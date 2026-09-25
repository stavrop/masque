import Foundation

/// Live implementation of `ICloudService` against Apple's private iCloud web
/// endpoints. Reimplements the pyicloud SRP + 2FA + accountLogin flow, then the
/// browser-extension HME calls. All state is actor-isolated.
///
/// ⚠️ These endpoints are unofficial and can change without notice.
actor ICloudLiveService: ICloudService {

    // MARK: Constants
    private let widgetKey = "d39ba9916b7251055b22c7f910e2ea796ee65e98b2ddecea8f5dde8d9d1a815d"
    private var clientId = "auth-" + UUID().uuidString.lowercased()
    private let authRoot = "https://idmsa.apple.com"
    private let auth = "https://idmsa.apple.com/appleauth/auth"
    private let home = "https://www.icloud.com"
    private let setup = "https://setup.icloud.com/setup/ws/1"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    private let trustTokenKey = "trustToken"
    private let sessionKey = "sessionBundle"

    // MARK: Session state (captured from response headers)
    private var sessionId: String?
    private var scnt: String?
    private var sessionToken: String?      // X-Apple-Session-Token -> dsWebAuthToken
    private var trustToken: String?        // X-Apple-TwoSV-Trust-Token (persisted)
    private var accountCountry: String?
    private(set) var hmeBase: URL?         // premiummailsettings host
    private(set) var dsid: String?         // dsInfo.dsid, binds service requests to the session

    // MARK: In-flight login
    private var srp: SRPClient?

    private let session: URLSession
    private let keychain = KeychainStore()

    /// Verbose step logging to stderr when MASQUE_DEBUG=1. Never logs secrets
    /// (no password, code, tokens, or cookies) — only step names + HTTP status.
    private let debug = ["1", "2"].contains(
        ProcessInfo.processInfo.environment["MASQUE_DEBUG"] ?? "")
    func dbg(_ s: String) {
        if debug { FileHandle.standardError.write(Data(("‹masque› " + s + "\n").utf8)) }
    }

    /// MASQUE_DEBUG=2 additionally dumps raw auth response bodies. These contain
    /// device names and Apple-masked phone numbers — never codes or tokens — so
    /// they stay off at the normal debug level.
    private let verbose = ProcessInfo.processInfo.environment["MASQUE_DEBUG"] == "2"
    func dbgBody(_ label: String, _ data: Data) {
        guard verbose else { return }
        let s = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        dbg("\(label) body: \(s.prefix(4000))")
    }

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        self.session = URLSession(configuration: config)
        self.trustToken = keychain.getCodable(String.self, for: trustTokenKey)
    }

    // MARK: - ICloudService: session lifecycle

    private struct SessionBundle: Codable {
        var cookies: [[String: String]]
        var dsid: String?
        var clientId: String
        var hmeBase: URL?
    }

    func restoreSession() async throws -> Bool {
        guard let bundle = keychain.getCodable(SessionBundle.self, for: sessionKey) else {
            dbg("restore: no stored session")
            return false
        }
        // Rehydrate cookies + service context, then prove the session is live.
        for props in bundle.cookies {
            var p: [HTTPCookiePropertyKey: Any] = [:]
            props.forEach { p[HTTPCookiePropertyKey($0.key)] = $0.value }
            if let c = HTTPCookie(properties: p) {
                session.configuration.httpCookieStorage?.setCookie(c)
            }
        }
        clientId = bundle.clientId
        dsid = bundle.dsid
        hmeBase = bundle.hmeBase
        dbg("restore: rehydrated session, verifying…")
        do {
            _ = try await listAddresses()
            dbg("restore: session is live")
            return true
        } catch {
            dbg("restore: stored session invalid (\(error.localizedDescription))")
            keychain.remove(sessionKey)
            hmeBase = nil; dsid = nil
            session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
            return false
        }
    }

    /// Persist the live session so a relaunch can restore it without re-login.
    private func persistSession() {
        let cookies = (session.configuration.httpCookieStorage?.cookies ?? [])
            .filter { $0.domain.contains("icloud.com") }
            .map { c -> [String: String] in
                var d = ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path]
                if c.isSecure { d["secure"] = "TRUE" }
                return d
            }
        let bundle = SessionBundle(cookies: cookies, dsid: dsid, clientId: clientId, hmeBase: hmeBase)
        keychain.setCodable(bundle, for: sessionKey)
        dbg("session persisted (\(cookies.count) cookies)")
    }

    func signIn(appleID: String, password: String) async throws -> SignInOutcome {
        resetTransient()
        let srp = SRPClient(username: appleID)
        self.srp = srp

        // 1. signin/init
        let initBody: [String: Any] = [
            "a": srp.aBase64,
            "accountName": appleID,
            "protocols": ["s2k", "s2k_fo"],
        ]
        dbg("signin/init → POST")
        let (initData, initResp) = try await send(
            "\(auth)/signin/init", method: "POST", json: initBody,
            headers: authHeaders(originIsIDMSA: true))
        dbg("signin/init ← \(initResp.statusCode)")
        guard initResp.statusCode == 200,
              let initJSON = try? JSONSerialization.jsonObject(with: initData) as? [String: Any],
              let saltB64 = initJSON["salt"] as? String, let salt = Data(base64Encoded: saltB64),
              let bB64 = initJSON["b"] as? String, let serverB = Data(base64Encoded: bB64),
              let c = initJSON["c"] as? String,
              let iteration = initJSON["iteration"] as? Int,
              let proto = initJSON["protocol"] as? String
        else {
            dbg("signin/init: unexpected body (bad account or protocol change)")
            throw ICloudError.invalidCredentials
        }
        dbg("srp: protocol=\(proto) iteration=\(iteration)")

        // 2. derive password key + SRP proof
        let passwordKey = CryptoUtils.derivePasswordKey(
            password: password, salt: salt, iterations: iteration, protocol: proto)
        let proof = srp.process(salt: salt, serverB: serverB, passwordKey: passwordKey)

        // 3. signin/complete
        var completeBody: [String: Any] = [
            "accountName": appleID,
            "c": c,
            "m1": proof.m1.base64EncodedString(),
            "m2": proof.m2.base64EncodedString(),
            "rememberMe": true,
        ]
        completeBody["trustTokens"] = trustToken.map { [$0] } ?? []

        dbg("signin/complete → POST (trustTokens=\(trustToken == nil ? 0 : 1))")
        let (completeData, completeResp) = try await send(
            "\(auth)/signin/complete?isRememberMeEnabled=true", method: "POST",
            json: completeBody, headers: authHeaders(originIsIDMSA: true))
        dbg("signin/complete ← \(completeResp.statusCode)")
        dbgBody("signin/complete", completeData)

        switch completeResp.statusCode {
        case 200:
            try await bootstrapICloud()
            return .authenticated
        case 409:
            // 2FA required. Apple has ALREADY pushed a prompt to the trusted
            // devices as part of this 409 — do NOT push again here. A second
            // request supersedes the first, so the device ends up showing
            // "a sign-in was requested" and then never displays a code sheet.
            // Resending is an explicit user action instead; see resendDeviceCode().
            dbg("2FA required (Apple pushed the prompt with the 409)")
            return .needsTwoFactor
        case 412:
            // Non-2FA "repair" precondition.
            _ = try await send("\(auth)/repair/complete", method: "POST", json: [:],
                               headers: authHeaders(originIsIDMSA: true))
            try await bootstrapICloud()
            return .authenticated
        case 401, 403:
            throw ICloudError.invalidCredentials
        default:
            throw ICloudError.server("Sign-in failed (HTTP \(completeResp.statusCode)).")
        }
    }

    func submitSecurityCode(_ code: String, phoneID: Int?) async throws {
        // An SMS code verifies against a different endpoint than a device code.
        let path: String
        let body: [String: Any]
        if let phoneID {
            path = "\(auth)/verify/phone/securitycode"
            body = ["phoneNumber": ["id": phoneID],
                    "securityCode": ["code": code],
                    "mode": "sms"]
        } else {
            path = "\(auth)/verify/trusteddevice/securitycode"
            body = ["securityCode": ["code": code]]
        }
        dbg("verify/securitycode → POST (\(phoneID == nil ? "device" : "sms"))")
        let (data, resp) = try await send(
            path, method: "POST",
            json: body, headers: authHeaders(originIsIDMSA: false))
        dbg("verify/securitycode ← \(resp.statusCode)")
        if resp.statusCode != 200 && resp.statusCode != 204 {
            // -21669 = wrong code
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sc = j["service_errors"] as? [[String: Any]],
               sc.first?["code"] as? String == "-21669" {
                throw ICloudError.invalidSecurityCode
            }
            throw ICloudError.invalidSecurityCode
        }
        try await trustSession()
        try await bootstrapICloud()
    }

    func signOut() async throws {
        _ = try? await send("\(setup)/logout", method: "POST",
                            json: ["trustBrowsers": false, "allBrowsers": false],
                            headers: defaultHeaders())
        keychain.remove(trustTokenKey)
        keychain.remove(sessionKey)
        resetTransient()
        trustToken = nil
        hmeBase = nil
        dsid = nil
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }

    // MARK: - Auth internals

    /// Read back the 2FA routes Apple offers for the pending sign-in.
    func twoFactorOptions() async throws -> TwoFactorOptions {
        dbg("authOptions → GET")
        let (data, resp) = try await send(auth, method: "GET", json: nil,
                                          headers: authHeaders(originIsIDMSA: false))
        dbg("authOptions ← \(resp.statusCode)")
        dbgBody("authOptions", data)
        guard resp.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unknown }

        let phones: [TwoFactorPhone] = (j["trustedPhoneNumbers"] as? [[String: Any]] ?? [])
            .compactMap { p in
                guard let id = p["id"] as? Int else { return nil }
                let number = (p["numberWithDialCode"] as? String)
                    ?? (p["obfuscatedNumber"] as? String)
                    ?? "Trusted number"
                return TwoFactorPhone(id: id, number: number)
            }
        // Apple sets `noTrustedDevices` when nothing can display a code.
        let noDevices = (j["noTrustedDevices"] as? Bool) ?? false

        // Accounts with security keys get an fsaChallenge and nothing else —
        // no trusted-device code, no SMS.
        var key: SecurityKeyChallenge?
        if let fsa = j["fsaChallenge"] as? [String: Any],
           let challenge = fsa["challenge"] as? String {
            let handles = (fsa["keyHandles"] as? [String])
                ?? (fsa["allowedCredentials"] as? String)?
                    .split(separator: ",").map(String.init)
                ?? []
            key = SecurityKeyChallenge(
                challenge: challenge,
                keyHandles: handles,
                rpId: (fsa["rpId"] as? String) ?? "apple.com",
                keyNames: (j["keyNames"] as? [String]) ?? [])
        }
        dbg("authOptions: trustedDevices=\(!noDevices) phones=\(phones.count) "
            + "securityKey=\(key != nil) handles=\(key?.keyHandles.count ?? 0)")
        return TwoFactorOptions(hasTrustedDevices: !noDevices, phones: phones,
                                securityKey: key)
    }

    /// Push a fresh code to the trusted devices. Failures surface, never swallowed.
    func resendDeviceCode() async throws {
        dbg("verify/trusteddevice (resend) → PUT")
        let (_, resp) = try await send("\(auth)/verify/trusteddevice/securitycode",
                                       method: "PUT", json: nil,
                                       headers: authHeaders(originIsIDMSA: false))
        dbg("verify/trusteddevice (resend) ← \(resp.statusCode)")
        guard (200...299).contains(resp.statusCode) else {
            if resp.statusCode == 403 || resp.statusCode == 412 {
                throw ICloudError.server(
                    "Apple wouldn’t send a code to a trusted device. Use a trusted "
                    + "phone number below, or read a code off a device directly: "
                    + "Settings › your name › Sign-In & Security › Get Verification Code.")
            }
            throw ICloudError.server("Couldn’t request a code (HTTP \(resp.statusCode)).")
        }
    }

    /// Complete 2FA with a hardware security key: get a WebAuthn assertion from
    /// the attached key, then post it to Apple. The key work happens off the
    /// actor because it blocks waiting for the user's touch.
    func authenticateWithSecurityKey(_ challenge: SecurityKeyChallenge) async throws {
        dbg("security key: requesting assertion (touch required)")
        let assertion = try await Task.detached(priority: .userInitiated) {
            try SecurityKeyAuthenticator().assert(challenge)
        }.value
        dbg("security key: assertion obtained — \(assertion.diagnostics)")

        // Apple wants the challenge echoed in the standard base64 alphabet,
        // while clientDataJSON carries the base64url form.
        let body: [String: Any] = [
            "challenge": challenge.challenge
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/"),
            "clientData": assertion.clientData,
            "signatureData": assertion.signature,
            "authenticatorData": assertion.authenticatorData,
            "userHandle": assertion.userHandle,
            "credentialID": assertion.credentialID,
            "rpId": challenge.rpId,
            "requestId": "",
        ]
        dbg("verify/security/key → POST")
        let (data, resp) = try await send("\(auth)/verify/security/key", method: "POST",
                                          json: body,
                                          headers: authHeaders(originIsIDMSA: false))
        dbg("verify/security/key ← \(resp.statusCode)")
        dbgBody("verify/security/key", data)
        // Apple acknowledges an accepted assertion with 409 as well as the
        // ordinary success codes — 409 here does NOT mean "still needs 2FA".
        guard [200, 204, 250, 409].contains(resp.statusCode) else {
            throw ICloudError.server("Security key rejected (HTTP \(resp.statusCode)).")
        }
        try await trustSession()
        try await bootstrapICloud()
    }

    /// Text a code to one of the account's trusted phone numbers.
    func sendPhoneCode(phoneID: Int) async throws {
        dbg("verify/phone → PUT")
        let body: [String: Any] = ["phoneNumber": ["id": phoneID], "mode": "sms"]
        let (_, resp) = try await send("\(auth)/verify/phone", method: "PUT",
                                       json: body,
                                       headers: authHeaders(originIsIDMSA: false))
        dbg("verify/phone ← \(resp.statusCode)")
        guard (200...299).contains(resp.statusCode) else {
            throw ICloudError.server("Couldn’t text a code (HTTP \(resp.statusCode)).")
        }
    }

    private func trustSession() async throws {
        dbg("2sv/trust → GET")
        let (_, resp) = try await send("\(auth)/2sv/trust", method: "GET",
                                       json: nil, headers: authHeaders(originIsIDMSA: false))
        dbg("2sv/trust ← \(resp.statusCode) (trustToken \(trustToken == nil ? "absent" : "captured"))")
        if let token = trustToken {
            keychain.setCodable(token, for: trustTokenKey)
        }
    }

    /// accountLogin → sets auth cookies and returns the per-account service hosts.
    private func bootstrapICloud() async throws {
        guard let dsWebAuthToken = sessionToken else { throw ICloudError.sessionExpired }
        let body: [String: Any] = [
            "accountCountryCode": accountCountry ?? "USA",
            "dsWebAuthToken": dsWebAuthToken,
            "extended_login": true,
            "trustToken": trustToken ?? "",
        ]
        dbg("accountLogin → POST")
        let (data, resp) = try await send("\(setup)/accountLogin", method: "POST",
                                          json: body, headers: defaultHeaders())
        dbg("accountLogin ← \(resp.statusCode)")
        guard resp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let webservices = json["webservices"] as? [String: Any],
              let hme = webservices["premiummailsettings"] as? [String: Any],
              let urlStr = hme["url"] as? String, let url = URL(string: urlStr)
        else {
            dbg("accountLogin: premiummailsettings host not found in webservices")
            throw ICloudError.server("Could not start iCloud session.")
        }
        // dsid binds subsequent service calls to this session (avoids "Invalid global session").
        if let dsInfo = json["dsInfo"] as? [String: Any], let d = dsInfo["dsid"] {
            dsid = (d as? String) ?? String(describing: d)
        }
        dbg("accountLogin: HME host = \(url.host ?? "?"), dsid=\(dsid ?? "nil")")
        hmeBase = url
        // The browser extension always hits /validate right after accountLogin —
        // this appears to activate the session for service (maildomains) calls.
        try? await validateSession()
        persistSession()
    }

    /// POST setup/validate — refreshes/activates the web session and webservices.
    private func validateSession() async throws {
        dbg("validate → POST")
        let (data, resp) = try await send("\(setup)/validate", method: "POST",
                                          json: nil, headers: defaultHeaders())
        dbg("validate ← \(resp.statusCode)")
        if resp.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ws = json["webservices"] as? [String: Any],
           let hme = ws["premiummailsettings"] as? [String: Any],
           let urlStr = hme["url"] as? String, let url = URL(string: urlStr) {
            hmeBase = url
        }
    }

    /// Query params iCloud web services require to validate the session.
    func serviceQueryItems() -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "clientBuildNumber", value: "2522Project44"),
            URLQueryItem(name: "clientMasteringNumber", value: "2522B2"),
            URLQueryItem(name: "clientId", value: clientId),
        ]
        if let dsid { items.append(URLQueryItem(name: "dsid", value: dsid)) }
        return items
    }

    /// Debug-only: log cookie names + domains (never values) the jar would send to `url`.
    func logCookies(for url: URL, label: String) {
        guard debug, let storage = session.configuration.httpCookieStorage else { return }
        let scoped = storage.cookies(for: url) ?? []
        let all = storage.cookies ?? []
        let names = scoped.map { "\($0.name)@\($0.domain)" }
        dbg("cookies \(label): \(scoped.count) sent to host / \(all.count) total → \(names.joined(separator: ", "))")
    }

    // MARK: - HTTP

    /// Sends a request, captures Apple session headers, returns (body, response).
    func send(_ urlString: String, method: String, json: Any?,
              headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw ICloudError.network("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw ICloudError.network("No HTTP response")
            }
            captureHeaders(http)
            if http.statusCode == 429 { throw ICloudError.rateLimited }
            return (data, http)
        } catch let e as ICloudError {
            throw e
        } catch {
            throw ICloudError.network(error.localizedDescription)
        }
    }

    private func captureHeaders(_ http: HTTPURLResponse) {
        func header(_ name: String) -> String? {
            http.value(forHTTPHeaderField: name)
        }
        if let v = header("X-Apple-ID-Session-Id") { sessionId = v }
        if let v = header("scnt") { scnt = v }
        if let v = header("X-Apple-Session-Token") { sessionToken = v }
        if let v = header("X-Apple-TwoSV-Trust-Token") { trustToken = v }
        if let v = header("X-Apple-ID-Account-Country") { accountCountry = v }
    }

    private func authHeaders(originIsIDMSA: Bool) -> [String: String] {
        var h: [String: String] = [
            "Accept": "application/json, text/javascript",
            "Content-Type": "application/json",
            "X-Apple-OAuth-Client-Id": widgetKey,
            "X-Apple-OAuth-Client-Type": "firstPartyAuth",
            "X-Apple-OAuth-Redirect-URI": home,
            "X-Apple-OAuth-Require-Grant-Code": "true",
            "X-Apple-OAuth-Response-Mode": "web_message",
            "X-Apple-OAuth-Response-Type": "code",
            "X-Apple-OAuth-State": clientId,
            "X-Apple-Widget-Key": widgetKey,
            "Origin": originIsIDMSA ? authRoot : home,
            "Referer": (originIsIDMSA ? authRoot : home) + "/",
        ]
        if let sessionId { h["X-Apple-ID-Session-Id"] = sessionId }
        if let scnt { h["scnt"] = scnt }
        return h
    }

    func defaultHeaders() -> [String: String] {
        [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Origin": home,
            "Referer": home + "/",
        ]
    }

    private func resetTransient() {
        sessionId = nil; scnt = nil; sessionToken = nil; accountCountry = nil; srp = nil
    }
}

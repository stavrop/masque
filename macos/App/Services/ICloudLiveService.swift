import Foundation

/// Live implementation of `ICloudService` against Apple's private iCloud web
/// endpoints. Reimplements the pyicloud SRP + 2FA + accountLogin flow, then the
/// browser-extension HME calls. All state is actor-isolated.
///
/// ⚠️ These endpoints are unofficial and can change without notice.
actor ICloudLiveService: ICloudService {

    // MARK: Constants
    private let widgetKey = "d39ba9916b7251055b22c7f910e2ea796ee65e98b2ddecea8f5dde8d9d1a815d"
    private let clientId = "auth-" + UUID().uuidString.lowercased()
    private let authRoot = "https://idmsa.apple.com"
    private let auth = "https://idmsa.apple.com/appleauth/auth"
    private let home = "https://www.icloud.com"
    private let setup = "https://setup.icloud.com/setup/ws/1"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    private let trustTokenKey = "trustToken"

    // MARK: Session state (captured from response headers)
    private var sessionId: String?
    private var scnt: String?
    private var sessionToken: String?      // X-Apple-Session-Token -> dsWebAuthToken
    private var trustToken: String?        // X-Apple-TwoSV-Trust-Token (persisted)
    private var accountCountry: String?
    private(set) var hmeBase: URL?         // premiummailsettings host

    // MARK: In-flight login
    private var srp: SRPClient?

    private let session: URLSession
    private let keychain = KeychainStore()

    /// Verbose step logging to stderr when MASQUE_DEBUG=1. Never logs secrets
    /// (no password, code, tokens, or cookies) — only step names + HTTP status.
    private let debug = ProcessInfo.processInfo.environment["MASQUE_DEBUG"] == "1"
    func dbg(_ s: String) {
        if debug { FileHandle.standardError.write(Data(("‹masque› " + s + "\n").utf8)) }
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

    func restoreSession() async throws -> Bool {
        // Cookies are in-memory only, so a cold launch has no live session. If a
        // trust token is stored we still require an explicit sign-in (which will
        // skip 2FA thanks to the token) — so report "not restored" here.
        return false
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
        let (_, completeResp) = try await send(
            "\(auth)/signin/complete?isRememberMeEnabled=true", method: "POST",
            json: completeBody, headers: authHeaders(originIsIDMSA: true))
        dbg("signin/complete ← \(completeResp.statusCode)")

        switch completeResp.statusCode {
        case 200:
            try await bootstrapICloud()
            return .authenticated
        case 409:
            // 2FA required — push a code to trusted devices.
            dbg("2FA required; pushing security code")
            try? await pushSecurityCode()
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

    func submitSecurityCode(_ code: String) async throws {
        let body: [String: Any] = ["securityCode": ["code": code]]
        dbg("verify/securitycode → POST")
        let (data, resp) = try await send(
            "\(auth)/verify/trusteddevice/securitycode", method: "POST",
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
        resetTransient()
        trustToken = nil
        hmeBase = nil
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }

    // MARK: - Auth internals

    private func pushSecurityCode() async throws {
        _ = try await send("\(auth)/verify/trusteddevice/securitycode", method: "PUT",
                           json: nil, headers: authHeaders(originIsIDMSA: false))
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
        dbg("accountLogin: HME host = \(url.host ?? "?")")
        hmeBase = url
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

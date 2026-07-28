import Foundation

/// Hide My Email endpoints on the `premiummailsettings` host. `list` is v2,
/// everything else is v1 (per the browser extension). All calls ride the auth
/// cookies set by `accountLogin` and check the `success` envelope flag.
extension ICloudLiveService {

    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool?
        let result: T
    }
    private struct ListResult: Decodable { let hmeEmails: [HMEAddress] }
    private struct GenerateResult: Decodable { let hme: String }
    private struct ReserveResult: Decodable { let hme: HMEAddress }

    func listAddresses() async throws -> [HMEAddress] {
        let data = try await hmeCall(version: 2, "hme/list", method: "GET", body: nil)
        return try decode(Envelope<ListResult>.self, from: data).result.hmeEmails
    }

    func generateAddress() async throws -> String {
        let data = try await hmeCall(version: 1, "hme/generate", method: "POST", body: [:])
        return try decode(Envelope<GenerateResult>.self, from: data).result.hme
    }

    func reserveAddress(hme: String, label: String, note: String) async throws -> HMEAddress {
        let data = try await hmeCall(version: 1, "hme/reserve", method: "POST",
                                     body: ["hme": hme, "label": label, "note": note])
        return try decode(Envelope<ReserveResult>.self, from: data).result.hme
    }

    func setActive(_ active: Bool, anonymousId: String) async throws {
        let path = active ? "hme/reactivate" : "hme/deactivate"
        _ = try await hmeCall(version: 1, path, method: "POST", body: ["anonymousId": anonymousId])
    }

    func deleteAddress(anonymousId: String) async throws {
        _ = try await hmeCall(version: 1, "hme/delete", method: "POST",
                              body: ["anonymousId": anonymousId])
    }

    func updateMetadata(anonymousId: String, label: String, note: String) async throws {
        _ = try await hmeCall(version: 1, "hme/updateMetaData", method: "POST",
                              body: ["anonymousId": anonymousId, "label": label, "note": note])
    }

    // MARK: - Plumbing

    /// Performs an HME request and returns the body after verifying the envelope.
    private func hmeCall(version: Int, _ path: String, method: String,
                         body: [String: Any]?) async throws -> Data {
        guard let base = hmeBase else { throw ICloudError.notAuthenticated }
        let url = base.appendingPathComponent("v\(version)").appendingPathComponent(path)
        let (data, resp) = try await send(url.absoluteString, method: method,
                                          json: body, headers: defaultHeaders())
        dbg("\(method) v\(version)/\(path) ← \(resp.statusCode)")
        switch resp.statusCode {
        case 200, 204:
            break
        case 401, 421, 450:
            throw ICloudError.sessionExpired
        default:
            throw ICloudError.server("Request failed (HTTP \(resp.statusCode)).")
        }
        // Envelope success flag: some errors return 200 with success=false.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = obj["success"] as? Bool, success == false {
            let msg = (obj["error"] as? [String: Any])?["errorMessage"] as? String
                ?? (obj["reason"] as? String) ?? "iCloud rejected the request."
            throw ICloudError.server(msg)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ICloudError.server("Unexpected response from iCloud.") }
    }
}

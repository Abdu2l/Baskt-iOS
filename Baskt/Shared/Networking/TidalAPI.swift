// TIDAL source, same approach as monochrome.tf: public browser client
// credentials mint an app token; catalog + streams from api.tidal.com.

import Foundation

struct TidalHit {
    let id: String
    let title: String
    let artists: String
    let image: String
    let durationSeconds: Int?
}

final class TidalAPI {
    static let shared = TidalAPI()
    private init() {}

    private let apiBase = "https://api.tidal.com/v1"
    private let tokenURL = URL(string: "https://auth.tidal.com/v1/oauth2/token")!
    private let clientID = "txNoH4kkV41MfH25"
    private let clientSecret = "dQjy0MinCEvxi1O4UmxvxWnDjt4cgHBPw8ll6nYBk98="

    private var token: String?
    private var tokenExpiry = Date.distantPast
    private let lock = NSLock()

    func search(_ query: String, limit: Int = 8) async -> [TidalHit] {
        guard let auth = await appToken() else { return [] }
        guard var comps = URLComponents(string: apiBase + "/search") else { return [] }
        comps.queryItems = [
            .init(name: "query", value: query),
            .init(name: "limit", value: String(max(1, min(limit, 20)))),
            .init(name: "countryCode", value: "US"),
        ]
        guard let url = comps.url else { return [] }
        do {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Bearer \(auth)", forHTTPHeaderField: "authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let items = ((json?["data"] as? [String: Any])?["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
            return items.compactMap { parseTrack($0) }
        } catch {
            return []
        }
    }

    func streamURL(id: String) async -> URL? {
        guard let auth = await appToken() else { return nil }
        guard var comps = URLComponents(string: apiBase + "/tracks/\(id)/playbackinfo") else { return nil }
        comps.queryItems = [
            .init(name: "audioquality", value: "LOSSLESS"),
            .init(name: "playbackmode", value: "STREAM"),
            .init(name: "assetpresentation", value: "FULL"),
            .init(name: "countryCode", value: "US"),
        ]
        guard let url = comps.url else { return nil }
        do {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Bearer \(auth)", forHTTPHeaderField: "authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let manifestB64 = json["manifest"] as? String,
                  let manifestData = Data(base64Encoded: manifestB64),
                  let manifest = String(data: manifestData, encoding: .utf8) else { return nil }
            // Classic BTS manifest: JSON with urls[].
            if let mData = manifest.data(using: .utf8),
               let mJson = try? JSONSerialization.jsonObject(with: mData) as? [String: Any],
               let urls = mJson["urls"] as? [String],
               let first = urls.first, first.hasPrefix("http") {
                return URL(string: first)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func parseTrack(_ item: [String: Any]) -> TidalHit? {
        let id: String
        if let n = item["id"] as? Int { id = String(n) }
        else if let s = item["id"] as? String, !s.isEmpty { id = s }
        else { return nil }
        guard let title = item["title"] as? String, !title.isEmpty else { return nil }
        var artists: [String] = []
        if let arr = item["artists"] as? [[String: Any]] {
            artists = arr.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
        }
        if artists.isEmpty, let a = item["artist"] as? [String: Any], let n = a["name"] as? String, !n.isEmpty {
            artists = [n]
        }
        var image = ""
        if let album = item["album"] as? [String: Any], let cover = album["cover"] as? String, !cover.isEmpty {
            image = "https://resources.tidal.com/images/\(cover.replacingOccurrences(of: "-", with: "/"))/640x640.jpg"
        }
        var duration: Int? = nil
        if let d = item["duration"] as? Int, d > 0 { duration = d }
        return TidalHit(id: id, title: title, artists: artists.joined(separator: ", "), image: image, durationSeconds: duration)
    }

    private func appToken() async -> String? {
        lock.lock()
        let cached = token
        let valid = Date() < tokenExpiry
        lock.unlock()
        if let cached, valid { return cached }
        do {
            var req = URLRequest(url: tokenURL, timeoutInterval: 15)
            let creds = "\(clientID):\(clientSecret)"
            req.setValue("Basic \(Data(creds.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpMethod = "POST"
            req.httpBody = "grant_type=client_credentials".data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let access = json["access_token"] as? String, !access.isEmpty else { return nil }
            let expiresIn = json["expires_in"] as? Double ?? 3600
            lock.lock()
            token = access
            tokenExpiry = Date().addingTimeInterval(expiresIn - 60)
            lock.unlock()
            return access
        } catch {
            return nil
        }
    }
}

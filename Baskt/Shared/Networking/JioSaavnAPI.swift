// JioSaavn direct API: search + DES-decrypted 320kbps stream URLs.
// Same endpoints + key as the Android app (sumitkolhe/jiosaavn-api approach).

import Foundation
import CommonCrypto

struct SaavnTrack {
    let id: String
    let title: String
    let artists: String
    let image: String
    let durationSeconds: Int?
}

final class JioSaavnAPI {
    static let shared = JioSaavnAPI()
    private init() {}

    private let base = "https://www.jiosaavn.com/api.php"
    private let userAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    func search(_ query: String, limit: Int = 10) async -> [SaavnTrack] {
        guard var comps = URLComponents(string: base) else { return [] }
        comps.queryItems = [
            .init(name: "__call", value: "search.getResults"),
            .init(name: "q", value: query),
            .init(name: "p", value: "1"),
            .init(name: "n", value: String(max(1, min(limit, 20)))),
            .init(name: "_format", value: "json"),
            .init(name: "_marker", value: "0"),
            .init(name: "api_version", value: "4"),
            .init(name: "ctx", value: "web6dot0"),
        ]
        guard let url = comps.url else { return [] }
        do {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = json?["results"] as? [[String: Any]] ?? []
            return results.compactMap { item -> parseTrack(item) }
        } catch {
            return []
        }
    }

    func streamURL(id: String) async -> URL? {
        guard var comps = URLComponents(string: base) else { return nil }
        comps.queryItems = [
            .init(name: "__call", value: "song.getDetails"),
            .init(name: "pids", value: id),
            .init(name: "_format", value: "json"),
            .init(name: "_marker", value: "0"),
            .init(name: "api_version", value: "4"),
            .init(name: "ctx", value: "web6dot0"),
        ]
        guard let url = comps.url else { return nil }
        do {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let songs = json?["songs"] as? [[String: Any]] ?? []
            for song in songs {
                let info = song["more_info"] as? [String: Any] ?? [:]
                if let enc = info["encrypted_media_url"] as? String, !enc.isEmpty,
                   let stream = Self.decryptTo320(enc) {
                    return URL(string: stream)
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func parseTrack(_ item: [String: Any]) -> SaavnTrack? {
        guard let id = item["id"] as? String, !id.isEmpty,
              let title = item["title"] as? String, !title.isEmpty else { return nil }
        let type = item["type"] as? String ?? ""
        guard type == "song" || type.isEmpty else { return nil }
        let info = item["more_info"] as? [String: Any] ?? [:]
        var artists = info["primary_artists"] as? String ?? ""
        if artists.isEmpty { artists = info["singers"] as? String ?? "" }
        var image = item["image"] as? String ?? ""
        image = image.replacingOccurrences(of: "150x150", with: "500x500")
            .replacingOccurrences(of: "50x50", with: "500x500")
        if image.hasPrefix("http://") { image = "https://" + image.dropFirst(7) }
        var duration: Int? = nil
        if let d = info["duration"] as? String { duration = Int(d) }
        if duration == nil, let d = info["duration"] as? Int { duration = d }
        return SaavnTrack(id: id, title: title, artists: artists, image: image, durationSeconds: duration)
    }

    /// DES-ECB decrypt (PKCS7) with the public JioSaavn key, then swap _96 → _320.
    static func decryptTo320(_ encrypted: String) -> String? {
        guard let data = Data(base64Encoded: encrypted) else { return nil }
        let key = Array("38346591".utf8)
        var out = Data(count: data.count + 8)
        var outLen = 0
        let status = data.withUnsafeBytes { dataPtr in
            out.withUnsafeMutableBytes { outPtr in
                key.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmDES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyPtr.baseAddress, kCCKeySizeDES,
                        nil,
                        dataPtr.baseAddress, data.count,
                        outPtr.baseAddress, out.count,
                        &outLen
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = outLen
        guard var str = String(data: out, encoding: .utf8) else { return nil }
        str = str.trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
        str = str.replacingOccurrences(of: "_96", with: "_320")
        guard str.hasPrefix("http") else { return nil }
        return str
    }
}

// Baskt for iPad — unified song model across sources.

import Foundation

enum MusicSource: String, Codable {
    case jiosaavn
    case tidal
}

struct AppSong: Identifiable, Hashable {
    let id: String  // "js:<pid>" or "td:<trackId>"
    let title: String
    let artists: String
    let imageURL: URL?
    let durationSeconds: Int?
    let source: MusicSource

    var displayArtists: String { artists.isEmpty ? "Unknown artist" : artists }
}

// Playback: AVQueuePlayer fed by TIDAL → JioSaavn auto-fallback.

import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var queue: [AppSong] = []
    @Published var index: Int = 0
    @Published var isPlaying = false
    @Published var isLoading = false

    private var player: AVQueuePlayer?
    private var timeObserver: Any?

    var current: AppSong? {
        guard queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    func play(_ songs: [AppSong], startAt: Int = 0) {
        queue = songs
        index = max(0, min(startAt, songs.count - 1))
        playCurrent()
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func next() {
        guard index + 1 < queue.count else { return }
        index += 1
        playCurrent()
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        playCurrent()
    }

    private func playCurrent() {
        guard let song = current else { return }
        isLoading = true
        isPlaying = false
        player?.pause()
        Task {
            let url = await resolve(song)
            guard let url else {
                await MainActor.run { self.isLoading = false }
                return
            }
            await MainActor.run {
                let item = AVPlayerItem(url: url)
                let p = AVQueuePlayer(playerItem: item)
                p.automaticallyWaitsToMinimizeStalling = true
                self.player = p
                self.isLoading = false
                p.play()
                self.isPlaying = true
                self.publishNowPlaying(song: song)
            }
        }
    }

    private func resolve(_ song: AppSong) async -> URL? {
        switch song.source {
        case .tidal:
            if let url = await TidalAPI.shared.streamURL(id: song.id) { return url }
            // TIDAL dead → fall through to JioSaavn by title.
            guard let hit = await JioSaavnAPI.shared.search(song.title + " " + song.displayArtists, limit: 5).first else { return nil }
            return await JioSaavnAPI.shared.streamURL(id: hit.id)
        case .jiosaavn:
            return await JioSaavnAPI.shared.streamURL(id: song.id)
        }
    }

    private func publishNowPlaying(song: AppSong) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.displayArtists,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let img = song.imageURL {
            URLSession.shared.dataTask(with: img) { data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                Task { @MainActor in
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
                }
            }.resume()
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

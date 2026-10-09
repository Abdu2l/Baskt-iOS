// Baskt for iPad: search across TIDAL + JioSaavn, play, now playing.

import SwiftUI

struct ContentView: View {
    @StateObject private var player = PlayerManager.shared
    @State private var query = ""
    @State private var results: [AppSong] = []
    @State private var searching = false
    @State private var showPlayer = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Search") {
                    HStack {
                        TextField("Songs, artists…", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { runSearch() }
                        if searching { ProgressView() }
                    }
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { song in
                            SongRow(song: song) {
                                if let i = results.firstIndex(of: song) {
                                    player.play(results, startAt: i)
                                    showPlayer = true
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Search TIDAL + JioSaavn. Playback falls back automatically.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("About") {
                    Label("Made by Abdu2l", systemImage: "person.circle")
                    Link("GitHub", destination: URL(string: "https://github.com/Abdu2l")!)
                    Link("Instagram @khhezer", destination: URL(string: "https://instagram.com/khhezer")!)
                }
            }
            .navigationTitle("Baskt")
        } detail: {
            NowPlayingView()
        }
        .sheet(isPresented: $showPlayer) { NowPlayingView() }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            async let tidal = TidalAPI.shared.search(q, limit: 10)
            async let saavn = JioSaavnAPI.shared.search(q, limit: 10)
            let (t, s) = await (tidal, saavn)
            let songs: [AppSong] = t.map {
                AppSong(id: "td:\($0.id)", title: $0.title, artists: $0.artists,
                        imageURL: URL(string: $0.image), durationSeconds: $0.durationSeconds, source: .tidal)
            } + s.map {
                AppSong(id: "js:\($0.id)", title: $0.title, artists: $0.artists,
                        imageURL: URL(string: $0.image), durationSeconds: $0.durationSeconds, source: .jiosaavn)
            }
            await MainActor.run {
                results = songs
                searching = false
            }
        }
    }
}

struct SongRow: View {
    let song: AppSong
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                AsyncImage(url: song.imageURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).lineLimit(1)
                    Text(song.displayArtists).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(song.source == .tidal ? "TIDAL" : "Saavn")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary).clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

struct NowPlayingView: View {
    @StateObject private var player = PlayerManager.shared

    var body: some View {
        VStack(spacing: 20) {
            if let song = player.current {
                AsyncImage(url: song.imageURL) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 16).fill(.quaternary)
                }
                .frame(maxWidth: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(song.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(song.displayArtists).foregroundStyle(.secondary)
                if player.isLoading { ProgressView() }
                HStack(spacing: 40) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.title)
                    }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title)
                    }
                }
                .disabled(player.queue.isEmpty)
            } else {
                ContentUnavailableView("Nothing playing", systemImage: "music.note",
                                       description: Text("Search and tap a song."))
            }
            Spacer()
        }
        .padding(32)
        .navigationTitle("Now Playing")
    }
}

# Baskt for iPad

Native iPadOS music player: TIDAL + JioSaavn sources with automatic fallback,
background audio, lock-screen controls. No YouTube.

## Status

Early scaffold (v0.1.0): search across both sources, playback with auto-fallback,
now-playing UI, Made-by-Abdu2l credits. Lyrics, downloads, and playlists come next.

## Build

Requires Xcode 16+ on a Mac (cannot be built on Linux/Windows):

```sh
open Baskt.xcodeproj
```

Run on iPad (iPad-only target, iOS 17+). Sideload via Xcode + free Apple ID,
AltStore, or a paid developer account.

## Sources

- TIDAL (`api.tidal.com`, public browser credentials, same approach as monochrome.tf)
- JioSaavn direct API (DES-decrypted 320kbps URLs)

## License

GPLv3 — see LICENSE. Based on open-source work; see About in-app.

# Contributing to Deckle

Thanks for considering it! Deckle is a small, focused app — contributions that keep it small and focused are the most welcome kind.

## Building

```sh
git clone https://github.com/Kelvanic/deckle.git
cd deckle
swift run        # run unbundled for development
swift test       # full test suite
make app         # build dist/Deckle.app (ad-hoc signed)
```

No third-party dependencies — Swift and Apple frameworks, built with SwiftPM. Requires macOS 13+ and a Swift 5.9 or newer toolchain (Xcode 15 or later, or its command line tools).

## Making changes

- `main` is protected: branch → PR. There is no CI on pull requests, so run `swift test` locally and include the result. For release-sensitive changes, also run `make build UNIVERSAL=1`, which compiles both architectures as the release workflow does.
- Look at [`good first issue`](https://github.com/Kelvanic/deckle/labels/good%20first%20issue) for curated starting points, or open a [Discussion](https://github.com/Kelvanic/deckle/discussions) before larger work so we agree on direction first.
- Code style: match what's around you. Comments explain *constraints*, not what the next line does.
- One feature or fix per PR. Include screenshots for UI changes.
- [`AGENTS.md`](AGENTS.md) lists the architectural invariants and testing expectations in full.

## Architecture in 60 seconds

- `TexturePreset.swift` — paper recipes (data) and engine versions. `TextureRenderer.swift` — renders them into small seamless tiles: the original value-noise engine, the FFT-based spectral engine, and its fiber layers.
- `OverlayWindow`/`OverlayController` — one click-through window per display; the texture is a CALayer pattern color (retained-mode — nothing renders per frame).
- `AppState` — all settings, persisted to UserDefaults. `MenuView` and its child views — the menu bar popover UI.
- `PaperMill` — custom papers, with import and export. `URLCommands` — the `deckle://` automation surface. `UpdateManager` — GitHub release updates.

## Releases

The maintainer tags `vX.Y.Z`; CI then runs the tests, builds a universal DMG, signs it with a Developer ID, notarizes and staples it, and publishes it with a SHA-256 checksum. The app notices the new release and offers **Update** in the menu, or installs it automatically if the user turned that on.

## License

MIT. By contributing you agree your contributions are MIT-licensed too.

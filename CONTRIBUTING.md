# Contributing

Bug reports, layout ideas and focused pull requests are welcome.

1. Fork and build using the README instructions on macOS 15+ with Swift 6+.
2. Keep changes focused and describe the user-visible result.
3. Run `swift run SongAmbientChecks` on a Mac with Metal support and build with `./script/build_and_run.sh --build`.
4. For visual changes, include an image or short recording using the authored demo rather than private playback or copyrighted lyric excerpts.

Preserve Spotify-only capture. Never add a system-mix fallback. Keep exact and estimated timing clearly distinguished; do not invent provider timestamps or add song-specific timing exceptions. Do not commit credentials, local preferences, downloaded lyrics/artwork, app bundles, extracted third-party code or reverse-engineering archives.

This release has been checked on Apple silicon. Intel, multi-monitor, sleep/wake and different output-device reports are useful; explain what you actually tested. Do not claim validation you have not performed.

By submitting a contribution, you agree to license your contribution under this project's MIT license. Preserve third-party notices.

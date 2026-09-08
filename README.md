# Caravay Audio

A macOS command-line tool that captures system audio and streams raw PCM to
stdout. Save recordings or pipe audio into an encoder or another application
without a virtual audio device.

Output is headerless Float32 little-endian PCM, mono, 16 kHz. Diagnostics go to
stderr. Capture includes other applications and excludes this process's audio;
it does not capture the microphone.

## Install with Homebrew

Requires macOS 13+ on Apple Silicon. The tap installs a prebuilt binary;
no Swift toolchain is needed.

```sh
brew install tjvjk/tap/caravay-audio
caravay-audio --version
```

To update, run `brew update` followed by `brew upgrade caravay-audio`.
To uninstall, run `brew uninstall caravay-audio`.

## Install from source

Requires macOS 13+ and Apple Command Line Tools with Swift 6.2+ to build.
Validated locally on Apple Silicon; Intel support has not been tested.

From this repository:

```sh
make install
export PATH="$HOME/.local/bin:$PATH"
caravay-audio --version
```

The default destination is `~/.local/bin`. Add that directory to your shell PATH
permanently if needed. Override the location with `make install PREFIX=/your/prefix`.
To remove the installation, delete that prefix's `bin/caravay-audio` file.

## Use

```sh
caravay-audio > recording.f32le
```

On first capture, allow Screen & System Audio Recording in System Settings →
Privacy & Security for the executable or its launching terminal. Retry after
permission is granted; restart the terminal if macOS requests it.
Audio remains audible through your selected output device. Stop with Ctrl-C.
Do not merge stderr into stdout.

Use `--help` for options and `--verbose` for timing and queue diagnostics.
See [PROTOCOL.md](PROTOCOL.md) for the process contract.

## Development and releases

Run `make check` to lint Swift and run the Swift Testing process tests.
Only the Swift toolchain is required; there are no package dependencies.
Tests require macOS 14+; the release executable still targets macOS 13+.
With full Xcode, you can also run `swift test` directly. `make check` handles
the framework search paths needed by standalone Command Line Tools.
Tests launch the debug executable with a controlled producer and do not request recording permission. Release builds
exclude this producer.

`make dist` creates a native-architecture macOS archive and SHA-256 checksum in
`dist/`. CI checks the code and uploads the archive as a workflow artifact.
Public archives are attached to [GitHub Releases](https://github.com/tjvjk/caravay-audio/releases).
The [Homebrew tap](https://github.com/tjvjk/homebrew-tap) installs the Apple Silicon
archive. Archives are currently unsigned and not notarized.
Bump the version in `Makefile` and `Sources/CaravayAudio/main.swift` together,
publish the archive and checksum under the corresponding version tag, then update
the URL, version and SHA-256 in the tap's `Formula/caravay-audio.rb`.

For a real capture smoke test, run capture while playing known audio, stop with
Ctrl-C, and verify that the resulting stream contains audio and playback remains
audible. This manual check is not covered by the controlled tests.

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

[MIT](LICENSE).

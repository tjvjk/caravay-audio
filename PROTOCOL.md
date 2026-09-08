# Process contract

Run `caravay-audio [--verbose]`. No input is read from stdin.

- stdout: headerless little-endian IEEE Float32, 16,000 frames/second, one channel.
- stderr: human-readable status and diagnostics; never PCM.
- `--help`, `--version`: print text to stdout and exit without requesting capture.
- Unknown arguments fail before capture starts.
- SIGINT stops capture, drains accepted PCM and exits 130; downstream sees EOF.
- Capture, conversion, permission, output and overload errors exit 1.
- A closed downstream pipe reports `broken_pipe` and exits 1.
- Buffering is bounded to 64 chunks; overload fails explicitly without silently
  dropping samples. A stalled consumer must be stopped separately if draining
  cannot progress.

No language processing, microphone capture, device rerouting or keepalive
samples are added. Output sample positions are relative to captured PCM, not
wall-clock timestamps. Permission and device behavior depend on macOS.

With `--verbose`, stderr includes `first_pcm: uptime_seconds=...` and
`capture_stopped: reason=... capture_queue_peak=...` for integration diagnostics.

Debug builds accept `CARAVAY_AUDIO_TEST_*` environment variables used by the
process tests. These are private test controls, absent from release builds.

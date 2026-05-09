# Moonlight/Sunshine Mouse Research Monorepo

This repository is organized as a two-module workspace for Moonlight client and Sunshine server work, with a focus on accurate Parsec-like mouse and cursor behavior.

## Modules

- `client/` contains the Moonlight macOS client.
- `server/` contains the Sunshine fork imported from upstream.

## Build Entry Points

- Client: open `client/Moonlight.xcodeproj` in Xcode.
- Server: configure/build from `server/CMakeLists.txt` on Windows only.

## Current Test Topology

- Client: Moonlight for macOS, built from `client/`.
- Server: Sunshine on Windows 11, built from `server/` on the Windows host.

The Sunshine server in this monorepo is intentionally Windows-only. `server/CMakeLists.txt` fails configuration on macOS, Linux, and other non-Windows hosts so server work does not accidentally target unsupported platform paths.

When debugging client/server behavior, do not assume the macOS Sunshine capture path is active. The current server target is Windows 11, so host-side audio instrumentation should be added under the Windows platform code rather than `server/src/platform/macos/`.

## Audio Debugging Notes

Recent client diagnostics write to `/tmp/moonlight_audio_diagnostics.log` on macOS. A crackling run showed client audio starvation during the bad window:

- `decoded` dropped below the expected roughly 1000 packets per 5 seconds.
- `outputUnderruns` increased at the same time.
- `decodeErrors`, `ringDrops`, `invalidFrames`, and `clipped` stayed at zero.

That points away from client-side clipping, Opus decode corruption, or client ring-buffer overflow. The next useful checks are Windows Sunshine audio capture/send diagnostics and, as a client-side mitigation test, increasing `CIRCULAR_BUFFER_DURATION` in `client/Limelight/Stream/Connection.m`.

Enable diagnostics only while capturing a repro:

- Client: open the Debug settings pane and turn on `Audio Diagnostics Logging` for the target host. This writes `/tmp/moonlight_audio_diagnostics.log`, `/tmp/moonlight_audio_network.log`, and a short decoded PCM dump.
- Windows Sunshine server: set `SUNSHINE_AUDIO_DIAGNOSTICS=1` before launching Sunshine. This adds 5-second capture, encode, and audio send-cadence summaries to the Sunshine log.

## Windows Server Build

Sunshine server builds are supported only on Windows in this monorepo. Do not configure or build `server/` on macOS or Linux; those hosts fail fast by design. Build the `server/` module on the target Windows architecture.

Use the explicit monorepo instructions in `server/WINDOWS_BUILD.md`.

## Sunshine Upstream Sync

Sunshine is vendored into `server/` with `git subtree`.

```bash
git fetch sunshine-upstream master
git subtree pull --prefix=server sunshine-upstream master --squash
```

See `server/FORK_NOTES.md` for the imported upstream commit and fork purpose.

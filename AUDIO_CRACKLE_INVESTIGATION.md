# Audio Crackle Investigation

## Problem Statement

Audio crackling has not been reduced by the attempted fixes so far. The current evidence points to intermittent audio starvation rather than clipping, decoder failure, or client ring-buffer overflow, but the source of the starvation is still unproven.

Current topology:

- Client: Moonlight macOS from `client/`.
- Server: Sunshine on Windows 11 from `server/`.

Do not treat `server/src/platform/macos/` as the active host audio path for this issue.

## Change Ledger

| Change | Location | Intent | Current Evidence | Status |
| --- | --- | --- | --- | --- |
| Client AudioQueue counters and `/tmp/moonlight_audio_diagnostics.log` | `client/Limelight/Stream/Connection.m` in commit `0a584a2b` | Count decoded packets, decode errors, ring drops, output underruns, invalid frame counts, clipping, and queue depth. | A bad run showed `decoded` below the expected roughly 1000 packets per 5 seconds while `outputUnderruns` increased. `decodeErrors`, `ringDrops`, `invalidFrames`, and `clipped` stayed at zero. | Useful diagnostic. Keep until source is found. |
| Server audio sample sanitization | `server/src/audio.cpp` in commit `0a584a2b` | Clamp non-finite/out-of-range host samples before Opus encode. | Client logs showed no clipping and no decode errors, so this probably did not target the observed failure mode. | Low-confidence mitigation. Not proven relevant. |
| macOS Sunshine capture diagnostics and larger macOS capture ring | `server/src/platform/macos/av_audio.*`, `server/src/platform/macos/microphone.mm` in commit `0a584a2b` | Detect macOS host capture underflow/drop behavior. | Current server target is Windows 11, so this does not instrument the active server path. | Wrong platform for this bug. Do not use as evidence. |
| README topology/debug notes | `README.md` uncommitted | Record that the active host is Windows and summarize client evidence. | Matches the current repo and logs. | Useful. Keep. |
| Client network receive counters and `/tmp/moonlight_audio_network.log` | `client/moonlight-common/moonlight-common-c/src/AudioStream.c` uncommitted | Count UDP receive, timeouts, initial drops, RTP queue handling, FEC recovery, and PLC calls. | Active stream sample showed ~1500 received UDP packets per 5 seconds and ~1000 handled audio packets per 5 seconds, with no recovery/PLC. Need a crackling capture from the bad window. | Useful diagnostic. Keep, but gather a bad run. |
| macOS socket QoS for audio UDP | `client/moonlight-common/moonlight-common-c/src/PlatformSockets.*` uncommitted | Prioritize audio traffic locally. | No evidence yet that it reduces crackle. It also changes behavior during measurement. | Test separately after baseline diagnosis. |
| SDL audio output rewrite, decoded PCM dump, and SDL queue backpressure | `client/Limelight/Stream/Connection.m` uncommitted | Replace AudioQueue output path and dump decoded PCM. | This is a major behavior change, not just instrumentation. It may hide or introduce timing problems, so it is not a clean diagnostic baseline. | Isolate on a separate branch or revert before the next baseline test. |
| SDL backlog threshold instrumentation and tuning | `client/Limelight/Stream/Connection.m` uncommitted | Distinguish client decoder backlog drops from network loss, raise the backlog drop threshold, and log output queue high-water marks. | A later run showed healthy network receive while the client reported small `ringDrops` bursts. Those drops were caused by the SDL path dropping when `LiGetPendingAudioDuration()` exceeded 30 ms, which is the moonlight-common decoder queue depth, not the SDL output queue. | Test next. If `backlogDrops` disappear but crackle remains, focus on Windows server diagnostics. If they persist, client output throttling is still suspect. |

## Evidence From Current Logs

Files found locally:

- `/tmp/moonlight_audio_diagnostics.log`
- `/tmp/moonlight_audio_network.log`
- `/tmp/moonlight_decoded_audio.pcm`
- `/tmp/moonlight_decoded_audio.txt`

Recent active stream window:

- Client diagnostics recovered to about `decoded=1000` per 5 seconds.
- Network diagnostics showed about `recv=1500` per 5 seconds and `handleNow=1000` per 5 seconds.
- `recovered=0` and `plc=0`, so there was no obvious client-side FEC recovery or packet-loss concealment in that captured window.

Later diagnostic run:

- Network receive stayed healthy near `recv=1500` and `handleNow=1000` per 5 seconds with zero timeouts.
- Client diagnostics still showed small drop bursts, for example `ringDrops=5` and `ringDrops=8`.
- Those drops were not network loss; they came from the SDL output path's 30 ms decoder-backlog drop threshold.

Earlier bad-window summary from existing notes:

- `decoded` dropped below the expected roughly 1000 packets per 5 seconds.
- `outputUnderruns` increased at the same time.
- `decodeErrors`, `ringDrops`, `invalidFrames`, and `clipped` stayed at zero.

Interpretation:

- If a fresh crackling run shows `recv` also drops, the likely source is upstream of the client receive loop: server send cadence, Windows capture/encode cadence, host scheduling, network path, or socket/QoS.
- If `recv` remains healthy while `decoded` drops, the likely source is client RTP queueing/decryption/decode handoff.
- If decoded PCM crackles while network/decode counts are healthy, the corruption is before or during decode/encode.
- If decoded PCM is clean but playback crackles, the problem is the macOS output path or output scheduling.

## Next Plan

1. Return to a clean diagnostic baseline.
   Keep counters and logs. Do not combine them with the SDL audio output rewrite for the next diagnosis run. The SDL rewrite changes the playback backend, buffering, and backpressure all at once.

2. Capture one reproducible crackling run with synchronized logs.
   Enable the client Debug setting named "Audio Diagnostics Logging". Before launching, remove old `/tmp/moonlight_audio_diagnostics.log` and `/tmp/moonlight_audio_network.log`. During the bad window, note wall-clock time and the game/action. Preserve the decoded PCM dump only if using the PCM-dump build.

3. Add Windows-host diagnostics in the active path.
   Set `SUNSHINE_AUDIO_DIAGNOSTICS=1` before launching Sunshine. This enables Windows WASAPI capture diagnostics from `server/src/platform/windows/audio.cpp` around `mic_wasapi_t::_fill_buffer()` and `mic_wasapi_t::sample()` for event timeouts, discontinuity flags, silent buffers, captured frames, overflow events, and sample calls per 5 seconds.

4. Add server send-cadence diagnostics.
   With `SUNSHINE_AUDIO_DIAGNOSTICS=1`, `server/src/audio.cpp::encodeThread()` and `server/src/stream.cpp::audioBroadcastThread()` report captured sample batches, encoded packets, encode failures, UDP sends, FEC sends, send exceptions, and max inter-packet gap.

5. Compare the same 5-second windows across host capture, host encode/send, client receive, client decode, and client playback.
   The first stage whose packet/cadence count drops during the crackle is the next target. Do not apply another mitigation until this comparison points to a specific stage.

6. Test mitigations one at a time.
   Candidate tests after the baseline: increase client AudioQueue circular buffer duration, enable client socket QoS, adjust Windows audio capture wait/silence behavior, or adjust server audio thread priority/send pacing. Record each test in the ledger with before/after counts.

## Success Criteria

- A bad run has aligned 5-second counters for the active Windows host path and the macOS client path.
- The investigation identifies the first stage where cadence/data drops during crackle.
- Any mitigation is tested independently against that stage and has before/after evidence.

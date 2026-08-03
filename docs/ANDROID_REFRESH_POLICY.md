# Android Data And Refresh Policy

This document defines the public data-source and refresh baseline for the Android VPN client.

| Feature | Source | Background / network cadence | Visible UI cadence |
|---|---|---:|---:|
| VPN state | Native core events | Event driven, no polling | Immediate |
| Tunnel RX/TX | Native core counters | Local only while visible | 1 second |
| Connection timer | Android monotonic clock | Stopped when hidden | 1 second or display frame |
| Node latency | Local probe / core API | Bounded and cached | Cached value |
| Public IP | Configured public-IP provider | Connect, reconnect, or node switch | Immediate from cache |
| Account state | Configured service API | Bounded refresh | Immediate from cache |
| Support messages | Realtime channel | Active only when required | Immediate |

## Rules

- Do not use a server request to animate local VPN state, throughput, or elapsed time.
- Backgrounding the application must stop nonessential UI timers and network sampling.
- A connection is ready only after the native core is running and a valid egress state is confirmed.
- New periodic work must document its owner, foreground/background behavior, timeout, cache, and retry backoff.

## Release Configuration

Release versioning, package checksums, supported-version policy, and distribution URLs are deployment configuration. Maintain them outside the public repository and inject them through the release pipeline.

# Smart Dolphin VPN Android Architecture

## Runtime Components

| Layer | Responsibility |
|---|---|
| Flutter and Dart | User interface, application state, local preferences, and platform-channel clients. |
| Kotlin and `VpnService` | Android lifecycle integration, foreground-service behavior, and system VPN permission handling. |
| Dolphin-Core | Native tunnel orchestration and runtime event delivery. |
| sing-box / libbox | Protocol configuration and transport implementation. |

## Configuration Boundary

The repository contains protocol schemas and placeholder values in `apps/mobile-flutter/lib/services/vpn/node_table.dart`. Production node addresses, credentials, keys, server names, certificate material, and distribution endpoints must be supplied by a deployment-specific configuration source.

## Main Code Paths

- `apps/mobile-flutter/lib/services/vpn/`: configuration generation and core integration
- `apps/mobile-flutter/lib/platform/android/`: Flutter platform channels
- `platforms/android/app/`: Kotlin host application and VPN service integration
- `apps/mobile-flutter/lib/features/session/`: session lifecycle and connection state
- `apps/mobile-flutter/lib/features/servers/`: server catalog and selection UI
- `qa/tests/`: application and service tests

## Operational Requirements

- Keep VPN credentials and private keys out of source control.
- Use Android Keystore-backed storage for sensitive local material.
- Treat server-provided authorization, subscription, and account state as authoritative.
- Validate native core startup and confirmed egress state before reporting a connection as ready.

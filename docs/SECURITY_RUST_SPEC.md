# Android Security Layer Specification

## Scope

This specification defines public security requirements for the Android client and its Rust integration layer. It intentionally excludes production endpoints, account records, credentials, signing material, and deployment topology.

## Identity And Credentials

- Validate account identifiers and passwords before sending requests; server-side validation remains authoritative.
- Store session material using Android Keystore-backed encryption. Never persist plaintext passwords in preferences, logs, crash reports, or test fixtures.
- Bind sessions to an application-scoped device identifier. Do not collect or hardcode IMEI or other unnecessary hardware identifiers.
- Treat authorization, account status, subscription state, and revocation results returned by the service as authoritative.

## Update Integrity

- Verify update metadata and package integrity before installation.
- Validate application signing certificates and required native-library integrity where supported by the platform.
- Keep release URLs, hashes, and signing configuration in the release pipeline rather than source control.

## Android Runtime Protection

- Use `VpnService` and a foreground service according to Android platform requirements.
- Prevent sensitive values from entering telemetry, diagnostics, and user-visible error messages.
- Keep native and Flutter security decisions consistent through a documented platform-channel contract.

## Rust Integration

The Rust package is a platform-adaptation baseline. JNI bindings and Android-specific implementations must be reviewed for memory safety, error handling, cryptographic API usage, and lifecycle ownership before release.

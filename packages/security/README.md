# Android Rust Security Layer

This directory contains the Rust security-layer code intended for Android platform adaptation. The current implementation is a specification-aligned baseline; platform-specific modules such as `device.rs` and `guard.rs` require Android API and JNI integration before inclusion in a release build.

See `docs/SECURITY_RUST_SPEC.md` for the public security specification.

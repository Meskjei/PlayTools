# Toucher smoke test

Run `Tests/ToucherSmoke/run.sh` on macOS with the Xcode command-line tools. The test compiles the real `Toucher.swift` against minimal UIKit stand-ins and checks missing-window, unmatched-release and normal begin/end behavior. It does not exercise real UIKit event delivery.

If local policy rejects ad-hoc binaries, provide a locally available signing identity via `PLAYTOOLS_TEST_SIGN_IDENTITY`.

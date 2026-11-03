# Qwen 6.12.0.2486 compatibility

This is a version-specific workaround for the enterprise build of Qwen with Mach-O UUID `282EE888-852E-3C5B-8F40-91820B039B6F`. Its security SDK writes into a shared Block descriptor in the main image's read-only `__DATA_CONST,__const` section. PlayTools copies that descriptor to writable process-owned storage and redirects only matching heap Blocks retained at the verified call site. It does not change page protections or modify the IPA.

The workaround is enabled only when the executable UUID and section address match. The retain hook additionally checks the exact call site, Block flags, and original descriptor pointer. The hook still adds a fast guard to `objc_retain` in other apps. Revalidate the binary, Block layout, lifetime, and call site before supporting any other version; matching a bundle ID or version string alone is insufficient. This is an experimental compatibility measure, not a general Block fix.

Run `Tests/QwenCompatibility/run.sh` for the matching and non-matching guard tests. On macOS installations that require signed local binaries, set `PLAYTOOLS_TEST_SIGN_IDENTITY` to a local development signing identity and `TMPDIR` to a writable directory where locally signed programs may run. These checks do not replace running the actual app and verifying its original data segment remains read-only.

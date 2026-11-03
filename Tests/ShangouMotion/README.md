# Shangou virtual motion compatibility

The tested enterprise IPA (UUID `5431157E-3050-3D18-ADF1-D0D62D65C0F9`, 12.10.61 / 59536680) crashes on macOS build `26B123` while destroying `UINSVirtualMotionDevice`: an over-resumed dispatch source or a stale object captured by its initialization blocks. The crash recorder can subsequently suspend a thread holding the Objective-C runtime lock and deadlock, presenting as a frozen logout page.

Only for this binary, host build and presence of the Mac virtual device, `CMMotionManager` allocation returns nil before creating any CoreMotion instance. Calls to the unavailable manager therefore return nil/NO under normal Objective-C semantics. No sensor readings are fabricated. CoreLocation, account storage and crash reporting remain untouched. Revalidate other versions rather than broadening the match by bundle ID.

Run `sh Tests/ShangouMotion/run.sh`. It checks mismatching image/host guards, the alloc/init, new and allocWithZone paths, with no allocated instance or initializer/destructor invocation. Actual app launch, logout and page interaction must also be verified; these checks do not emulate UIKitMacHelper. Discarded approaches: returning nil from the initializer still destroys an uninitialized CoreMotion object; only disabling updates still leaves virtual-device teardown alive. Neither is sufficient.

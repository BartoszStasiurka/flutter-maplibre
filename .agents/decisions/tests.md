# Tests

- **One Flutter app, `examples`, runs the integration tests.** Its platform
  folders are already set up for the C library (arm64 only, the macOS
  network entitlement, Swift Package Manager), so a second app would only
  duplicate them. The packages have no example apps. `all_test.dart` runs
  the suite in one launch, as each launch builds and starts the app.
- **Unit tests cover what needs no platform** (models, annotation layers,
  the UI widgets against a mocked `MapController`, the gesture recognizer).
  Integration tests cover what each platform implements: rendering,
  camera, projection, style, queries, gestures.
- **Integration tests wait for what they assert.** Map commands and runtime
  events are asynchronous and screen locations follow the frame on screen,
  so the `TestMap` helpers pump until an event, a camera, a shown frame or a
  feature query matches, with a timeout, instead of fixed delays. Styles are
  inline JSON or assets; only tests named "(network)" load remote styles.
- **CI runs the integration tests on every platform, rendering in software**
  (SwiftShader in the Android emulator, lavapipe on Linux and Windows, the
  macOS VMs' paravirtualized Metal), and uploads their coverage per
  platform. On Windows the map then falls back to CPU readback. The iOS
  run goes through `.github/scripts/watchdog.sh`, which stops it after 10
  minutes without output and reports the stall as annotations, because the
  job log needs a sign-in and annotations don't. flutter test sometimes
  never attaches to the app on the CI simulator (Flutter 3.47.7 and 3.47.8;
  the app logs its VM service and waits, no MapLibre thread exists), so the
  watchdog stops a run once the VM service has listened for two minutes
  without a test starting, and CI starts it again, up to three times. The
  Windows runner runs elevated, and an elevated Vulkan loader ignores
  `VK_DRIVER_FILES`, so CI registers lavapipe in the registry.
- **The recognizer is unit tested against a recording `GestureCameraSink`**
  (`maplibre_platform_interface/test`). `examples/integration_test/gestures_test.dart`
  checks each platform's camera end to end.
- **`linux/test/gl_texture_test.cc` checks the Linux zero-copy path without
  Flutter**, against stand-ins for the few Flutter functions the plugin
  calls: the GPU IDs from the EGL probe of a real window, a Vulkan device on
  its UUID that the plugin adopts as it adopts the library's, and exported
  images that `populate` imports and returns in an EGL
  context that shares nothing with GDK's, as Flutter's, also across a resize
  and the disposal of a texture. It checks which slots are in use. It passes on Mesa's lavapipe and
  llvmpipe, which share memory, so it runs without a GPU.
- **Projection integration tests run at zoom 4.** At the minimum zoom of a
  wide desktop window the world is narrower than the window, and screen
  corners wrap to the neighbouring world copy.

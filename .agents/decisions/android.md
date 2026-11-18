# Android

- **MapLibre presents to the Surface of a Flutter `SurfaceProducer` through
  `attachAndroidSurface`, with a graphics context that the C library
  creates: an EGL context on the default display (OpenGL ES build) or a
  Vulkan device and swapchain (Vulkan build), on the session's core
  worker.** This is zero-copy, works with Impeller and the ImageReader
  backend, and leaves the plugin without native code: Dart passes the
  Surface as a `jobject` with its thread's `JNIEnv*` (read through the
  JavaVM's `GetEnv`, as `package:jni` exposes neither publicly), and
  `initAndroid` gets the application context once. This replaced a JNI shim
  with its own EGL setup, Vulkan device and a render thread for
  caller-graphics-thread EGL sessions.
- **`onSurfaceCleanup` releases the session's target and pauses frame
  demands, and `onSurfaceAvailable` gives the session the current Surface
  again and resumes.** The session keeps its own reference to the window, so
  a frame in flight while Flutter destroys it finishes with
  `targetNotReady`. A resize that makes Flutter hand out a new Surface moves
  the session there with `setAndroidSurfaceTarget`; otherwise it is a
  session resize.
- **Sessions end with `RenderSessionHandle.release()`, not `abandon()`.**
  Release detaches a core-worker session off the UI thread and completes once
  no library thread touches the target, after which the plugin frees its
  texture or surface. Abandon blocked the UI thread on the map's tile work
  and GPU queue. Release reports nothing about kept objects; a Vulkan
  swapchain is kept only when the process exits or its queue fails to drain.
- **HTTP follows the app's network security config (0.202610.3), so
  cleartext needs the app's permission.** The example permits it for
  127.0.0.1 and localhost in its debug source set only, for the local test
  server of the integration tests.
- **The plugin ships no TLS verifier code.** The C library embeds the dex of
  its rustls-platform-verifier helper and loads it in `mln_android_init`, so
  the APK needs no Java classes or keep rules for it.

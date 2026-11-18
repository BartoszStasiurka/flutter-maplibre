# Architecture

- **Two platform packages: `maplibre_web` for the browser and `maplibre_native`
  for everything else.** One C API serves every native platform, so the
  per-platform packages (android, ios, webview) were removed.
- **The C API comes from the `maplibre_native_ffi` package on pub.dev
  (0.202611.0), whose build hook downloads the prebuilt C library of its
  release, checked against digests pinned in the package.** No submodule and
  no local C build are needed; `local_build` (see `build-ci.md`) points the
  hook at one when the C library changes.
- **Rendering goes only through the texture registry, never platform views.**
  This keeps Flutter composition, transforms, and overlays working.
- **Windows and Linux render through Vulkan. Android renders through OpenGL
  ES by default, and through Vulkan when the app selects the Vulkan build.
  iOS and macOS render through Metal.** WGL and GLX/EGL need one pinned
  thread, which Dart can't guarantee, and the binding's texture APIs are
  Vulkan-first. On Android, OpenGL ES runs on every device,
  while Vulkan 1.1 drivers are missing or unreliable on many older ones.
- **The C library carries one backend, and Dart follows it at runtime.** The
  binding's build hook picks it per target (OpenGL ES on Android, Metal on
  iOS and macOS, Vulkan on Windows and Linux) unless
  `hooks.user_defines.maplibre_native_ffi.backend.<os>` names one, and `mln_supported_render_backend_mask()` tells `MapRenderer`
  which path to take. The workspace sets no backend.
- **Dart reaches the platform plugins through ffigen (Windows, Linux, iOS,
  macOS) and jnigen (Android), never method channels.** Calls are synchronous
  and typed, with no message encoding. The Windows and Linux plugin libraries
  export one C API, whose shared functions `desktop/` implements once, and
  keep their registered instances behind a mutex. Each platform defines
  only its own functions of that header; the bindings look a symbol up on
  first call, so Dart calls only those of its platform. On Android a Kotlin
  `MaplibreNativeApi` object holds each engine's texture registry, and
  SurfaceProducer callbacks reach Dart through a `SurfaceListener` that Dart
  implements as async listeners.
- **Plugin state is per engine, and every plugin call passes
  `PlatformDispatcher.instance.engineId`.** An app can run more than one
  engine in a process, such as one of a background service, and every engine
  registers its own plugin instance with its own texture registry, whose
  texture ids may repeat across engines. A texture is created and found in the
  plugin of the caller's engine, and an engine that goes away releases only
  its own textures (#677). The id maps to the plugin through public embedder
  APIs: `FlutterEngine.getEngineId()` at attach on Android, the plugin that the
  engine published (`valuePublishedByPlugin:`) on iOS and macOS, the engine's
  plugin registrar on Windows, and its texture registrar on Linux.
- **`MapRenderer` drives every platform the same way, and a `FrameTarget`
  per platform owns the texture and plugin calls.** The renderer demands a
  frame, hands each rendered one to the target on one serial GPU queue, and
  demands the next; targets attach the session, resize, present, end the
  session, and dispose the texture. Windows, Linux, iOS, and macOS share
  `RingTarget` (a ring of three images). Windows copies each frame on the
  GPU before releasing it; Linux, iOS and macOS keep it acquired while
  Flutter samples its slot (`holdsFrames`), and release it once the plugin
  reports the slot free. A resize releases the held frames first, as the
  session refuses to resize while it has a frame acquired.
- **The C library allocates the ring where it can (`LibraryRingTarget`:
  DXGI shared textures on Windows, IOSurfaces on iOS and macOS), and on
  Android presents to the Surface with a graphics context of its own.**
  Plugins then only hand frames to Flutter, with no Vulkan, Metal, EGL or JNI
  code. A resize is a session resize, after which the library hands out new
  images for the same slots, so Dart counts rings and the plugins open or
  wrap each image once per ring. Linux keeps a plugin-owned ring that the
  session borrows (`BorrowedRingTarget`): the library's dma-buf ring needs a
  DRM device that CI, WSL2 and software rendering lack, while opaque Vulkan
  memory works there.
- **Windows and Linux render on a Vulkan device that the C library creates
  (`VulkanDeviceHandle.create`) on Flutter's GPU**, which the plugin names
  through `maplibre_native_gpu_id`: the adapter LUID on Windows, the OpenGL
  device UUID on Linux. The device lives as long as the process and enables
  the external memory extensions the GPU has. On Linux the plugin allocates
  its ring images on it through the functions of its context.
- **One process-wide VkDevice and VkQueue are shared by every map on
  Windows and Linux, without a queue lock.** The C library serializes every
  session's submits and presents per queue (`vulkan_queue_access.cpp`). A
  lock is only needed if host code uses the queue, and none does.
- **Widgets over the map follow the frame on screen, not the latest camera.**
  Each rendered frame result carries the view it drew; when Flutter can show
  that frame, the renderer creates its projection (`mapProjectionCreate`) and
  hands both to the map state. `camera` and screen locations come from it,
  so widget layers rebuild in the same
  Flutter frame as the map image. Camera events and `getCamera()` still
  report the latest camera, so `await moveCamera(...)` is followed by the new
  one. Exact on Windows. On Android Flutter takes the newest Surface
  image itself, so it can be off by a frame. The map takes its bounds,
  initial camera and style before the session attaches (`MapRenderer.create`
  `setUp`, which map creation runs once the map is ready), so the first frame
  already shows them. Events that arrive meanwhile wait for
  `MapRenderer.start()`, after `onMapCreated`. The native camera center is unwrapped to the visible
  world copy; projections keep it, while `CameraPosition` wraps the longitude
  into [-180, 180).
- **Dart calls the plugins on its UI thread.** Flutter's Windows and Linux
  texture registrar functions may be called from any thread. On Android the UI
  thread is the main thread, which SurfaceProducer needs, and its `JNIEnv*`
  is the one the C library gets with each Surface.
- **Every session uses the core-worker driver, with frame wakes drained on
  the Dart isolate.** Frame
  demands use `waitForUpdate`, so a demand renders only a newer map update and
  idle maps don't render, and every rendered frame is presented. The frame
  wake is a `Wake` with a Dart callback. A map's event mask holds the events the state always handles plus
  the ones whose `MapLibreMap` callback is set, and follows the widget
  (`setEventMask`), so per-frame render events are only queued while
  `onRenderFrame` listens. Runtime events arrive through
  `RuntimeHandle.setEventHandler`, which the binding calls on the isolate.
  Events that arrive before the first frame demand are kept until then.

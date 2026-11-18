# iOS and macOS

- **One Objective-C plugin in `darwin/` serves both, with
  `sharedDarwinSource`, as a SwiftPM package only.** The Metal and CoreVideo
  code is the same on both; only the Flutter import differs. CocoaPods is
  deprecated (its trunk turns read-only on 2026-12-02) and Flutter uses
  Swift Package Manager by default since 3.44, so there is no podspec, and
  the example's iOS and macOS projects have no Podfile. The Flutter minimum
  of 3.47 means apps need no `flutter config` step.
- **Sessions render into the library's ring of three BGRA8 IOSurfaces
  (`attachIoSurfaceRing`), which the plugin wraps in pixel buffers
  (`CVPixelBufferCreateWithIOSurface`, once per ring), and the
  `FlutterTexture` returns the presented slot's buffer from
  `copyPixelBuffer`, without a copy or a wait.** BGRA8 is what Flutter's
  pixel buffer textures read. The frame's GPU writes completed before it
  became acquirable, so Flutter can sample it at once. Dart keeps the frame on
  screen acquired, so MapLibre renders into the other slots, and releases a
  frame it replaced once `maplibre_native_gpu_texture_slot_in_use` reports
  its slot free: not the presented slot, and neither of the last two slots
  Flutter took (it holds the last buffer until it takes the next, and a frame
  still on the GPU may read the one before). So MapLibre renders into one
  free slot while Flutter keeps up. `IOSurfaceIsInUse` can't tell: the ring's
  own buffer and texture keep every surface in use (use count 2), Flutter's
  texture raises nothing, and Flutter has dropped the buffer by the time it
  takes the next. It checks on each present and every
  4 ms while a replaced frame is held. A resize releases every held frame
  before the session resizes; Flutter keeps the old buffer it shows, which
  retains its surface.
  This replaced a blit into a `CVPixelBufferPool` buffer that the Dart UI
  thread waited for on every frame.
- **Dart finds the C API through `+[MaplibreNativePlugin symbols]`, called
  with `objc_msgSend`, not `DynamicLibrary.process()`.** SwiftPM links the
  plugin statically into the app, and release builds strip global symbols
  (Flutter's FFI docs ask apps to change `STRIP_STYLE` for this). The
  Objective-C runtime finds the class by name regardless, and the table keeps
  the functions from dead stripping. All of it lives in one `.m` file, which
  the generated plugin registrant pulls into the link.
- **Texture registration and unregistration run on the main thread, inline
  when Dart's UI thread is the main thread.** `textureFrameAvailable` runs on
  the calling thread.
- **`Package.swift` requires iOS 15.0 and macOS 14.3**, the deployment
  targets of the C library's Apple presets, so an app can't target systems
  where the library fails to load. The example's macOS target is 14.3. iOS
  matches Flutter 3.47's minimum; macOS is above its 12.0.
- **The example excludes x86_64 (macOS and the iOS simulator) and has the
  `network.client` entitlement on macOS.** The C library is published for
  arm64 only, and the sandbox blocks tile downloads without it.

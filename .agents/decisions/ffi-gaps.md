# Gaps of maplibre_native_ffi

- **Native `queryRenderedFeatures` returns features in the order their
  layers were added, not their draw order after a `moveStyleLayer`** (seen on
  Windows with 0.202611.0, not checked elsewhere). The pixels follow
  the move. Hit testing of annotation layers therefore ranks hits by the
  index in `style.layers`, and the integration test checks the order by
  color.
- `maplibre_native_ffi` has no local font option, although MapLibre Native's
  renderer takes a local font family. On iOS and macOS the local glyph
  rasterizer also reads the `MLNIdeographicFontFamilyName` user default,
  which `localIdeographFontFamily` sets before each session attaches. The
  renderer reads it at the session's first frame, and it is the process's,
  so a map that attaches with different fonts before another map's first
  frame gives that map its fonts. It is registered in the registration
  domain, so a value the app stores under that key, or passes as a launch
  argument, overrides the option. Android, Windows and Linux draw the
  style's glyphs.
- MapLibre Native moves to the style's camera on load only while no camera
  change happened, and `mln_map_set_bounds` counts as one (it always passes
  bounds, even `unbounded`). The C API has no getter for the style's camera.
  So a map without `MapOptions.initCamera` sets its camera constraints after
  the first style loaded, and frames before that are unconstrained.
- `maplibre_native_ffi` has no call to change the tiles or the TileJSON URL of
  raster, raster DEM and vector sources. `StyleControllerNative` removes the
  layers that use the source, swaps the source and adds the layers back at
  their positions, in one command group. `getStyleSource` is lossy (no
  inline tiles or GeoJSON data), so sources are read from
  `getLoadedStyleJson` instead.
- `getLoadedStyleJson` returns the style document as it was parsed, so it only
  fills the cache on load.
- Feature queries on native don't return layers in their order, and layers with
  the same layout share one symbol placement. So the tests check the order of
  layers through symbol placement, with icons of slightly different sizes.
- `MapHandle.setStyleUrl` and `setStyleJson` complete once the style
  document parsed, and fail when it doesn't load. The map state only submits
  the style and doesn't wait: later commands run after it anyway, a failure
  reaches `onError` through the loading failed event, and a newer style
  cancels an older one.
- `setGeoJsonSourceData` prepares the data in the background, but the binding
  still `jsonEncode`s it, so `GeoJsonData.text` is decoded in Dart and
  encoded again. Newer data cancels data that isn't ready yet, which
  `setGeoJsonData` treats as done.
- The C API has no setter for the offline tile count limit and no automatic
  database packing, so `setOfflineTileCountLimit` and
  `runPackDatabaseAutomatically` were removed from the `OfflineManager`.
- Missing on native: the globe and vertical perspective projections and
  video sources. MapLibre Native implements none of them, and the C API has
  no setting for them (`mln_map_set_projection_mode` only sets axonometric
  and skew; `MLN_STYLE_SOURCE_TYPE_VIDEO` only names the type).
  `setProjection` with anything but Mercator logs once and keeps Mercator,
  so pages that ask for a globe still show a map; adding a `VideoSource` throws an `UnsupportedError`, as a layer on it
  could not render.
- iOS and macOS pass the integration tests on an arm64 Mac (Xcode 27.1,
  macOS 27.0.1, iPhone 17 simulator on iOS 27.0) against the 0.202610.2
  release library, but have not run on an iOS device. 0.202610.3 adds a
  macOS x64 library, so Intel Macs build; none has run the tests.
- Linux passes the integration tests in WSL2 (WSLg, Mesa llvmpipe and
  lavapipe, Flutter 3.47.9) and under Xvfb, on zero-copy and on CPU readback.
  Not checked on a desktop with a GPU, where Flutter's OpenGL ES context may
  lack `GL_EXT_memory_object_fd`; Wayland compositors share frames as
  dma-buf EGLImages instead, which would be the alternative. Painting a map before its first frame crashed the
  raster thread until the texture callbacks set a `GError` with
  their `FALSE`, which Flutter's engine dereferences.
- x86_64 iOS simulators have no published C library (0.202610.3 publishes a
  macOS x64 one).
- The C library targets macOS 14.3, above Flutter 3.47's minimum of 12.0,
  so apps must raise their macOS target. MapLibre Native itself requires
  14.3 (its `CMakeLists.txt` fails below it), so `maplibre_native_ffi`
  can't lower it.
- The macOS presets also offer Vulkan and OpenGL. Selecting either with
  `backend.macos` makes a macOS map throw `UnsupportedError`, since the
  plugin only integrates Metal.
- The zero-copy Metal path passed on macOS and the iOS simulator with the
  plugin's own ring, with MapLibre rendering into the one free slot; the
  library's IOSurface ring has only run in CI. Not checked: iOS devices, and
  whether a GPU read of Flutter outlasts the two slots the ring holds for it
  (tearing; none seen).
- The DXGI shared texture ring has not run with a GPU: CI's lavapipe has no
  adapter LUID, so Windows CI reads frames back.
- Touch tilt and double-tap-drag are not tested on Windows touchscreens.
- Web lost gl-js's keyboard navigation and shift-drag box zoom, which the
  shared recognizer doesn't offer, and its grab cursor.

# Map API: options, events, plugins, camera and queries

- **Network settings are static, on `MapLibreNetwork`, not in
  `MapOptions`.** On native the header rules and the URL transform belong to
  a runtime, and the `OfflineManager` has a runtime of its own, so a per-map
  option couldn't reach its downloads. `createRuntime()` applies them to
  every runtime and again on each change. On web, `transformRequest` reads
  them per request. Headers are native header rules (glob URL, first match
  wins) because the C API runs header callbacks synchronously on a library
  thread, which Dart can't answer; web matches the same globs in Dart. The
  URL transform is a Dart callback, set on native only while there is one,
  as each request then waits for Dart. `offline` is the C library's network
  status, which is process-wide and outlives the isolate: the first runtime
  of an isolate reads it and turns `offline` true if the process is offline,
  so neither a second engine's default nor a hot restart leaves the setting
  and the process apart; later only changes are set. A change of one setting
  doesn't send the others to the runtimes again. Not on web, as gl-js has no
  equivalent. Resource providers are not exposed yet.
- **Events follow the "Events" rules of the [API guidelines](../../website/docs/contributing/api-guidelines.md).** The
  former `onEvent` took a sealed event, so every new event broke the
  exhaustive switches of apps. An unsubscribed callback costs nothing:
  native maps leave it out of the event mask, web maps don't listen to
  `render`, and the gesture detector registers no recognizer for it. The
  events follow the ffi and
  gl-js events; per-axis camera events (gl-js `zoomstart`, `rotate` …), raw
  pointer events, box zoom, `styledata` and `dataabort` are left out on
  purpose, and offline events stay on `OfflineManager`.
- **Plugins are widgets in `MapLibreMap.children`; `MapPlugin` gives them
  the declarative parameters of `MapLibreMap`.** Layers, `on…` callbacks,
  `movements` and `gestures` of every `MapPlugin` are combined into one
  `MapLibreMap` (`MapLibreMapState.effectiveWidget`), which platforms read instead of
  `widget` and follow in `didUpdateCallbacks`. Plugin layers go after
  `MapLibreMap.layers` in tree order; input events go to the plugins in
  hit-test order at the pointer (a drag to the plugins at its start), then
  to the app; other events go to every plugin in tree order, then the app.
  No plugin can keep an event from others (no stop-propagation, as in
  gl-js); `preventDefault` stays on double click and drag start. Movements
  and gestures are ANDed. Plugins register after a frame (post-frame), so
  their changes show one frame late. A controller-based `on<T>()` and plugin
  objects were rejected as imperative; slots by kind (`controls:`,
  `plugins:`) because one plugin can have layers, events and UI.
- **`MapLibreInheritedModel` has aspects.** `MapController.of` and
  `MapOptions.of` rebuild on a new controller, options or style, or when
  rendering pauses or resumes; `CameraPosition.of` on every camera change;
  `StyleController.of` on a new style and on every notification of the
  style. Widgets that show something that moves with the camera must read
  `CameraPosition.of`.
- **The style notifies structure, not values.** `StyleLayers` notify on
  add, remove and move, `StyleSources` on add, remove and changed TileJSON,
  the `StyleController` on those and on attribution changes (platforms call
  `notifyAttributionsChanged`). Layer properties and source data don't
  notify, as apps change them every frame and every `StyleController.of`
  widget would rebuild with them. The map counts the notifications into the
  model, after the frame when they come while the tree builds (annotation
  layers change there). Only the model rebuilds for them (a
  `ValueListenableBuilder` around it), not the platform widget.
- **`MapOptions.style` is a sealed `MapStyle`** (see the API guidelines).
  Backends switch on the type instead of guessing from the string.
- **One sealed `CameraUpdate` (position, bounds, points, geometry) for
  `MapOptions.initCamera`, `moveCamera`, `animateCamera` and `cameraFor`;
  one sealed `CameraAnimation` (ease, fly) for how.** Both platforms have
  jump, ease and fly modes, so there are no platform-prefixed parameters.
  `initCamera` is null by default: null keeps the style's camera; a set camera
  replaces it as a whole, as both MapLibre Native and gl-js ignore the style
  camera once the camera changed. Fit targets are fitted before the first
  frame (native: `cameraFor*` in `setUp`; web: `cameraForBounds` + `jumpTo`
  right after the map is created, and again in the first post-frame callback,
  when the element has the size of its platform view). Native fits points
  with `cameraForLatLngs` and geometries with `cameraForGeometry`; web fits
  their bounding box. The ffi `CameraFitOptions` has no max zoom, so native
  clamps the fitted zoom.
- **`animateCamera` returns `completed` or `cancelled`.** Native reads the
  outcome from the ffi `endHandler`, but marks a gesture, `moveCamera` or
  `stopCamera` as cancelled itself, since the ffi counts a later camera write
  as completed. Web tags each animation's moves with event data and completes
  it on its `moveend`; a gesture, `moveCamera` or `stopCamera` cancels it
  first. Projection names stay `toScreenLocation`/`toLngLat` (as in
  maplibre-compose and the Android SDK); `project` would clash with
  `MapProjection`.
- **Bounds are geobase's `GeoBox`, and only the geobase types of the API are
  re-exported** (`show` lists in `maplibre` and
  `maplibre_platform_interface`). Backends import other geobase types from
  geobase directly.
- **Feature queries are async on every platform, and there is no
  `queryLayers`.** The C API only queries asynchronously, and its features
  carry their source and source layer but not their style layer, so
  `RenderedFeature` has `sourceId` and `sourceLayer`, and layer membership is
  queried with `layerIds`. Since 0.202610.3 query results also name their
  style layer, `RenderedFeature.layerId`; on web it comes from the gl-js
  feature's `layer.id`. The webview's `*Async` overloads went with the
  webview package.
- **One `queryRenderedFeatures(QueryGeometry, {layerIds, filter})`, like
  gl-js and the C API.** `QueryGeometry` is sealed: `.point`, `.rect` and
  `.viewport`. The C API also queries along a screen line string, but gl-js
  only takes a point or a box, so there is no `.line`. The C API has no
  viewport geometry, so native queries a box of the map's extent; gl-js
  queries without a geometry. `filter` is a typed `Expression<bool>`, the
  type of layer filters. `RenderedFeature.geometry` is a geobase `Geometry`,
  parsed from the GeoJSON that both platforms report, like sources and
  offline regions. `querySourceFeatures(sourceId, {sourceLayer, filter})`
  takes one source layer like gl-js; native passes it as the C API's list.
  Web returns no features for a missing source instead of letting gl-js
  throw, as native does.
- **`MapOptions.localIdeographFontFamily` is a per-map CSS font-family list,
  as gl-js's option, and defaults to `'sans-serif'`, as gl-js and MapLibre's
  iOS and Android SDKs draw CJK locally by default.** Null (`false` to
  gl-js) or an empty string draws the style's glyphs on every platform. On
  iOS and macOS the C library's local glyph rasterizer reads its fonts from
  the `MLNIdeographicFontFamilyName` user default when the session's
  renderer is created, on its first frame (the C API passes none, see
  `ffi-gaps.md`), so the Darwin target registers a value just before every session
  attaches, in the registration domain, which is the process's and never
  written to disk: the names, or `@NO` for null, since the rasterizer reads
  the key with `stringArrayForKey:` and is on for any array, even an empty
  one. A map without the fonts thus never inherits another map's. A generic
  sans-serif family stands for the system font's family, as MapLibre's iOS
  and macOS SDKs pass it by default, and the plugin reads it through Core
  Text, which any thread may call; other generic families reach Core Text
  as literal names. The rasterizer puts the layer's `text-font` names before
  these. The other native platforms have no local rasterizer.
- **An app drives the camera through the named constructor
  `MapLibreMap.withCamera(camera: …)`, not an optional `camera` parameter of
  the default constructor.** The user found a parameter too prominent for an
  edge case (flutter_map as root, syncing maps, custom gesture layers). Each
  new camera is applied in `didUpdateWidget`, so it reaches the map while the
  widget builds: native submits it without waiting
  (`discarding.updateCamera`), and `CameraPosition.of` still follows the frame
  on screen. On web it jumps in build. Multi-threaded skwasm shows a Flutter
  frame one browser frame after it was built, and GL JS draws a change made
  within a frame in the next one, so both match. CanvasKit and
  single-threaded skwasm show the build in the current browser frame, so GL
  JS redraws in a post-frame callback, which runs in the same rAF. Not in
  build, because `redraw()` fires `render`, `load` and `idle` synchronously,
  and their callbacks may rebuild other widgets. Camera callbacks fired by
  the jump are deferred to a microtask for the same reason. The gestures
  don't move the camera while it is set (movements are none); the
  controller still can, until the next change. Presenting frames in build
  through one texture per ring slot would close the remaining one-frame race
  on native, but changes how every map presents, so it is not done.
- **Global state values are declarative, `MapOptions.globalState`; the
  style's `state` defaults and the merged result are read on
  `StyleController.globalState`.** The values are app state, toggled with
  `setState`, and should outlive a style switch, as gl-js's `globalState`
  map option does. So there is no imperative setter (a widget parameter has
  no controller method for the same thing). `StyleGlobalState` sends only the
  keys that changed; a removed or null key goes back to the style default,
  which Dart sends itself as it knows the defaults from the style JSON
  (gl-js resets on null, the C API is not documented to). Each newly loaded
  style gets every value right in its load callback, before the style JSON
  is read, so its first frames already use them; web doesn't pass gl-js's
  `globalState` option, so that both platforms apply the values the same way.
  A map can keep global state across a style switch (gl-js's diffed
  `setStyle` does), so the new style also resets the keys that the previous
  one set and the options no longer have, once its defaults are read.

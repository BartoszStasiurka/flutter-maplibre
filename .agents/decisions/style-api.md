# Style API: sources, style layers, expressions and images

- **GeoJSON data is a sealed `GeoJsonData`: geobase objects
  (`.featureCollection`, `.feature`, `.geometry`), decoded JSON (`.json`) or
  text (`.text`).** The raw forms skip building geobase objects for large
  data. Native passes decoded JSON to the C API (text is decoded in Dart
  first); web hands text to `JSON.parse` and only `jsify`s decoded JSON.
  gl-js `updateData` diffs and `getData` are not exposed, as the C API has
  neither. Nor are the GeoJSON source's `filter`, `generateId` and
  `promoteId`: MapLibre Native ignores them (checked on Linux, both in the
  source JSON and on data updates).
- **Clustering is an optional `GeoJsonCluster` on `GeoJsonSource`, not a
  separate source type.** Sources are immutable data, so the cluster queries
  live on `MapController` next to the other queries: native calls the typed
  cluster queries of the render session; web calls the methods of the gl-js
  `GeoJSONSource`.
- **`setProjection` takes an `Expression<MapProjection>`**, the projection
  definition of the style spec, so web can interpolate projections by zoom.
  `MapProjection` is a `StyleEnum`. gl-js reports `globe-mercator` for a
  globe that shows Mercator at the current zoom; the event maps it to
  `mercator`. The C API's `ProjectionMode` (axonometric, skew) is a render
  transform, not a projection, and is not exposed.
- **Image options are a shared `StyleImageOptions` next to `pixelRatio`**,
  which stays its own parameter because `addImageFromCanvas`,
  `addImageFromIconData` and `addImageFromWidget` derive it. Their option
  positions are logical pixels and are scaled to image pixels, like their
  sizes; the other methods take image pixels.
- **Expressions are a sealed `Expression<T>` of `Literal`, `Call` and
  `RawValue`, with static members and extensions, and layer properties take
  them directly.** The design is in issue #72: `T` is what it evaluates to,
  numbers are `num` because generics are covariant, overloads are extensions
  on the receiver type, and keyword clashes are renamed. `==` compares
  `toJson()` deeply. `RawValue` is an addition for what a style holds but
  `Call` (a list) can't: legacy function objects and colors the reader doesn't
  know, such as extended CSS names. They read back unchanged.
- **`StyleLayer` subclasses are generated from the style spec by
  `tool/codegen/style_layers.dart`, and the generated Dart is committed.**
  The API of the generated layers is in the [API guidelines](../../website/docs/contributing/api-guidelines.md); transitions
  have typed properties too (`colorTransition`). Property names and JSON
  stay inside the package, except for `Expression.raw` and
  `StyleLayer.fromJson`/`toJson`, which also keep what a newer style spec
  adds. Setters can be synchronous because the state is in Dart.
  Layers keep only style JSON privately, and
  getters decode it on read, so what a style holds round trips unchanged and
  anything but a literal stays an `Expression.raw`. A literal list goes to the
  map in the plain form of the spec, without `literal`, which every property
  accepts. Colors are written as `#rrggbb`, or `rgba()` when translucent, as
  MapLibre Native's parser doesn't read hex with alpha.
- **A layer object on a map sends each change of its setters** (it is its
  own controller, see the API guidelines), fire-and-forget and in order (native: `MapHandle.discarding.setStyleLayerProperty`, which
  also takes `filter`, `minzoom`, `maxzoom` and `visibility`; web:
  `setPaintProperty`, `setLayoutProperty`, `setFilter`, `setLayerZoomRange`).
  Removing the layer or replacing the style detaches the object.
- **`StyleController.layers` and `sources` are own classes, not a `Map` or
  `List`, served synchronously from a cache behind a `StyleBackend` that each
  platform implements.** The cache and the argument checks are in
  `maplibre_platform_interface`, so both platforms behave the same and unit
  tests run against a recording backend. On style load native runs one
  `getLoadedStyleJson` query and web reads `getStyle()`; after that every
  change goes through this API. Changes apply to the cache at once and are
  undone if the map rejects them. What a TileJSON adds to a source comes in on
  source changes (`applyTileJson`) and is kept apart from the source as
  specified, so that an update doesn't carry it over.
- **`StyleController.batch` wraps its synchronous callback in a command group
  on native, ended in `finally`, and only runs it on web.**
  `AnnotationManager` uses it, so one rebuild shows in one frame.
- **Style images have a size in logical pixels that the package keeps the
  same on every platform and screen.** `addImage` takes a `pixelRatio` of
  image pixels per logical pixel, 1 by default as in MapLibre GL JS, and
  passes it to `map.addImage` on web and to `StyleImageOptions` on native.
  The canvas, icon and widget helpers take logical sizes, render at the
  device pixel ratio and pass it on, so callers never scale by it.
- **Images don't go through Flutter's image codecs on web.** The skwasm
  renderer (`--wasm`) gives a decoded image the size of the view, and
  encodes a layer's image (`addImageFromWidget`) to a PNG of that size.
  Web `addImage` decodes bytes with the browser's `createImageBitmap`, and
  the helpers hand their `ui.Image` to `addImageFromUiImage`, which passes
  its raw pixels (straight RGBA on web, premultiplied on native).
- **Animations change paint, not data.** The animation page adds its path
  once and moves a `step` on `line-progress` in `LineStyleLayer.gradient`. A GeoJSON
  update per frame re-encodes the data in Dart, parses and indexes it on the
  UI thread (`geojsonSourceDataCreate` is synchronous) and re-tiles the
  source; a paint change does none of that.
- **`StyleController.setPlacementTransitions` mirrors the C API's
  `StyleTransitionOptions.enablePlacementTransitions`.** Native keeps the
  style's transition duration and delay. gl-js only takes `fadeDuration` as
  a constructor option and keeps it in the private `_fadeDuration`, which it
  reads on every frame, so web sets that field: 0 off, the map's own value
  on. Honouring it only when the map is created would make the switch do
  nothing on web afterwards; the integration test fails if gl-js renames the
  field. A newly loaded style has them on again on both platforms. Native
  fades over the style's transition duration, web over the map's 300 ms,
  which gl-js also times pattern and dash crossfades with, so off ends those
  too on web.

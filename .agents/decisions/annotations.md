# Annotation layers

- **One internal `AnnotationManager` per map, not per style, keeps the
  layers of `MapLibreMap.layers` (#674).** It holds their definitions and
  features in Dart whether or not a style is loaded, adds their sources,
  style layers and images to every style that loads (`attach` after
  `onStyleLoaded`, so anchors can name layers the app added there), and
  forgets them with the old style (`detach`). Before, the platforms dropped
  the manager on every style load, and an app re-added its marker images in
  `onStyleLoaded`.
- **A rebuild matches layers like `Element.updateChildren`: by `Layer.id`,
  or else the next unmatched layer of the same `runtimeType` in list
  order.** Matched layers keep their style layer and source and get only
  what changed (`StyleLayer.updateFrom`, compared by JSON, and the source
  only when a copy of the features differs); a layer is re-created only when
  its type or source changes. The style layer and the source share the id.
  Without `Layer.id` it is generated once, on first mount, as
  `maplibre-<style layer type>-<n>` per map, never from the list index, so
  that inserting a layer doesn't rename the others. The type comes from the
  style layer, not `runtimeType`, which dart2js minifies in release builds.
  `Layer.id` must not start with `maplibre-`, and a generated id that a
  newly loaded style already uses gets the next number instead of leaving
  the layer off that style. `update` is the only way in: an imperative
  API (id-keyed add, move, remove) waits for a public design.
- **The manager is split by job (#680 review):** `annotation_manager.dart`
  matches the list and coordinates; `annotation_placement.dart` is the pure
  `placeLayers` (style ids and anchors in, add and move steps out, table
  tested in `annotation_placement_test.dart`); the parts
  `annotation_images.dart` (ref-counted images, `_ImageState` loading,
  ready, failed) and `annotation_drag.dart` (the overlay, `_DropState`
  dragging, dropped, saved) hold the other two.
- **The list is the draw order, and `Layer.anchor` (top, bottom, below or
  above a style layer, after maplibre-compose's `Anchor`) groups layers.**
  Each group keeps list order; `placeLayers` walks a group from the top down and
  moves (`StyleLayers.move`) or adds a layer only when it is out of order or
  out of its anchor's region, so a rebuild usually makes no calls. Top and
  bottom mean above or below every layer that is not in the group. An anchor
  that names a layer the style lacks, or a layer of the list, falls back to
  the top with a debug warning, and is retried on every rebuild. The
  manager also places the layers again in a microtask after the app adds,
  moves or removes a style layer (`StyleOwner.layoutChanged`), so a
  divider layer added after an await in `onStyleLoaded` needs no rebuild.
  A `.below(x)` or `.above(x)` group must sit right next to `x`. Taps,
  hovers and drags pick the layer drawn on top by its index in
  `style.layers`, not in the list.
- **The style layers of the annotations are protected in
  `StyleController.layers`.** `remove` and `move` of them throw a
  `StateError`, and their setters warn once in debug builds, unless the
  manager makes the change itself (`StyleOwner.isWriting`); the next
  rebuild would undo it otherwise. Writes to their GeoJSON sources warn
  once in debug builds. Both collections ask one internal interface,
  `StyleOwner` (`lib/src/style/style_owner.dart`: `ownsLayer`,
  `ownsSource`, `isWriting`, `layoutChanged`), which the manager implements
  and sets with `setStyleOwner`; they keep no ids or counters of their own
  and don't name `MapLibreMap.layers` except through `StyleOwner.name`.
  The setter of each collection is a top-level function that `style.dart`
  hides from the public API.
- **`MarkerLayer.icon` is the only image parameter of a marker layer: a
  sealed `MarkerIcon` (icon data, asset, bytes, `ImageProvider`, the id of
  an image the style has, or an expression that picks one per feature).**
  The manager adds each image it draws once per style, keyed by the icon's
  `==`, as `maplibre-icon-<n>`, counts the layers that show it, removes it
  after the last, and re-adds it after a style load. When `icon` changes,
  the style layer keeps the old image until the new one is on the style, so
  the markers don't disappear while it loads. It writes the
  symbol layer's `icon-image` for every kind of icon (user decision on #680:
  one sealed parameter instead of `icon` plus `iconImage`).
- **Annotation layers take `Expression<T>` for their style fields, with const
  `.literal` defaults, and pass them on to their style layer.** That allows
  per feature styling and keeps the layers `const`. `==` works as expressions
  compare deeply. Colors keep their alpha in the CSS color, so `opacity` is a
  field of its own that multiplies it.

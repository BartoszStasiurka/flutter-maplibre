---
title: 'Feature State'
description: 'Highlight hovered or selected features with feature state, without changing the data of a source.'
icon: lucide/highlighter
weight: 120
---

# Feature State

Feature state is data per feature that the app sets at run time, such as
`hover` or `selected`. Paint properties read it with the `feature-state`
expression, so the map shows a change on the next frame without touching
the data of the source. Use it instead of updating a GeoJSON source on every
hover.

```dart linenums="1"
Future<void> _onStyleLoaded(StyleController style) async {
  await style.sources.add(
    const GeoJsonSource.url(id: 'states', url: 'https://example.com/states.geojson'),
  );
  await style.layers.add(
    FillStyleLayer(
      id: 'states',
      sourceId: 'states',
      color: .select([
        (
          Expression.equal(.featureState('hover'), const .literal(true)),
          const .literal(Color(0xFF1565C0)),
        ),
      ], fallback: const .literal(Color(0xFF90CAF9))),
      onEnter: (event) =>
          style.sources.setFeatureState(.of(event.feature), {'hover': true}),
      onLeave: (event) =>
          style.sources.removeFeatureState(.of(event.feature), key: 'hover'),
    ),
  );
}
```

A `FeatureRef` names the feature: its source, its id and, for a vector
source, its source layer. `FeatureRef.of` takes them from a
`RenderedFeature` of a query or a [layer event](click-and-hover.md).

- `setFeatureState` merges its keys into the state of the feature, and
  `featureState` reads the state back.
- `removeFeatureState` removes one key or the whole state of a feature, and
  `clearFeatureState` the state of every feature of a source (or of one
  source layer of a vector source).
- The calls reach the map without waiting, in order with other changes.
- The state stays while the source is on the map, also when its data
  changes. It goes with the source or the style, and with `updateTiles` and
  `updateTileJsonUrl`.
- A call for a source that the style doesn't have does nothing, so a hover
  callback doesn't fail when its source was just removed. Debug builds warn.

<a href="../../../demo/#/style-layers/hover">Try it in the demo.</a>

## Details

- Only GeoJSON and vector sources have feature state.
- The features need ids: the `id` of a GeoJSON feature, or the id of a
  feature in a vector tile. On web, GeoJSON ids must be non-negative
  integers.
- Layer filters can't read feature state; paint properties can.

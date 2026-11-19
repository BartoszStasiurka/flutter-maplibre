---
title: 'API guidelines'
description: 'The rules behind the public API of maplibre, for contributors and plugin authors.'
icon: lucide/ruler
---

# API guidelines

These rules shape the public API of `maplibre` and
`maplibre_platform_interface`. They explain why the API looks the way it does,
so that new features fit in, and they help plugin authors write packages that
feel like part of `maplibre`. The reasons behind single features are
recorded in
[`.agents/decisions/`](https://github.com/maplibre/flutter-maplibre/tree/main/.agents/decisions),
one file per area.

If a change needs to break one of these rules, discuss it in an issue first.

## Declarative widgets, imperative style

`maplibre` has two kinds of API, and each feature belongs to exactly one of
them.

**Widgets are declarative.** `MapLibreMap`, its `MapOptions`, the
[annotation layers](../annotations/index.md) in `layers`, the
[plugins](../plugins.md) in `children` and the `on…` callbacks describe what
the map should look like now. Apps change them by rebuilding, and the map
applies only what changed.

- A widget parameter has no controller method that changes the same thing.
  A new style is a new `MapOptions.style`, so there is no `setStyle`.
- Options that apps set once and rarely change, such as `initCamera`, say so
  in their name or docs.

**The style is imperative.** [Sources](../sources/index.md) and
[style layers](../style-layers/index.md) are added, changed, moved and removed
through the `StyleController`, `style.sources` and `style.layers`, usually in
`onStyleLoaded`. They are objects with an identity on the map, and apps
change them often, so they don't go through a rebuild.

- Never add a declarative option for style layers or sources to
  `MapLibreMap`. Events of a style layer are fields of the layer
  (`onClick`, `onEnter`, `onLeave`), not a `layerEvents` map on the widget.
- Annotation layers are built on style layers, but keep their own small,
  declarative API.

```dart
// Do: a declarative parameter, changed with setState()
MapLibreMap(
  options: MapOptions(style: .url(styleUrl)),
  layers: [CircleLayer(points: points)],
);

// Do: imperative style changes
onStyleLoaded: (style) async {
  await style.sources.add(GeoJsonSource.url(id: 'quakes', url: quakesUrl));
  await style.layers.add(CircleStyleLayer(id: 'quakes', sourceId: 'quakes'));
},

// Don't: declarative style layers or a setter for a widget parameter
MapLibreMap(styleLayers: [CircleStyleLayer(...)]);
controller.setStyle(styleUrl);
```

## Types that may grow

Use a `sealed` class with `const` named factory constructors when a value can
take one of several forms. The factories read well with Dart's dot
shorthands, and a new form is a new constructor.

| Type             | Variants                                                    |
|------------------|-------------------------------------------------------------|
| `MapStyle`       | `.url`, `.json`, `.asset`, `.file`                           |
| `CameraUpdate`   | `.position`, `.bounds`, `.points`, `.geometry`              |
| `CameraAnimation`| `.ease`, `.fly`                                             |
| `QueryGeometry`  | `.point`, `.rect`, `.viewport`                              |
| `GeoJsonData`    | `.featureCollection`, `.feature`, `.geometry`, `.json`, `.text` |
| `MarkerIcon`     | `.iconData`, `.asset`, `.bytes`, `.provider`, `.named`, `.expression` |

- Adding a subclass to a sealed class is not a breaking change when apps
  create one instance and pass it in (`CameraUpdate`, `QueryGeometry`) or get
  one at a time (`MapEvent`).
- Prefer one parameter of a sealed type over several parameters that exclude
  each other. A marker has one `icon`, not `icon` and `iconImage`.
- Group related switches into an option class whose fields are optional and
  on by default, with a `.none()` constructor, such as `MapMovements` and
  `MapGestures`. A new switch is a new optional field.

```dart
// Do
controller.animateCamera(
  .position(center: center, zoom: 12),
  animation: const .fly(),
);

// Don't: parameters that exclude each other, or a mode flag
controller.animateCamera(center: center, bounds: bounds, fly: true);
```

## Style layers are their own controllers

Like the layers of the Android and iOS SDKs, a style layer object controls
its layer on the map.

- Every property of the style spec is a typed getter, setter and optional
  constructor parameter, generated from the spec. There are no `paint` or
  `layout` maps and no access by property name.
- Getters are synchronous and read the state that Dart holds. Setters are
  synchronous too and send the change to the map in order, without a
  `Future`. There are no async `setX` methods.
- Properties take a typed `Expression<T>`, with `const .literal(…)` for
  constants, so the same parameter takes a constant, a zoom curve or a value
  per feature.

```dart
// Do
final layer = style.layers['route'] as LineStyleLayer?;
layer?.width = const .literal(6);

// Don't
await controller.setLayerProperty('route', 'line-width', 6);
```

## Sync and async

A member is synchronous when Dart holds the answer: the style layers and
sources, the current `camera`, the options. It returns a `Future` when a
platform has to answer, such as feature queries, `cameraFor`, `toLngLat` and
camera animations. An animation completes with a result
(`CameraAnimationResult`) instead of throwing when a gesture cancels it.

## Events

- One `on…` callback per event on `MapLibreMap` and `MapPlugin`, each with an
  event class of its own, such as `onClick` with `MapEventClick`. Not one
  `onEvent` with a type switch. A new event is a new optional callback.
- A callback that is null is not subscribed: the map doesn't listen for it.
- Events with a default action, such as double click zoom or drag pan, have
  `preventDefault()` on the event.

## Plugins and UI widgets

- Build features that sit on the map as widgets for `MapLibreMap.children`.
  `MapPlugin` gives them the declarative parameters of `MapLibreMap`
  (layers, callbacks, movements and gestures), and `MapController.of`,
  `CameraPosition.of`, `MapOptions.of` and `StyleController.of` give them the
  map's state. A widget that moves with the camera reads `CameraPosition.of`.
- The packages depend on `flutter/widgets` only, never on Material or
  Cupertino, so apps with any design system can use them.
- UI widgets don't read a `Theme`. They have default values for their look
  and take parameters such as `backgroundColor`, `needleColor` or `textStyle`
  to change it.

## One API for every platform

- A feature exists once, for every platform. There are no parameters or
  classes prefixed with a platform (`androidX`, `webX`).
- A feature needs a way to work on every platform before it is added: on
  web through MapLibre GL JS, everywhere else through the C API of
  `maplibre_native_ffi`.
- When a platform can't support something, document it, and fail in a
  documented way, for example with an `UnsupportedError`. A setting that
  only changes how a platform behaves, such as `MapLibreNetwork.offline`,
  may instead have no effect there, as documented, so that apps need no
  platform checks to set it.
- Use the types of [geobase](https://pub.dev/packages/geobase) for geographic
  data: `Geographic` for positions, `GeoBox` for bounds, `Feature` and
  `Geometry` for features. `maplibre` re-exports the ones its API uses.

## Platform conversions

Convert between the types of this plugin and those of a platform (`mln.*`,
gl-js interop types) with extension methods in the platform package's
`lib/src/extensions.dart`, not with static or top-level helpers or members of
interop types.

- Name an extension `<Type>Ext`, or `Mln<Type>Ext` and `Js<Type>Ext` on
  platform types.
- Convert with `toMln()` or `toJs()`, and back with `to<Type>()`.

```dart
// Do
extension GeographicExt on Geographic {
  mln.LatLng toMln() => mln.LatLng(latitude: lat, longitude: lon);
}

extension MlnLatLngExt on mln.LatLng {
  Geographic toGeographic() => Geographic(lon: longitude, lat: latitude);
}

// Don't
mln.LatLng _latLngOf(Geographic position) => ...;
```

## Documentation

- Every public member has a dartdoc comment that starts with one sentence
  saying what it does.
- Name platforms, never the engine behind them: write "only on web", "not on
  web" or a list of platforms, not "on MapLibre Native" or "native maps".
- Don't mark features as experimental, and don't add status columns. A
  feature is either part of the API or not.
- Show new features in the example app and document them on this website.

## Compatibility

`maplibre` follows [semantic versioning](https://dart.dev/tools/pub/versioning):
while it is below 1.0, a new minor version (0.3 to 0.4) is a breaking
release.

- Breaking releases come with a migration guide, such as
  [Upgrade to 0.4](../migrate/upgrade-from-v0.3.x.md), that names the
  replacement of every removed or changed API.
- Every user-facing change gets one short bullet in the changelog of
  `packages/maplibre`.

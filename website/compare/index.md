---
title: Compare
description: How maplibre differs from maplibre_gl, flutter_map, mapbox_maps_flutter and google_maps_flutter.
icon: lucide/scale
hide: [ navigation ]
---

# Compare Map Packages

Flutter has several map packages. This page shows what `maplibre` does
differently and what that means for your app. If you already use another
package, the migration guides show how to move from
[maplibre_gl](../docs/migrate/maplibre_gl.md),
[flutter_map](../docs/migrate/flutter_map.md),
[google_maps_flutter](../docs/migrate/google_maps_flutter.md) and
[mapbox_maps_flutter](../docs/migrate/mapbox_maps_flutter.md).

## What sets maplibre apart

### One API on six platforms

`maplibre` runs on Android, iOS, macOS, Windows, Linux and web with the same
API, gestures and behavior. The other GPU-rendered packages cover Android,
iOS and web only, so desktop apps had to fall back to a different package or
a WebView.

### The map is part of the Flutter widget tree

The map renders into a Flutter `Texture` (an HTML element on web) instead of
a platform view. Widgets over, under and around the map compose like any other
widget, without the performance and layering limits of platform views, and
widgets can be placed at map coordinates.

### Dart first, synchronous where possible

`maplibre` follows the principle that what can be done in Dart is done in
Dart. Gestures, annotations and the UI widgets are written in Dart, so they
behave the same everywhere. It calls MapLibre through FFI (and maplibre-gl-js
through JS interop on web) instead of platform channels, so many values, such
as the camera and the style layers, can be read synchronously.

### Declarative annotations, typed styles

Annotations are declarative layers that you update with `setState()`, like
any other widget. Style layers, sources and expressions are typed Dart
classes, so the compiler catches mistakes that other packages only report at
runtime, if at all.

### Your map data, no API key

`maplibre` shows any MapLibre or Mapbox compatible style, from any tile
provider or your own server. It needs no API key of its own and has no usage
fees; keys and fees depend only on the tile provider you choose. Vector and
raster tiles, PMTiles, MBTiles, MapLibre Tiles, hillshading, heatmaps and 3D
extrusions work out of the box.

### Batteries included

Offline regions, the user location, a compass, a scale bar, attribution, zoom
buttons, clustering, feature queries and events for taps, drags and hover are
part of the package, so you don't assemble them from plugins.

### Maintained in the open

`maplibre` is a
[hosted project](https://github.com/maplibre/maplibre/blob/main/PROJECT_TIERS.md#hosted-project)
of the MapLibre organization, keeps its tech stack up to date and follows
semantic versioning. Every breaking release comes with a
[migration guide](../docs/migrate/upgrade-from-v0.3.x.md).

## At a glance

|                     | maplibre                 | maplibre_gl            | flutter_map              | mapbox_maps_flutter     | google_maps_flutter       |
|---------------------|--------------------------|------------------------|--------------------------|-------------------------|---------------------------|
| Map data            | Any tile provider        | Any tile provider      | Any tile provider        | Mapbox or other providers | Google                  |
| API key and billing | Only if your provider needs one | Only if your provider needs one | Only if your provider needs one | Mapbox access token, billed by usage | Google API key, billed by usage |
| Rendering           | MapLibre, GPU            | MapLibre, GPU          | Flutter canvas, Dart     | Mapbox, GPU             | Google Maps SDKs          |
| Map in Flutter as   | `Texture`, HTML element on web | Platform view, HTML element on web | Widgets                  | Platform view           | Platform view             |
| Android, iOS        | ✅                        | ✅                      | ✅                        | ✅                       | ✅                         |
| Web                 | ✅                        | ✅                      | ✅                        | ✅                       | ✅                         |
| macOS, Windows, Linux | ✅                      | ❌                      | ✅                        | ❌                       | ❌                         |
| Vector tiles        | ✅                        | ✅                      | With `vector_map_tiles`  | ✅                       | ❌ (Google's own maps)     |
| Style spec          | MapLibre, typed          | MapLibre, untyped      | ❌                        | Mapbox                  | Cloud styling or JSON     |
| Annotations         | Declarative layers       | Imperative controller  | Declarative widgets      | Imperative managers     | Declarative sets          |
| Offline regions     | ✅ (not on web)           | Android and iOS        | With plugins             | Android and iOS         | ❌                         |
| Widgets at map coordinates | ✅                        | ❌                      | ✅                        | ❌                       | ❌                         |
| License             | BSD-3-Clause             | BSD-3-Clause           | BSD-3-Clause             | Plugin BSD/MIT, SDK under Mapbox terms | BSD-3-Clause, service under Google terms |

## Compared with each package

### maplibre_gl

Both use the same map styles and tiles. `maplibre_gl` wraps the MapLibre
Android and iOS SDKs and maplibre-gl-js and lets them do the work; `maplibre`
does as much as it can in Dart. That gives `maplibre` the desktop platforms, a
map inside the widget tree instead of a platform view, and declarative
annotations and synchronous reads instead of an imperative, asynchronous
controller.
[Migrate from maplibre_gl](../docs/migrate/maplibre_gl.md).

### flutter_map

`flutter_map` draws the map with the Flutter canvas. `maplibre` draws on the
GPU with MapLibre, which renders vector tiles, large data, labels, 3D
extrusions and hillshading faster, and has those features, offline regions
and the user location built in instead of in separate plugins.
[Migrate from flutter_map](../docs/migrate/flutter_map.md).

### mapbox_maps_flutter

MapLibre started as a fork of the open source Mapbox SDKs, so styles, layers
and expressions are very similar. Unlike `mapbox_maps_flutter`, `maplibre`
needs no Mapbox access token, has no usage fees, works with any tile provider
or your own server, and also runs on desktop platforms.
[Migrate from mapbox_maps_flutter](../docs/migrate/mapbox_maps_flutter.md).

### google_maps_flutter

`google_maps_flutter` is tied to Google's map data and a billed Google Maps
Platform API key. `maplibre` shows any vector or raster tiles with full
control over the style, has style layers for large data, heatmaps and 3D, and
runs on desktop platforms.
[Migrate from google_maps_flutter](../docs/migrate/google_maps_flutter.md).

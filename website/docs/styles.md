---
icon: lucide/map
description: 'Load a map style from a URL, an asset, a file or JSON, and find style providers.'
---

# Styles

By default, the default MapLibre style gets used which shows only countries.
To change this use the style of a tile provider or create and use your own map
style.

Custom map styles can be used by setting the `style` parameter of the map
options like so:

```dart hl_lines="5"
Widget build() {
  return MapLibreMap(
      options: MapOptions(
        style: MapStyle.url('https://demotiles.maplibre.org/style.json'),
      )
  );
}
```

The map loads a new style when `style` changes. The following formats are
supported:

1. `MapStyle.url`: the URL of a map style, such as a custom map style served
   remotely using a URL that starts with `http(s)://`.
2. `MapStyle.asset`: a JSON file in the Flutter assets of the app.
3. `MapStyle.file`: the absolute path of a JSON file, for example in the
   ApplicationDocumentsDirectory. Not supported on web.
4. `MapStyle.json`: the raw JSON of the map style.

Without `MapOptions.initCamera`, the map starts at the camera stored in the
style (its `center`, `zoom`, `bearing` and `pitch`).

## Tile sources that require an API key

If your tile source requires an API key, it is recommended to directly append it
to the url as a query parameter.
For example:

```url
https://tiles.example.com/{z}/{x}/{y}.pbf?api_key={your_key}
```

## Use existing styles

Every tile provider provides map styles that you can use.

!!! warning

      Note, that the style
      needs to be compatible with the tile schema used by the tile server.
      For example OpenMapTiles styles used by MapTiler are not compatible with
      Protomaps tiles.

Have a look at
the [awesome-maplibre](https://github.com/maplibre/awesome-maplibre#maptile-providers)
list to get an overview over available tile
providers that support the MVT standard.

## Create a custom style

Map styles are defined in JSON. MapLibre offers a style editor
called [Maputnik](https://maplibre.org/maputnik)
that allows to customize existing styles or create a new style from scratch.
Other tile providers like MapBox have own editors you can use.

![Maputnik Editor](../assets/images/maputnik.jpg)

## Global state

Layers can read values of the style's global state with the `global-state`
expression (`Expression.globalState`), for example to switch every label
between metric and imperial units at once. The style's `state` sets their
defaults, and `MapOptions.globalState` overrides them:

```dart
MapLibreMap(
  options: MapOptions(
    style: MapStyle.url(styleUrl),
    globalState: {'units': imperial ? 'imperial' : 'metric'},
  ),
)
```

Rebuild with new values to change them: the map sets the values that
changed, and a value that is removed or null goes back to the style's
default. The values also apply to every style that loads later.
`StyleController.globalState` reads the result, the defaults merged with the
options.

## Light

The light of a style shades the sides of fill extrusions. It is part of the
style, so `StyleController.light` reads it and its setters change it, like
the properties of a [style layer](style-layers/paint-and-layout.md):

```dart
onStyleLoaded: (style) {
  style.light
    ..anchor = const .literal(.map)
    ..colorTransition = const StyleTransition(duration: Duration(seconds: 1))
    ..color = const .literal(Color(0xFFFFE0B0))
    ..intensity = const .literal(0.8);
},
```

A newly loaded style has its own light.

## Default transition

Paint properties without a transition of their own, such as
`FillStyleLayer.colorTransition`, change over the style's transition, 300 ms
unless the style's `transition` sets another. `StyleController.transition`
reads and changes it for the changes that follow:

```dart
style.transition = const StyleTransition(duration: Duration(seconds: 1));
```

A newly loaded style has its own.

## Label placement transitions

Labels fade in and out as their collisions with other labels change, over
the style's `transition` duration on native (300 ms unless the style sets
one) and over 300 ms on web. `setPlacementTransitions` turns the fade off, so
labels show and hide at once:

```dart
MapLibreMap(
  onStyleLoaded: (style) => style.setPlacementTransitions(enabled: false),
)
```

A newly loaded style has them on again.

On web, turning it off also ends the crossfade of `*-pattern` and
`line-dasharray` values between zoom levels.

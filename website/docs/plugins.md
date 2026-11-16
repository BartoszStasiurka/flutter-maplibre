---
icon: lucide/puzzle
---

# Plugins

A plugin is a widget in the `children` of `MapLibreMap`. Plugins can come
from your app or from a package, and every widget in `children` can do what
a plugin does.

```dart
MapLibreMap(
  layers: [/* the app's own layers */],
  children: [
    const SourceAttribution(),
    if (measuring) const MeasureLine(),
  ],
)
```

Adding a plugin to `children` turns it on and removing it turns it off,
along with everything it added to the map.

## What a plugin can do

### Read the map

Every widget below the map can call these:

| Call                                     | Returns                                          | The widget rebuilds when                               |
| ---------------------------------------- | ------------------------------------------------ | ------------------------------------------------------ |
| `MapController.of(context)` / `maybeOf`  | The controller: camera moves, queries, the style | The controller, options or style change, or the map pauses or resumes rendering |
| `CameraPosition.of(context)` / `maybeOf` | The current camera                               | The camera moves                                       |
| `MapOptions.of(context)` / `maybeOf`     | The `MapLibreMap.options`                        | The options change                                     |
| `StyleController.of(context)` / `maybeOf` | The loaded style: layers, sources, attributions | A style loads, layers or sources come, go or move, or the attributions change |

Only `CameraPosition.of` rebuilds the widget while the camera moves. Use it
when a widget shows something that depends on the camera, such as a
position on the screen. Use `MapController.of` alone for a widget that only
calls the controller, such as a button.

`StyleController.of` suits a widget that lists what the style has, such as
a layer switcher or a legend. It doesn't rebuild when the properties of a
layer or the data of a source change, as apps change those every frame. Code
outside of `build` can listen to the `StyleController`, its `layers` or its
`sources` instead.

### Draw over the map

A plugin builds Flutter widgets that show above the map, like any other
widget in `children`. `MapController.toScreenLocations` turns coordinates
into positions on the screen.

### Add layers, listen to events and limit movements

The `MapPlugin` widget takes the same layers and callbacks as `MapLibreMap`:

```dart
class MeasureLine extends StatefulWidget {
  const MeasureLine({super.key});

  @override
  State<MeasureLine> createState() => _MeasureLineState();
}

class _MeasureLineState extends State<MeasureLine> {
  final _points = <Geographic>[];

  @override
  Widget build(BuildContext context) => MapPlugin(
    // Adds a point at every tap.
    onClick: (event) => setState(() => _points.add(event.point)),
    // Shown above the layers of MapLibreMap.
    layers: [
      if (_points.length > 1)
        PolylineLayer(polylines: [Feature(geometry: LineString.from(_points))]),
      CircleLayer(
        points: [for (final point in _points) Feature(geometry: Point(point))],
      ),
    ],
    // The user can't rotate the map while the plugin is shown.
    movements: const MapMovements(rotate: false),
    // A Flutter widget over the map, laid out like a widget in children.
    child: const Align(alignment: Alignment.topCenter, child: Text('Tap to measure')),
  );
}
```

The map combines every `MapPlugin` with its own parameters:

- **Layers** show above `MapLibreMap.layers`, the layers of later plugins
  above those of earlier ones. They stay on the map when the style changes,
  and their `onClick`, `onEnter`, `onLeave` and `draggable` work as on
  [annotation layers](annotations/index.md).
- **Taps, clicks, drags and mouse moves** go to the plugins under the
  pointer first, the topmost first, and then to the callbacks of
  `MapLibreMap`. Every callback gets the event, so a plugin can't keep it
  from your app. A plugin can call `preventDefault` on a double click or
  the start of a drag to stop the map from zooming or panning, and the
  callbacks after it see that in `defaultPrevented`.
- **Other events**, such as camera moves, style loads and errors, go to every
  plugin and then to `MapLibreMap`.
- **Movements and gestures** of a plugin can only turn things off: the
  user's gestures move the map only the ways that `MapOptions` and every
  plugin allow. Camera calls, such as `animateCamera`, are not limited.

A `MapPlugin` fills the map and never takes a pointer itself, so the map
still gets the pointers its `child` lets through. Wrap it in a `Positioned`
to receive the taps of only a part of the map.

### Share a corner with other widgets

Wrap a plugin's button in a `MapAlignItem`. Alone, it places the button at
its own alignment. Inside a `MapAlign`, the group places it next to the
built-in widgets without overlapping. See
[User Interface](ui.md#placing-widgets).

## Packages that extend maplibre

| Package                                                               | What it does                                                                                                                                   |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| [maplibre_geolocator](https://pub.dev/packages/maplibre_geolocator)   | Turns the positions of [geolocator](https://pub.dev/packages/geolocator) into the location stream of the [UserLocationLayer](user-location.md) plugin. |
| [flutter_map_maplibre](https://pub.dev/packages/flutter_map_maplibre) | Shows a MapLibre map with vector tiles in [flutter_map](https://pub.dev/packages/flutter_map). Its current release needs maplibre 0.3.          |

Built a plugin or another package for maplibre? Open a pull request to add
it here.

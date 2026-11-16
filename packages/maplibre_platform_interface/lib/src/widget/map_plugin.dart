import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';
import 'package:maplibre_platform_interface/src/widget/inherited_model.dart';
import 'package:maplibre_platform_interface/src/widget/map_plugin_registry.dart';

/// Lets a widget in [MapLibreMap.children], such as a plugin, add to the
/// map what the app declares with the parameters of [MapLibreMap]: layers,
/// event callbacks and limits on how the map moves.
///
/// The map combines every [MapPlugin] below it with its own parameters:
///
/// - [layers] show above [MapLibreMap.layers], the layers of later plugins
///   in the tree above those of earlier ones. They survive style changes
///   and report taps, drags and the mouse like [MapLibreMap.layers].
/// - Taps, clicks, drags and mouse moves go to the plugins at the pointer
///   first, the topmost first and inner plugins before outer ones, in the
///   order that Flutter hit-tests widgets. Then they go to the callbacks of
///   [MapLibreMap]. A drag goes to the plugins at its start until it ends.
///   Every callback gets the event: a plugin can't keep it from the others,
///   but it can call `preventDefault` on [MapEventDoubleClick] and
///   [MapEventDragStart], which the callbacks after it can read with
///   `defaultPrevented`. The other events go to every plugin, in tree order,
///   and then to [MapLibreMap].
/// - [movements] and [gestures] can only turn movements and gestures of the
///   user off: the gestures do what [MapOptions.movements] and
///   [MapOptions.gestures] and every plugin allow. Camera calls are not
///   limited.
///
/// A plugin fills the map and lays out [child] at its top left, with at
/// most the size of the map.
/// Wrap it in a [Positioned] to receive the taps of only a part of the map.
/// It never takes a pointer itself, so the map below it still receives the
/// pointers that [child] lets through.
///
/// Removing the plugin from the tree removes its layers and callbacks and
/// lifts its limits.
///
/// ```dart
/// class MeasureLine extends StatefulWidget {
///   const MeasureLine({super.key});
///
///   @override
///   State<MeasureLine> createState() => _MeasureLineState();
/// }
///
/// class _MeasureLineState extends State<MeasureLine> {
///   final _points = <Geographic>[];
///
///   @override
///   Widget build(BuildContext context) => MapPlugin(
///     onClick: (event) => setState(() => _points.add(event.point)),
///     layers: [
///       if (_points.length > 1)
///         PolylineLayer(
///           polylines: [Feature(geometry: LineString.from(_points))],
///         ),
///     ],
///   );
/// }
/// ```
///
/// {@category Basic}
@immutable
class MapPlugin extends StatefulWidget {
  /// Creates a plugin of the map above it.
  const MapPlugin({
    this.layers = const [],
    this.movements = const MapMovements(),
    this.gestures = const MapGestures(),
    this.onStyleLoaded,
    this.onClick,
    this.onDoubleClick,
    this.onSecondaryClick,
    this.onLongClick,
    this.onDragStart,
    this.onDrag,
    this.onDragEnd,
    this.onPointerMove,
    this.onPointerLeave,
    this.onCameraMoveStart,
    this.onCameraMove,
    this.onCameraMoveEnd,
    this.onIdle,
    this.onError,
    this.onStyleImageMissing,
    this.onLoadingStarted,
    this.onLoadingFinished,
    this.onSourceChanged,
    this.onTile,
    this.onRenderFrame,
    this.onRenderMap,
    this.onGlyphs,
    this.onSprite,
    this.onRenderingChanged,
    this.onResize,
    this.onContextLost,
    this.onContextRestored,
    this.onProjectionChanged,
    this.child,
    super.key,
  });

  /// Layers that show above [MapLibreMap.layers], see [MapLibreMap.layers].
  final List<Layer> layers;

  /// The movements that the plugin allows the gestures of the user. They
  /// only move the map the ways that [MapOptions.movements] and every
  /// plugin allow, so a plugin can stop the user from rotating the map
  /// while it is shown, for example. Camera calls such as
  /// [MapController.animateCamera] still move the map in every way.
  final MapMovements movements;

  /// The gestures that the plugin allows, combined like [movements]. The
  /// [MapGestures.rotateThreshold] of [MapOptions.gestures] stays.
  final MapGestures gestures;

  /// See [MapLibreMap.onStyleLoaded]. The plugin is added once the map is
  /// created, so it only hears the styles that load later. The current one
  /// is [MapController.style].
  final StyleLoadedCallback? onStyleLoaded;

  /// See [MapLibreMap.onClick].
  final MapEventCallback<MapEventClick>? onClick;

  /// See [MapLibreMap.onDoubleClick]. The map waits for a returned [Future]
  /// before it calls the next callback.
  final FutureOr<void> Function(MapEventDoubleClick event)? onDoubleClick;

  /// See [MapLibreMap.onSecondaryClick].
  final MapEventCallback<MapEventSecondaryClick>? onSecondaryClick;

  /// See [MapLibreMap.onLongClick].
  final MapEventCallback<MapEventLongClick>? onLongClick;

  /// See [MapLibreMap.onDragStart]. The map waits for a returned [Future]
  /// before it calls the next callback.
  final FutureOr<void> Function(MapEventDragStart event)? onDragStart;

  /// See [MapLibreMap.onDrag].
  final MapEventCallback<MapEventDrag>? onDrag;

  /// See [MapLibreMap.onDragEnd].
  final MapEventCallback<MapEventDragEnd>? onDragEnd;

  /// See [MapLibreMap.onPointerMove].
  final MapEventCallback<MapEventPointerMove>? onPointerMove;

  /// See [MapLibreMap.onPointerLeave].
  final MapEventCallback<MapEventPointerLeave>? onPointerLeave;

  /// See [MapLibreMap.onCameraMoveStart].
  final MapEventCallback<MapEventCameraMoveStart>? onCameraMoveStart;

  /// See [MapLibreMap.onCameraMove].
  final MapEventCallback<MapEventCameraMove>? onCameraMove;

  /// See [MapLibreMap.onCameraMoveEnd].
  final MapEventCallback<MapEventCameraMoveEnd>? onCameraMoveEnd;

  /// See [MapLibreMap.onIdle].
  final MapEventCallback<MapEventIdle>? onIdle;

  /// See [MapLibreMap.onError].
  final MapEventCallback<MapEventError>? onError;

  /// See [MapLibreMap.onStyleImageMissing].
  final MapEventCallback<MapEventStyleImageMissing>? onStyleImageMissing;

  /// See [MapLibreMap.onLoadingStarted].
  final MapEventCallback<MapEventLoadingStarted>? onLoadingStarted;

  /// See [MapLibreMap.onLoadingFinished].
  final MapEventCallback<MapEventLoadingFinished>? onLoadingFinished;

  /// See [MapLibreMap.onSourceChanged].
  final MapEventCallback<MapEventSourceChanged>? onSourceChanged;

  /// See [MapLibreMap.onTile].
  final MapEventCallback<MapEventTile>? onTile;

  /// See [MapLibreMap.onRenderFrame].
  final MapEventCallback<MapEventRenderFrame>? onRenderFrame;

  /// See [MapLibreMap.onRenderMap].
  final MapEventCallback<MapEventRenderMap>? onRenderMap;

  /// See [MapLibreMap.onGlyphs].
  final MapEventCallback<MapEventGlyphs>? onGlyphs;

  /// See [MapLibreMap.onSprite].
  final MapEventCallback<MapEventSprite>? onSprite;

  /// See [MapLibreMap.onRenderingChanged].
  final MapEventCallback<MapEventRenderingChanged>? onRenderingChanged;

  /// See [MapLibreMap.onResize].
  final MapEventCallback<MapEventResize>? onResize;

  /// See [MapLibreMap.onContextLost].
  final MapEventCallback<MapEventContextLost>? onContextLost;

  /// See [MapLibreMap.onContextRestored].
  final MapEventCallback<MapEventContextRestored>? onContextRestored;

  /// See [MapLibreMap.onProjectionChanged].
  final MapEventCallback<MapEventProjectionChanged>? onProjectionChanged;

  /// A widget that the plugin shows over the map, at its top left and at
  /// most as large as the map. Use a [Stack] to position several widgets.
  final Widget? child;

  @override
  State<MapPlugin> createState() => _MapPluginState();
}

class _MapPluginState extends State<MapPlugin> implements MapPluginEntry {
  MapPluginRegistry? _registry;

  @override
  MapPlugin get plugin => widget;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = MapLibreInheritedModel.maybePluginsOf(context);
    if (identical(registry, _registry)) return;
    _registry?.remove(this);
    _registry = registry?..add(this);
  }

  @override
  void didUpdateWidget(covariant MapPlugin oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The map reads the callbacks from the current widget when it calls
    // them, so it only needs to know which ones are set.
    if (_shapeChanged(oldWidget, widget)) {
      _registry?.update(this, structural: true);
    } else if (!_sameLayers(oldWidget.layers, widget.layers)) {
      _registry?.update(this, structural: false);
    }
  }

  static bool _sameLayers(List<Layer> a, List<Layer> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Whether [a] and [b] differ in what the map listens for or allows.
  static bool _shapeChanged(MapPlugin a, MapPlugin b) =>
      a.movements != b.movements ||
      a.gestures != b.gestures ||
      !listEquals(mapPluginCallbacksSet(a), mapPluginCallbacksSet(b));

  @override
  void activate() {
    super.activate();
    // Moved in the tree with a GlobalKey, possibly below another map.
    final registry = MapLibreInheritedModel.maybePluginsOf(context);
    if (!identical(registry, _registry)) _registry?.remove(this);
    _registry = registry?..add(this);
  }

  @override
  void deactivate() {
    _registry?.remove(this);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) =>
      MapPluginRenderWidget(entry: this, child: widget.child);
}

/// Which callbacks of [p] are set, one entry for every callback of
/// [MapPlugin]. The map only needs to know again when this changes.
@visibleForTesting
List<bool> mapPluginCallbacksSet(MapPlugin p) => [
  p.onStyleLoaded != null,
  p.onClick != null,
  p.onDoubleClick != null,
  p.onSecondaryClick != null,
  p.onLongClick != null,
  p.onDragStart != null,
  p.onDrag != null,
  p.onDragEnd != null,
  p.onPointerMove != null,
  p.onPointerLeave != null,
  p.onCameraMoveStart != null,
  p.onCameraMove != null,
  p.onCameraMoveEnd != null,
  p.onIdle != null,
  p.onError != null,
  p.onStyleImageMissing != null,
  p.onLoadingStarted != null,
  p.onLoadingFinished != null,
  p.onSourceChanged != null,
  p.onTile != null,
  p.onRenderFrame != null,
  p.onRenderMap != null,
  p.onGlyphs != null,
  p.onSprite != null,
  p.onRenderingChanged != null,
  p.onResize != null,
  p.onContextLost != null,
  p.onContextRestored != null,
  p.onProjectionChanged != null,
];

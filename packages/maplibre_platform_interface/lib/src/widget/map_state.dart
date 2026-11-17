import 'dart:async';

import 'package:flutter/rendering.dart' show BoxHitTestResult;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';
import 'package:maplibre_platform_interface/src/layer/annotation_manager.dart';
import 'package:maplibre_platform_interface/src/widget/inherited_model.dart';
import 'package:maplibre_platform_interface/src/widget/map_plugin_registry.dart';

/// The [State] of the [MapLibreMap] widget.
abstract class MapLibreMapState extends State<MapLibreMap>
    implements MapController {
  /// The counter is used to ensure an unique [viewName] for the platform view.
  static int _counter = 0;

  /// A unique name for the platform view.
  final viewName = 'plugins.flutter.io/maplibre${_counter++}';

  /// Keeps the layers of [MapLibreMap.layers] on every style of the map.
  late final AnnotationManager _annotations;

  /// Adds the layers of [MapLibreMap.layers] to [style], which just loaded.
  /// Platforms call it after [MapLibreMap.onStyleLoaded].
  @protected
  void attachAnnotations(StyleController style) => _annotations.attach(style);

  /// Forgets the style of the layers of [MapLibreMap.layers], which is about
  /// to be replaced. Platforms call it.
  @protected
  void detachAnnotations() => _annotations.detach();

  /// The id of the style layer and source of [layer] of [MapLibreMap.layers],
  /// or null if it is not in the list.
  @visibleForTesting
  String? annotationLayerId(Layer layer) {
    for (final entry in _annotations.entries) {
      if (identical(entry.layer, layer)) return entry.id;
    }
    return null;
  }

  /// Get the [MapOptions] from [MapLibreMap.options].
  @override
  MapOptions get options => widget.options;

  @override
  CameraPosition? camera;

  /// Set to true once the map is initialized and a [MapController.camera]
  /// is set.
  bool isInitialized = false;

  @override
  bool get isRenderingPaused => _renderingPaused;
  var _renderingPaused = false;

  /// Stops or resumes rendering, see [MapLibreMap.paused]. Called whenever
  /// [isRenderingPaused] changes, including when the map starts out paused.
  /// The map keeps its style, camera and tiles meanwhile.
  @protected
  void setRenderingPaused({required bool paused}) {}

  /// Whether the platform stops rendering a paused map. Where it does not,
  /// [isRenderingPaused] stays false.
  @protected
  bool get canPauseRendering => true;

  @override
  void initState() {
    super.initState();
    _annotations = AnnotationManager(widget.layers);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRenderingPaused();
  }

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _annotations.update(effectiveWidget.layers);
    if (oldWidget.paused != widget.paused) _updateRenderingPaused();
    final targetCamera = widget.camera;
    if (targetCamera != null && targetCamera != oldWidget.camera) {
      applyCamera(targetCamera);
    }
    // Plugins among the new children may have moved.
    if (!identical(oldWidget.children, widget.children) &&
        _plugins.entries.length > 1) {
      _plugins.checkOrder();
    }
    didUpdateCallbacks();
  }

  /// Pauses the map while [MapLibreMap.paused] is set, while a [Visibility]
  /// or an [IndexedStack] hides it, or while [TickerMode] is disabled.
  void _updateRenderingPaused() {
    final paused =
        canPauseRendering &&
        (widget.paused ||
            !TickerMode.valuesOf(context).enabled ||
            !Visibility.of(context));
    if (paused == _renderingPaused) return;
    _renderingPaused = paused;
    setRenderingPaused(paused: paused);
    // This runs while the tree builds, where listeners must not rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _renderingPaused == paused) {
        effectiveWidget.onRenderingChanged?.call(
          MapEventRenderingChanged(paused: paused),
        );
      }
    });
  }

  /// Moves the camera to [camera] of [MapLibreMap.camera] while the widget
  /// builds, after it changed. The platform takes the initial one as the
  /// initial camera of the map instead.
  @protected
  void applyCamera(CameraPosition camera) {}

  /// The camera that the map starts at: [MapLibreMap.camera], or else
  /// [MapOptions.initCamera].
  @protected
  CameraUpdate? get initialCamera =>
      widget.camera?.toCameraUpdate() ?? options.initCamera;

  /// Applies the camera changes of the map gestures that
  /// [MapGestureDetector] recognizes over [buildPlatformWidget], or null if
  /// the platform handles gestures itself.
  GestureCameraSink? get gestureCamera => null;

  /// The feature of [MapLibreMap.layers] that the current drag moves.
  _LayerDrag? _layerDrag;

  /// Whether a layer of [MapLibreMap.layers] has draggable features.
  bool get _layersDraggable =>
      effectiveWidget.layers.any((layer) => layer.draggable);

  /// Counts the drags, so that a feature query of a drag that ended or was
  /// followed by another one is dropped.
  var _dragGeneration = 0;

  /// The search of the current drag for a feature to move, until it and the
  /// start callbacks complete.
  Future<void>? _dragStarting;

  /// The last move of the current drag while it starts, which is reported
  /// once it started.
  MapEventDrag? _heldDrag;

  FutureOr<void> _onDragStart(MapEventDragStart event) {
    _layerDrag = null;
    _heldDrag = null;
    final generation = ++_dragGeneration;
    final onDragStart = effectiveWidget.onDragStart;
    if (!_layersDraggable) return onDragStart?.call(event);
    final starting = _grabFeature(
      event,
      generation,
    ).then((_) => onDragStart?.call(event));
    _dragStarting = starting;
    unawaited(
      _afterStart(starting, () {
        if (!identical(_dragStarting, starting)) return;
        _dragStarting = null;
        final held = _heldDrag;
        _heldDrag = null;
        if (held != null && mounted) _onDrag(held);
      }),
    );
    // The gesture detector reports the errors of the start.
    return starting;
  }

  /// Runs [callback] once [starting] completes. Reports the errors of
  /// [callback], but not those of [starting], which the gesture detector
  /// reports.
  Future<void> _afterStart(
    Future<void> starting,
    void Function() callback,
  ) async {
    try {
      await starting;
    } on Object catch (_) {}
    try {
      callback();
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while handling a drag');
    }
  }

  void _reportError(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'maplibre',
        context: ErrorDescription(context),
      ),
    );
  }

  /// Finds the feature of a draggable layer that [event] went down on, and
  /// keeps the drag from panning the map if it found one.
  Future<void> _grabFeature(MapEventDragStart event, int generation) async {
    final hits = await _queryLayers(
      .rect(
        Rect.fromCenter(
          center: event.screenPoint,
          width: _grabSize,
          height: _grabSize,
        ),
      ),
      (layer) => layer.draggable,
      'while finding the feature to drag',
    );
    if (hits == null || generation != _dragGeneration) return;
    final hit = _topmost(hits.layers, event.screenPoint);
    if (hit == null) return;
    event.preventDefault();
    _layerDrag = _LayerDrag(hit, event.screenPoint);
    _annotations.startDrag(hit.entry, hit.featureIndex);
    _emitLayerDrag(event.screenPoint, (layer) => layer.onDragStart);
  }

  /// The features in [geometry] of the layers of [MapLibreMap.layers] that
  /// [include] picks and of the style layers that [includeStyle] picks, or
  /// null if the query failed or the map is gone.
  Future<_Hits?> _queryLayers(
    QueryGeometry geometry,
    bool Function(Layer layer) include,
    String context, {
    bool Function(StyleLayer layer)? includeStyle,
  }) async {
    final entries = <String, AnnotationEntry>{
      for (final entry in _annotations.entries)
        if (include(entry.layer)) entry.id: entry,
    };
    final styleLayerIds = {
      if (includeStyle != null)
        for (final layer in style?.layers ?? const <StyleLayer>[])
          if (includeStyle(layer) && !_annotations.ownsLayer(layer.id))
            layer.id,
    };
    if (entries.isEmpty && styleLayerIds.isEmpty) return const _Hits();
    final List<RenderedFeature> features;
    try {
      features = await queryRenderedFeatures(
        geometry,
        layerIds: [...entries.keys, ...styleLayerIds],
      );
    } on Object catch (error, stack) {
      _reportError(error, stack, context);
      return null;
    }
    if (!mounted) return null;
    return _Hits(
      layers: _layerHits(features, entries, include),
      styleLayers: [
        for (final feature in features)
          if (styleLayerIds.contains(feature.layerId)) feature,
      ],
    );
  }

  /// The features of [features] of the layers of [MapLibreMap.layers] by
  /// the ids of their style layers in [entries].
  List<_LayerHit> _layerHits(
    List<RenderedFeature> features,
    Map<String, AnnotationEntry> entries,
    bool Function(Layer layer) include,
  ) {
    // The draw order of the style layers, which anchors make differ from
    // the order of the list.
    final order = <String, int>{
      for (final (index, layer)
          in (style?.layers ?? const <StyleLayer>[]).indexed)
        layer.id: index,
    };
    final hits = <_LayerHit>[];
    for (final feature in features) {
      final entry = entries[feature.layerId];
      final featureIndex =
          feature.properties[AnnotationManager.featureIndexProperty];
      if (entry == null || !entry.mounted || featureIndex is! num) continue;
      final layer = entry.layer;
      if (!include(layer) || featureIndex >= layer.list.length) continue;
      final listFeature = layer.list[featureIndex.toInt()];
      final geometry = listFeature.geometry;
      if (geometry == null) continue;
      hits.add(
        _LayerHit(
          entry,
          order[entry.id] ?? _annotations.entries.indexOf(entry),
          featureIndex.toInt(),
          listFeature,
          geometry,
        ),
      );
    }
    return hits;
  }

  /// Of [hits], the one of the topmost layer, and of its points the nearest
  /// to [center].
  _LayerHit? _topmost(List<_LayerHit> hits, Offset center) {
    _LayerHit? nearest;
    var nearestDistance = double.infinity;
    for (final hit in hits) {
      var distance = 0.0;
      if (hit.geometry case Point(:final position)) {
        distance =
            (toScreenLocation(Geographic.from(position)) - center).distance;
      }
      if (nearest == null ||
          hit.drawIndex > nearest.drawIndex ||
          (hit.drawIndex == nearest.drawIndex && distance < nearestDistance)) {
        nearest = hit;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  /// Whether a layer of [MapLibreMap.layers] reports taps on its features.
  bool get _layersClickable =>
      effectiveWidget.layers.any((layer) => layer.onClick != null);

  /// Whether a layer of [StyleController.layers] reports taps on its
  /// features.
  bool get _styleLayersClickable => style?.layers.any(_styleClickable) ?? false;

  static bool _styleClickable(StyleLayer layer) => layer.onClick != null;

  void _onClick(MapEventClick event) {
    effectiveWidget.onClick?.call(event);
    if (_layersClickable || _styleLayersClickable) {
      unawaited(_clickFeature(event));
    }
  }

  /// Reports a tap to [Layer.onClick] of the topmost feature under it, or,
  /// if none is right under it, next to it, and to [StyleLayer.onClick] of
  /// every style layer with a feature right under it.
  Future<void> _clickFeature(MapEventClick event) async {
    bool clickable(Layer layer) => layer.onClick != null;
    const context = 'while finding the clicked feature';
    final hits = await _queryLayers(
      .point(event.screenPoint),
      clickable,
      context,
      includeStyle: _styleClickable,
    );
    if (hits == null) return;
    var layerHits = hits.layers;
    // Only annotation layers take taps next to their features, like drags.
    if (layerHits.isEmpty && _layersClickable) {
      layerHits =
          (await _queryLayers(
            .rect(
              Rect.fromCenter(
                center: event.screenPoint,
                width: _grabSize,
                height: _grabSize,
              ),
            ),
            clickable,
            context,
          ))?.layers ??
          const [];
    }
    if (_topmost(layerHits, event.screenPoint) case final hit?) {
      _emitLayerEvent(hit, event, _layerOf(hit.entry)?.onClick);
    }
    for (final (layer, feature) in _topmostPerStyleLayer(
      hits.styleLayers,
      _styleClickable,
    )) {
      _emitStyleLayerEvent(layer, layer.onClick, feature, event);
    }
  }

  /// The topmost feature of [features] of each style layer that [include]
  /// picks.
  List<(StyleLayer, RenderedFeature)> _topmostPerStyleLayer(
    List<RenderedFeature> features,
    bool Function(StyleLayer layer) include,
  ) {
    final topmost = <String, (StyleLayer, RenderedFeature)>{};
    for (final feature in features) {
      final layerId = feature.layerId;
      if (layerId == null || topmost.containsKey(layerId)) continue;
      if (style?.layers[layerId] case final layer? when include(layer)) {
        // Rendered features come topmost first.
        topmost[layerId] = (layer, feature);
      }
    }
    return topmost.values.toList();
  }

  void _emitStyleLayerEvent(
    StyleLayer layer,
    StyleLayerFeatureCallback? callback,
    RenderedFeature feature,
    MapEventUserInput input,
  ) {
    // Removing the layer or loading another style ends its calls.
    if (callback == null || !identical(style?.layers[layer.id], layer)) return;
    try {
      callback(
        StyleLayerFeatureEvent(
          feature: feature,
          point: input.point,
          screenPoint: input.screenPoint,
        ),
      );
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while handling a style layer event');
    }
  }

  void _emitLayerEvent(
    _LayerHit hit,
    MapEventUserInput input,
    LayerFeatureCallback? callback,
  ) {
    if (callback == null) return;
    try {
      callback(
        LayerFeatureEvent(
          index: hit.featureIndex,
          feature: hit.feature,
          geometry: hit.geometry,
          point: input.point,
          screenPoint: input.screenPoint,
        ),
      );
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while handling a layer event');
    }
  }

  /// Whether a layer of [MapLibreMap.layers] reports the mouse over its
  /// features.
  bool get _layersHoverable => effectiveWidget.layers.any(_hoverable);

  static bool _hoverable(Layer layer) =>
      layer.onEnter != null || layer.onLeave != null;

  /// Whether a layer of [StyleController.layers] reports the mouse over its
  /// features.
  bool get _styleLayersHoverable => style?.layers.any(_styleHoverable) ?? false;

  static bool _styleHoverable(StyleLayer layer) =>
      layer.onEnter != null || layer.onLeave != null;

  /// The layer of [entry] while it is in [MapLibreMap.layers].
  static Layer? _layerOf(AnnotationEntry entry) =>
      entry.mounted ? entry.layer : null;

  /// The feature under the mouse, by layer.
  final _hovered = <AnnotationEntry, _LayerHit>{};

  /// The feature under the mouse, by style layer id.
  final _hoveredStyle = <String, (StyleLayer, RenderedFeature)>{};

  /// The last mouse position over the map.
  MapEventPointerMove? _hoverInput;

  /// Whether a query for the features under the mouse runs.
  var _hoverQuerying = false;

  /// Counts the times the mouse left the map, so that a query that started
  /// before is dropped.
  var _hoverGeneration = 0;

  void _onPointerMove(MapEventPointerMove event) {
    effectiveWidget.onPointerMove?.call(event);
    if (!_layersHoverable &&
        !_styleLayersHoverable &&
        _hovered.isEmpty &&
        _hoveredStyle.isEmpty) {
      return;
    }
    _hoverInput = event;
    unawaited(_hover());
  }

  void _onPointerLeave(MapEventPointerLeave event) {
    effectiveWidget.onPointerLeave?.call(event);
    _hoverGeneration++;
    final input = _hoverInput;
    _hoverInput = null;
    if (input != null) _updateHovered(const _Hits(), input);
  }

  /// Queries the features under the mouse, coalescing moves while a query
  /// runs.
  Future<void> _hover() async {
    if (_hoverQuerying) return;
    _hoverQuerying = true;
    try {
      MapEventPointerMove? queried;
      while (_hoverInput != null && !identical(_hoverInput, queried)) {
        final input = queried = _hoverInput!;
        final generation = _hoverGeneration;
        final hits = await _queryLayers(
          .point(input.screenPoint),
          _hoverable,
          'while finding the hovered feature',
          includeStyle: _styleHoverable,
        );
        if (hits == null || generation != _hoverGeneration) continue;
        _updateHovered(hits, input);
      }
    } finally {
      _hoverQuerying = false;
    }
  }

  /// Reports the features of [hits] that the mouse entered and the ones it
  /// left. Per layer, the topmost feature counts.
  void _updateHovered(_Hits hits, MapEventUserInput input) {
    _updateHoveredStyle(hits.styleLayers, input);
    final now = <AnnotationEntry, _LayerHit>{};
    for (final hit in hits.layers) {
      // Rendered features come topmost first.
      now.putIfAbsent(hit.entry, () => hit);
    }
    for (final MapEntry(key: entry, value: hit) in _hovered.entries) {
      if (now[entry]?.featureIndex == hit.featureIndex) continue;
      _emitLayerEvent(hit, input, _layerOf(entry)?.onLeave);
    }
    for (final MapEntry(key: entry, value: hit) in now.entries) {
      if (_hovered[entry]?.featureIndex == hit.featureIndex) continue;
      _emitLayerEvent(hit, input, _layerOf(entry)?.onEnter);
    }
    _hovered
      ..clear()
      ..addAll(now);
  }

  /// Reports the features of style layers in [features] that the mouse
  /// entered and the ones it left. Features without an id stand for their
  /// whole layer.
  void _updateHoveredStyle(
    List<RenderedFeature> features,
    MapEventUserInput input,
  ) {
    final now = {
      for (final entry in _topmostPerStyleLayer(features, _styleHoverable))
        entry.$1.id: entry,
    };
    bool same(
      (StyleLayer, RenderedFeature)? a,
      (StyleLayer, RenderedFeature) b,
    ) => a != null && identical(a.$1, b.$1) && a.$2.id == b.$2.id;
    for (final entry in _hoveredStyle.entries) {
      if (same(now[entry.key], entry.value)) continue;
      final (layer, feature) = entry.value;
      _emitStyleLayerEvent(layer, layer.onLeave, feature, input);
    }
    for (final entry in now.entries) {
      if (same(_hoveredStyle[entry.key], entry.value)) continue;
      final (layer, feature) = entry.value;
      _emitStyleLayerEvent(layer, layer.onEnter, feature, input);
    }
    _hoveredStyle
      ..clear()
      ..addAll(now);
  }

  void _onDrag(MapEventDrag event) {
    // Moves come after the start callbacks.
    if (_dragStarting != null) {
      _heldDrag = event;
      return;
    }
    final moved = _emitLayerDrag(event.screenPoint, (layer) => layer.onDrag);
    if (moved != null) _annotations.moveDrag(moved);
    effectiveWidget.onDrag?.call(event);
  }

  void _onDragEnd(MapEventDragEnd event) {
    // A drag that ends while it looks for its feature ends once it found it,
    // so that the callbacks come in order.
    final starting = _dragStarting;
    if (starting == null) return _endLayerDrag(event);
    final generation = _dragGeneration;
    unawaited(
      _afterStart(starting, () {
        if (!mounted) return;
        if (generation == _dragGeneration) return _endLayerDrag(event);
        effectiveWidget.onDragEnd?.call(event);
      }),
    );
  }

  void _endLayerDrag(MapEventDragEnd event) {
    final moved = _emitLayerDrag(event.screenPoint, (layer) => layer.onDragEnd);
    if (moved != null) _annotations.moveDrag(moved);
    _annotations.endDrag();
    _layerDrag = null;
    effectiveWidget.onDragEnd?.call(event);
  }

  /// Reports the pointer at [screenPoint] to the callback that [callback]
  /// picks of the layer of the current drag, with the dragged geometry,
  /// which it returns.
  Geometry? _emitLayerDrag(
    Offset screenPoint,
    LayerFeatureCallback? Function(Layer layer) callback,
  ) {
    final drag = _layerDrag;
    if (drag == null || !isInitialized) return null;
    final hit = drag.hit;
    final layer = _layerOf(hit.entry);
    if (layer == null ||
        !layer.draggable ||
        hit.featureIndex >= layer.list.length) {
      return null;
    }
    final delta = screenPoint - drag.start;
    final geometry = _moved(hit.geometry, delta);
    final (point, target) = switch (geometry) {
      Point(:final position) => (
        Geographic.from(position),
        toScreenLocation(Geographic.from(position)),
      ),
      _ => (toLngLat(screenPoint), screenPoint),
    };
    callback(layer)?.call(
      LayerFeatureEvent(
        index: hit.featureIndex,
        feature: hit.feature,
        geometry: geometry,
        point: point,
        screenPoint: target,
      ),
    );
    return geometry;
  }

  /// [geometry] moved by [delta] on screen. Only the geometries of the
  /// annotation layers move.
  Geometry _moved(Geometry geometry, Offset delta) {
    Geographic move(Position position) =>
        toLngLat(toScreenLocation(Geographic.from(position)) + delta);
    List<Geographic> moveAll(PositionSeries series) => [
      for (final position in series.positions) move(position),
    ];
    return switch (geometry) {
      Point(:final position) => Point(move(position)),
      LineString(:final chain) => LineString.from(moveAll(chain)),
      Polygon(:final rings) => Polygon.from([
        for (final ring in rings) moveAll(ring),
      ]),
      _ => geometry,
    };
  }

  /// The [MapPlugin]s below the map.
  late final MapPluginRegistry _plugins = MapPluginRegistry(_onPluginsChanged);

  /// The registered plugins in tree order: outer before inner, earlier
  /// before later.
  List<MapPluginEntry> _pluginOrder = const [];

  /// Counts the changes of the plugins, so that [effectiveWidget] combines
  /// them again.
  var _pluginsVersion = 0;

  MapLibreMap? _map;
  MapLibreMap? _mapOf;
  var _mapVersion = -1;

  /// The plugins at the start of the current drag, which get its moves and
  /// its end.
  List<MapPluginEntry> _dragPlugins = const [];

  /// The [Stack] of [MapLibreMap.children], where the plugins are found.
  final GlobalKey _childrenKey = GlobalKey();

  /// The map as the app and the [MapPlugin]s below it declare it together:
  /// the widget with the layers of the plugins after [MapLibreMap.layers],
  /// and callbacks that also call the callbacks of the plugins. A callback
  /// is null while neither the app nor a plugin sets it.
  ///
  /// Platforms read the callbacks from here instead of [widget], and update
  /// what they listen for in [didUpdateCallbacks].
  @protected
  MapLibreMap get effectiveWidget {
    final cached = _map;
    if (cached != null &&
        identical(_mapOf, widget) &&
        _mapVersion == _pluginsVersion) {
      return cached;
    }
    _mapOf = widget;
    _mapVersion = _pluginsVersion;
    return _map = _pluginOrder.isEmpty ? widget : _combine(widget);
  }

  /// Called when the callbacks of [effectiveWidget] may have changed: after
  /// [didUpdateWidget] and when the plugins changed.
  @protected
  void didUpdateCallbacks() {}

  void _onPluginsChanged({required bool structural}) {
    if (!mounted) return;
    final layerFlags = _layerFlags;
    // The walk also finds plugins that moved in the tree. Only plugins that
    // come, go or change what they listen for need the platform and a
    // rebuild.
    _pluginOrder = _pluginsInTreeOrder();
    _pluginsVersion++;
    _annotations.update(effectiveWidget.layers);
    if (structural) didUpdateCallbacks();
    if (structural || _layerFlags != layerFlags) setState(() {});
  }

  /// What the layers need from the gesture detector, which [build] reads.
  (bool, bool, bool) get _layerFlags =>
      (_layersDraggable, _layersClickable, _layersHoverable);

  List<MapPluginEntry> _pluginsInTreeOrder() {
    final registered = _plugins.entries;
    if (registered.isEmpty) return const [];
    final order = <MapPluginEntry>[];
    void visit(Element element) {
      if (element case StatefulElement(state: final MapPluginEntry entry)
          when registered.contains(entry)) {
        order.add(entry);
      }
      element.visitChildren(visit);
    }

    _childrenKey.currentContext?.visitChildElements(visit);
    return order;
  }

  /// The plugins at [point], in the order that Flutter hit-tests them: the
  /// topmost first, inner before outer.
  List<MapPluginEntry> _pluginsAt(Offset point) {
    final box = _childrenKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return const [];
    final result = BoxHitTestResult();
    box.hitTest(result, position: point);
    final registered = _plugins.entries;
    return [
      for (final hit in result.path)
        if (hit.target case RenderMapPlugin(:final entry)
            when registered.contains(entry))
          entry,
    ];
  }

  /// The movements that [MapOptions.movements] and every plugin allow. None
  /// while [MapLibreMap.camera] drives the camera.
  MapMovements get _movements => _pluginOrder.fold(
    widget.camera == null ? options.movements : const MapMovements.none(),
    (movements, entry) => movements.restrictedBy(entry.plugin.movements),
  );

  /// The gestures that [MapOptions.gestures] and every plugin allow.
  MapGestures get _gestures => _pluginOrder.fold(
    options.gestures,
    (gestures, entry) => gestures.restrictedBy(entry.plugin.gestures),
  );

  MapLibreMap _combine(MapLibreMap app) {
    final plugins = _pluginOrder;
    bool any(Object? Function(MapPlugin plugin) pick) =>
        plugins.any((entry) => pick(entry.plugin) != null);
    final drags =
        any((p) => p.onDragStart) ||
        any((p) => p.onDrag) ||
        any((p) => p.onDragEnd);
    final onDragStart = app.onDragStart;
    final onDrag = app.onDrag;
    final onDragEnd = app.onDragEnd;
    return MapLibreMap(
      options: app.options,
      gestureRecognizers: app.gestureRecognizers,
      onMapCreated: app.onMapCreated,
      onStyleLoaded: _toAll(app.onStyleLoaded, (p) => p.onStyleLoaded),
      onClick: _atPointer(app.onClick, (p) => p.onClick),
      onDoubleClick: _inOrderAtPointer(
        app.onDoubleClick,
        (p) => p.onDoubleClick,
      ),
      onSecondaryClick: _atPointer(
        app.onSecondaryClick,
        (p) => p.onSecondaryClick,
      ),
      onLongClick: _atPointer(app.onLongClick, (p) => p.onLongClick),
      onDragStart: drags
          ? (event) {
              final at = _dragPlugins = _pluginsAt(event.screenPoint);
              return _inOrder([
                for (final entry in at)
                  if (entry.plugin.onDragStart case final callback?)
                    _whileRegistered(entry, callback),
                ?onDragStart,
              ], event);
            }
          : onDragStart,
      onDrag: drags
          ? (event) {
              for (final entry in _dragPlugins) {
                _callPlugin(entry, () => entry.plugin.onDrag?.call(event));
              }
              onDrag?.call(event);
            }
          : onDrag,
      onDragEnd: drags
          ? (event) {
              final at = _dragPlugins;
              _dragPlugins = const [];
              for (final entry in at) {
                _callPlugin(entry, () => entry.plugin.onDragEnd?.call(event));
              }
              onDragEnd?.call(event);
            }
          : onDragEnd,
      onPointerMove: _atPointer(app.onPointerMove, (p) => p.onPointerMove),
      onPointerLeave: _toAll(app.onPointerLeave, (p) => p.onPointerLeave),
      onCameraMoveStart: _toAll(
        app.onCameraMoveStart,
        (p) => p.onCameraMoveStart,
      ),
      onCameraMove: _toAll(app.onCameraMove, (p) => p.onCameraMove),
      onCameraMoveEnd: _toAll(app.onCameraMoveEnd, (p) => p.onCameraMoveEnd),
      onIdle: _toAll(app.onIdle, (p) => p.onIdle),
      onError: _toAll(app.onError, (p) => p.onError),
      onStyleImageMissing: _toAll(
        app.onStyleImageMissing,
        (p) => p.onStyleImageMissing,
      ),
      onLoadingStarted: _toAll(app.onLoadingStarted, (p) => p.onLoadingStarted),
      onLoadingFinished: _toAll(
        app.onLoadingFinished,
        (p) => p.onLoadingFinished,
      ),
      onSourceChanged: _toAll(app.onSourceChanged, (p) => p.onSourceChanged),
      onTile: _toAll(app.onTile, (p) => p.onTile),
      onRenderFrame: _toAll(app.onRenderFrame, (p) => p.onRenderFrame),
      onRenderMap: _toAll(app.onRenderMap, (p) => p.onRenderMap),
      onGlyphs: _toAll(app.onGlyphs, (p) => p.onGlyphs),
      onSprite: _toAll(app.onSprite, (p) => p.onSprite),
      onRenderingChanged: _toAll(
        app.onRenderingChanged,
        (p) => p.onRenderingChanged,
      ),
      onResize: _toAll(app.onResize, (p) => p.onResize),
      onContextLost: _toAll(app.onContextLost, (p) => p.onContextLost),
      onContextRestored: _toAll(
        app.onContextRestored,
        (p) => p.onContextRestored,
      ),
      onProjectionChanged: _toAll(
        app.onProjectionChanged,
        (p) => p.onProjectionChanged,
      ),
      layers: [
        ...app.layers,
        for (final entry in plugins) ...entry.plugin.layers,
      ],
      paused: app.paused,
      children: app.children,
    );
  }

  /// Calls the callback that [pick] picks of every plugin, in tree order,
  /// and then [app].
  void Function(T)? _toAll<T>(
    void Function(T)? app,
    void Function(T)? Function(MapPlugin plugin) pick,
  ) {
    if (!_pluginOrder.any((entry) => pick(entry.plugin) != null)) return app;
    return (event) {
      for (final entry in _pluginOrder) {
        _callPlugin(entry, () => pick(entry.plugin)?.call(event));
      }
      app?.call(event);
    };
  }

  /// Calls the callback that [pick] picks of the plugins at the event, and
  /// then [app].
  MapEventCallback<T>? _atPointer<T extends MapEventUserInput>(
    MapEventCallback<T>? app,
    MapEventCallback<T>? Function(MapPlugin plugin) pick,
  ) {
    if (!_pluginOrder.any((entry) => pick(entry.plugin) != null)) return app;
    return (event) {
      for (final entry in _pluginsAt(event.screenPoint)) {
        _callPlugin(entry, () => pick(entry.plugin)?.call(event));
      }
      app?.call(event);
    };
  }

  /// Like [_atPointer], but waits for each callback that returns a
  /// [Future] before it calls the next.
  FutureOr<void> Function(T)? _inOrderAtPointer<T extends MapEventUserInput>(
    FutureOr<void> Function(T)? app,
    FutureOr<void> Function(T)? Function(MapPlugin plugin) pick,
  ) {
    if (!_pluginOrder.any((entry) => pick(entry.plugin) != null)) return app;
    return (event) => _inOrder([
      for (final entry in _pluginsAt(event.screenPoint))
        if (pick(entry.plugin) case final callback?)
          _whileRegistered(entry, callback),
      ?app,
    ], event);
  }

  /// [callback] of the plugin of [entry], which does nothing once the
  /// plugin is gone, for example while an earlier callback was awaited.
  FutureOr<void> Function(T) _whileRegistered<T>(
    MapPluginEntry entry,
    FutureOr<void> Function(T) callback,
  ) =>
      (event) => _plugins.entries.contains(entry) ? callback(event) : null;

  /// Calls [callbacks] one after another, each once the [Future] of the one
  /// before completes. Reports their errors.
  FutureOr<void> _inOrder<T>(
    List<FutureOr<void> Function(T)> callbacks,
    T event, [
    int from = 0,
  ]) {
    for (var i = from; i < callbacks.length; i++) {
      final FutureOr<void> result;
      try {
        result = callbacks[i](event);
      } on Object catch (error, stack) {
        _reportError(error, stack, 'while handling a map event');
        continue;
      }
      if (result is Future<void>) {
        return result
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) =>
                  _reportError(error, stack, 'while handling a map event'),
            )
            .then((_) => mounted ? _inOrder(callbacks, event, i + 1) : null);
      }
    }
  }

  /// Calls [call], a callback of the plugin of [entry] while it is
  /// registered, and reports its errors.
  void _callPlugin(MapPluginEntry entry, void Function() call) {
    if (!_plugins.entries.contains(entry)) return;
    try {
      call();
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while handling a map event of a plugin');
    }
  }

  /// The size of the map's last layout, to report changes with
  /// [MapLibreMap.onResize].
  Size? _size;

  void _onLayout(BoxConstraints constraints) {
    final size = constraints.biggest;
    if (!size.isFinite || size == _size) return;
    final resized = _size != null;
    _size = size;
    if (!resized) return;
    // Layout runs while the tree builds, where listeners must not rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _size == size) {
        effectiveWidget.onResize?.call(MapEventResize(size: size));
      }
    });
  }

  /// The style layers whose callbacks [build] follows.
  StyleLayers? _styleLayers;

  /// The style that [_onStyleChanged] listens to.
  StyleController? _listenedStyle;

  /// Counts the notifications of [style] for [StyleController.of].
  final ValueNotifier<int> _styleRevision = ValueNotifier(0);

  void _listenToStyle() {
    final style = this.style;
    if (identical(style, _listenedStyle)) return;
    _listenedStyle?.removeListener(_onStyleChanged);
    _listenedStyle = style?..addListener(_onStyleChanged);
  }

  void _listenToStyleLayers() {
    final layers = style?.layers;
    if (identical(layers, _styleLayers)) return;
    _styleLayers?.callbacksChanged.removeListener(_onStyleCallbacksChanged);
    _styleLayers = layers;
    layers?.callbacksChanged.addListener(_onStyleCallbacksChanged);
  }

  /// Rebuilds, so that the map listens for taps and the mouse while a style
  /// layer reports them.
  void _onStyleCallbacksChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // The callbacks changed while the tree builds.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// Rebuilds the widgets that depend on [StyleController.of], after the
  /// frame if the style changed while the tree builds.
  void _onStyleChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // The style changed while the tree builds, as annotation layers do.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _styleRevision.value++;
      });
    } else {
      _styleRevision.value++;
    }
  }

  @override
  void dispose() {
    _listenedStyle?.removeListener(_onStyleChanged);
    _styleRevision.dispose();
    _styleLayers?.callbacksChanged.removeListener(_onStyleCallbacksChanged);
    _plugins.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gestureCamera = this.gestureCamera;
    final platformWidget = buildPlatformWidget(context);
    final widget = this.widget;
    final layersDraggable = _layersDraggable;
    // Only the gesture detector reports taps and the mouse to style layers.
    if (gestureCamera != null) _listenToStyleLayers();
    _listenToStyle();
    final clicks =
        gestureCamera != null &&
        (_layersClickable ||
            _styleLayersClickable ||
            effectiveWidget.onClick != null);
    // Hovered features are left once the last hoverable layer is gone.
    final hovers =
        gestureCamera != null &&
        (_layersHoverable ||
            _styleLayersHoverable ||
            _hovered.isNotEmpty ||
            _hoveredStyle.isNotEmpty);
    return LayoutBuilder(
      builder: (context, constraints) {
        _onLayout(constraints);
        return Stack(
          children: [
            if (gestureCamera == null)
              platformWidget
            else
              MapGestureDetector(
                movements: _movements,
                gestures: _gestures,
                camera: gestureCamera,
                toLngLat: (point) => isInitialized ? toLngLat(point) : null,
                onClick: clicks ? _onClick : null,
                onDoubleClick: effectiveWidget.onDoubleClick,
                onSecondaryClick: effectiveWidget.onSecondaryClick,
                onLongClick: effectiveWidget.onLongClick,
                onDragStart:
                    layersDraggable || effectiveWidget.onDragStart != null
                    ? _onDragStart
                    : null,
                onDrag: layersDraggable || effectiveWidget.onDrag != null
                    ? _onDrag
                    : null,
                onDragEnd: layersDraggable || effectiveWidget.onDragEnd != null
                    ? _onDragEnd
                    : null,
                onPointerMove: hovers || effectiveWidget.onPointerMove != null
                    ? _onPointerMove
                    : null,
                onPointerLeave: hovers || effectiveWidget.onPointerLeave != null
                    ? _onPointerLeave
                    : null,
                child: platformWidget,
              ),
            // Only the model rebuilds when the style notifies.
            ValueListenableBuilder(
              valueListenable: _styleRevision,
              builder: (context, styleRevision, children) =>
                  MapLibreInheritedModel(
                    mapController: this,
                    cameraPosition: camera,
                    options: options,
                    style: style,
                    styleRevision: styleRevision,
                    renderingPaused: _renderingPaused,
                    plugins: _plugins,
                    child: children!,
                  ),
              child: isInitialized
                  ? Stack(key: _childrenKey, children: widget.children)
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  /// Build the platform specific widget.
  Widget buildPlatformWidget(BuildContext context);
}

/// Logical pixels of the square around a drag's start that it grabs a
/// feature of a draggable layer in, so that small features can be grabbed by
/// touch.
const _grabSize = 24.0;

/// What a query found.
class _Hits {
  const _Hits({this.layers = const [], this.styleLayers = const []});

  /// The features of [MapLibreMap.layers].
  final List<_LayerHit> layers;

  /// The features of style layers, topmost first.
  final List<RenderedFeature> styleLayers;
}

/// A feature of [MapLibreMap.layers] that a query found.
class _LayerHit {
  const _LayerHit(
    this.entry,
    this.drawIndex,
    this.featureIndex,
    this.feature,
    this.geometry,
  );

  /// The layer, which keeps its identity while the list changes.
  final AnnotationEntry entry;

  /// The position of the layer's style layer, from the bottom.
  final int drawIndex;

  final int featureIndex;
  final Feature feature;

  /// The geometry of the feature, where a drag starts.
  final Geometry geometry;
}

/// A feature of [MapLibreMap.layers] that a drag moves.
class _LayerDrag {
  _LayerDrag(this.hit, this.start);

  /// The dragged feature, with its geometry where the drag started.
  final _LayerHit hit;

  /// Where the drag started, in logical pixels of the map.
  final Offset start;
}

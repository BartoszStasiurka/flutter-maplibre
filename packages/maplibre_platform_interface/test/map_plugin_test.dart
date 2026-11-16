import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';
import 'package:maplibre_platform_interface/src/layer/annotation_manager.dart';
import 'package:maplibre_platform_interface/src/widget/inherited_model.dart';
import 'package:maplibre_platform_interface/src/widget/map_plugin.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _size = Size(800, 600);
const _center = Offset(400, 300);

/// A plate carrée world 1000 px wide, centered on the screen.
Geographic _toLngLat(Offset point) => Geographic(
  lon: (point.dx - _center.dx) * 360 / 1000,
  lat: (_center.dy - point.dy) * 360 / 1000,
);

Offset _toScreen(Geographic point) => Offset(
  _center.dx + point.lon * 1000 / 360,
  _center.dy - point.lat * 1000 / 360,
);

class _Camera implements GestureCameraSink {
  Offset panned = Offset.zero;
  double zoomed = 0;

  @override
  void gestureStart() {}

  @override
  void gestureUpdate(GestureCameraUpdate update) {
    if (update.pans) panned += update.panTo! - update.panFrom!;
  }

  @override
  void gestureEnd({GestureVelocity velocity = GestureVelocity.zero}) {}

  @override
  void zoomBy(
    double levels,
    Offset around, {
    Duration duration = Duration.zero,
  }) => zoomed += levels;
}

class _State extends MapLibreMapState {
  _State(this.sink);

  final _Camera sink;

  /// Counts the calls of [didUpdateCallbacks].
  int callbackUpdates = 0;

  @override
  StyleController? get style => null;

  @override
  void initState() {
    super.initState();
    isInitialized = true;
    camera = _camera(0);
  }

  /// Moves the camera, like a platform does in every frame of a move.
  void showCamera(double zoom) => setState(() => camera = _camera(zoom));

  static CameraPosition _camera(double zoom) => CameraPosition(
    center: const Geographic(lon: 0, lat: 0),
    zoom: zoom,
    bearing: 0,
    pitch: 0,
  );

  @override
  void didUpdateCallbacks() => callbackUpdates++;

  /// The map with the plugins, for the tests.
  MapLibreMap get combined => effectiveWidget;

  @override
  GestureCameraSink get gestureCamera => sink;

  @override
  Geographic toLngLat(Offset screenLocation) => _toLngLat(screenLocation);

  @override
  Offset toScreenLocation(Geographic lngLat) => _toScreen(lngLat);

  @override
  Future<List<RenderedFeature>> queryRenderedFeatures(
    QueryGeometry geometry, {
    List<String>? layerIds,
    Expression<bool>? filter,
  }) async {
    final rect = switch (geometry) {
      QueryGeometryRect(:final rect) => rect,
      QueryGeometryPoint(:final point) => Rect.fromCenter(
        center: point,
        width: 2,
        height: 2,
      ),
      _ => throw UnimplementedError(),
    };
    final features = <RenderedFeature>[];
    // Without a style, the layers are drawn in the order of the list.
    for (final layer in effectiveWidget.layers.reversed) {
      final layerId = annotationLayerId(layer)!;
      if (!layerIds!.contains(layerId)) continue;
      for (final (index, feature) in layer.list.indexed) {
        if (feature.geometry case Point(:final position)
            when rect.contains(_toScreen(Geographic.from(position)))) {
          features.add(
            RenderedFeature(
              id: null,
              properties: {AnnotationManager.featureIndexProperty: index},
              layerId: layerId,
            ),
          );
        }
      }
    }
    return features;
  }

  @override
  Widget buildPlatformWidget(BuildContext context) => const SizedBox.expand();

  // The other controller calls are not under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform extends MapLibrePlatform with MockPlatformInterfaceMixin {
  final camera = _Camera();
  late _State state;

  @override
  MapLibreMapState createWidgetState() => state = _State(camera);
}

class _PointLayer extends Layer<Feature<Point>> {
  const _PointLayer({required super.list, super.onClick});

  @override
  StyleLayer createStyleLayer({required String id, required String sourceId}) =>
      CircleStyleLayer(id: id, sourceId: sourceId);
}

Feature<Point> _point(double lon, double lat) => Feature(
  geometry: Point(Geographic(lon: lon, lat: lat)),
);

/// Counts its builds.
class _BuildCounter extends StatelessWidget {
  const _BuildCounter(this.read, this.builds);

  final void Function(BuildContext context) read;
  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    read(context);
    builds.add(1);
    return const SizedBox.shrink();
  }
}

void main() {
  late _Platform platform;
  late List<String> calls;

  setUp(() {
    platform = _Platform();
    MapLibrePlatform.instance = platform;
    calls = [];
  });

  Future<void> pumpMap(
    WidgetTester tester, {
    List<Widget> children = const [],
    List<Layer> layers = const [],
    MapOptions options = const MapOptions(),
    MapEventCallback<MapEventClick>? onClick,
    FutureOr<void> Function(MapEventDoubleClick)? onDoubleClick,
    FutureOr<void> Function(MapEventDragStart)? onDragStart,
    MapEventCallback<MapEventIdle>? onIdle,
  }) async {
    tester.view
      ..physicalSize = _size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MapLibreMap(
          options: options,
          layers: layers,
          onClick: onClick,
          onDoubleClick: onDoubleClick,
          onDragStart: onDragStart,
          onIdle: onIdle,
          children: children,
        ),
      ),
    );
    // The plugins register after the first frame.
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    // A tap waits whether a second one follows.
    await tester.pump(kDoubleTapTimeout * 2);
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
    final gesture = await tester.startGesture(from);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(by / 10);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('events', () {
    testWidgets('a tap goes to the plugins, the topmost first, then the map', (
      tester,
    ) async {
      MapEventClick? seen;
      await pumpMap(
        tester,
        onClick: (event) {
          calls.add('map');
          expect(event, same(seen));
        },
        children: [
          MapPlugin(
            onClick: (event) {
              calls.add('outer');
              seen ??= event;
            },
            child: MapPlugin(onClick: (event) => calls.add('inner')),
          ),
          MapPlugin(onClick: (event) => calls.add('top')),
        ],
      );
      await tap(tester, const Offset(100, 100));
      expect(calls, ['top', 'inner', 'outer', 'map']);
    });

    testWidgets('a positioned plugin only gets the taps inside it', (
      tester,
    ) async {
      await pumpMap(
        tester,
        onClick: (_) => calls.add('map'),
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 100,
            height: 100,
            child: MapPlugin(onClick: (_) => calls.add('plugin')),
          ),
        ],
      );
      await tap(tester, const Offset(50, 50));
      await tap(tester, const Offset(300, 300));
      expect(calls, ['plugin', 'map', 'map']);
    });

    testWidgets('a plugin lets the map get the pointers its child misses', (
      tester,
    ) async {
      await pumpMap(
        tester,
        children: [
          MapPlugin(
            child: SizedBox.square(
              dimension: 100,
              child: GestureDetector(
                onTap: () => calls.add('child'),
                child: const ColoredBox(color: Color(0xFF000000)),
              ),
            ),
          ),
        ],
      );
      await tap(tester, const Offset(50, 50));
      expect(calls, ['child']);
      await drag(tester, const Offset(300, 300), const Offset(100, 0));
      expect(platform.camera.panned.dx, greaterThan(50));
    });

    testWidgets('a plugin is heard while the app sets no callback', (
      tester,
    ) async {
      await pumpMap(
        tester,
        children: [MapPlugin(onClick: (_) => calls.add('plugin'))],
      );
      await tap(tester, const Offset(100, 100));
      expect(calls, ['plugin']);
    });

    testWidgets('preventDefault of a plugin keeps the map from zooming', (
      tester,
    ) async {
      MapEventDoubleClick? seen;
      await pumpMap(
        tester,
        onDoubleClick: (event) => seen = event,
        children: [
          MapPlugin(
            onDoubleClick: (event) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              event.preventDefault();
            },
          ),
        ],
      );
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(100, 100));
      await tester.pumpAndSettle();
      expect(seen?.defaultPrevented, isTrue);
      expect(platform.camera.zoomed, 0);
    });

    testWidgets('a drag goes to the plugins at its start until it ends', (
      tester,
    ) async {
      await pumpMap(
        tester,
        onDragStart: (event) {
          calls.add('map start ${event.defaultPrevented}');
        },
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 100,
            height: 100,
            child: MapPlugin(
              onDragStart: (event) {
                calls.add('start');
                event.preventDefault();
              },
              onDrag: (_) => calls.add('drag'),
              onDragEnd: (_) => calls.add('end'),
            ),
          ),
        ],
      );
      // Ends far outside the plugin.
      await drag(tester, const Offset(50, 50), const Offset(400, 0));
      expect(calls.first, 'start');
      expect(calls[1], 'map start true');
      expect(calls, contains('drag'));
      expect(calls.last, 'end');
      expect(platform.camera.panned, Offset.zero);
      calls.clear();
      await drag(tester, const Offset(300, 300), const Offset(100, 0));
      expect(calls, ['map start false']);
      expect(platform.camera.panned.dx, greaterThan(50));
    });

    testWidgets('other events go to every plugin in tree order, then the map', (
      tester,
    ) async {
      await pumpMap(
        tester,
        onIdle: (_) => calls.add('map'),
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 10,
            height: 10,
            child: MapPlugin(onIdle: (_) => calls.add('first')),
          ),
          MapPlugin(onIdle: (_) => calls.add('second')),
        ],
      );
      platform.state.combined.onIdle!(const MapEventIdle());
      expect(calls, ['first', 'second', 'map']);
    });

    testWidgets('an error of a plugin does not stop the others', (
      tester,
    ) async {
      await pumpMap(
        tester,
        onClick: (_) => calls.add('map'),
        children: [MapPlugin(onClick: (_) => throw StateError('plugin'))],
      );
      await tap(tester, const Offset(100, 100));
      expect(tester.takeException(), isA<StateError>());
      expect(calls, ['map']);
    });

    testWidgets('the platform hears when the callbacks of plugins change', (
      tester,
    ) async {
      await pumpMap(tester);
      final before = platform.state.callbackUpdates;
      expect(platform.state.combined.onIdle, isNull);
      await pumpMap(tester, children: [MapPlugin(onIdle: (_) {})]);
      expect(platform.state.callbackUpdates, greaterThan(before));
      expect(platform.state.combined.onIdle, isNotNull);
      await pumpMap(tester);
      expect(platform.state.combined.onIdle, isNull);
    });
  });

  group('layers', () {
    testWidgets('come after the layers of the map, in tree order', (
      tester,
    ) async {
      final app = _PointLayer(list: [_point(0, 0)]);
      final first = _PointLayer(list: [_point(10, 0)]);
      final second = _PointLayer(list: [_point(20, 0)]);
      await pumpMap(
        tester,
        layers: [app],
        children: [
          MapPlugin(layers: [first]),
          MapPlugin(layers: [second]),
        ],
      );
      expect(platform.state.combined.layers, [app, first, second]);
      expect(platform.state.annotationLayerId(second), isNotNull);
      await pumpMap(tester, layers: [app]);
      expect(platform.state.combined.layers, [app]);
      expect(platform.state.annotationLayerId(second), isNull);
    });

    testWidgets('follow keyed plugins that swap places', (tester) async {
      final first = _PointLayer(list: [_point(10, 0)]);
      final second = _PointLayer(list: [_point(20, 0)]);
      final a = MapPlugin(key: const ValueKey('a'), layers: [first]);
      final b = MapPlugin(key: const ValueKey('b'), layers: [second]);
      await pumpMap(tester, children: [a, b]);
      expect(platform.state.combined.layers, [first, second]);
      // The same widgets, so no plugin changes itself.
      await pumpMap(tester, children: [b, a]);
      await tester.pump();
      expect(platform.state.combined.layers, [second, first]);
    });

    testWidgets('report taps like the layers of the map', (tester) async {
      await pumpMap(
        tester,
        children: [
          MapPlugin(
            layers: [
              _PointLayer(
                list: [_point(0, 0)],
                onClick: (event) => calls.add('feature ${event.index}'),
              ),
            ],
          ),
        ],
      );
      await tap(tester, _center);
      expect(calls, ['feature 0']);
    });
  });

  group('movements', () {
    testWidgets('a plugin can only turn movements off', (tester) async {
      await pumpMap(
        tester,
        children: [const MapPlugin(movements: MapMovements(pan: false))],
      );
      await drag(tester, const Offset(300, 300), const Offset(100, 0));
      expect(platform.camera.panned, Offset.zero);
      await pumpMap(tester);
      await drag(tester, const Offset(300, 300), const Offset(100, 0));
      expect(platform.camera.panned.dx, greaterThan(50));
    });

    testWidgets('a plugin can only turn gestures off', (tester) async {
      await pumpMap(
        tester,
        options: const MapOptions(gestures: MapGestures.none(doubleTap: true)),
        children: [const MapPlugin(gestures: MapGestures(doubleTap: false))],
      );
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(100, 100));
      await tester.pumpAndSettle();
      expect(platform.camera.zoomed, 0);
      await drag(tester, const Offset(300, 300), const Offset(100, 0));
      expect(platform.camera.panned, Offset.zero);
    });
  });

  test('the callback list of a plugin covers every callback', () {
    void onEvent(Object? _) {}
    final plugin = MapPlugin(
      onStyleLoaded: onEvent,
      onClick: onEvent,
      onDoubleClick: onEvent,
      onSecondaryClick: onEvent,
      onLongClick: onEvent,
      onDragStart: onEvent,
      onDrag: onEvent,
      onDragEnd: onEvent,
      onPointerMove: onEvent,
      onPointerLeave: onEvent,
      onCameraMoveStart: onEvent,
      onCameraMove: onEvent,
      onCameraMoveEnd: onEvent,
      onIdle: onEvent,
      onError: onEvent,
      onStyleImageMissing: onEvent,
      onLoadingStarted: onEvent,
      onLoadingFinished: onEvent,
      onSourceChanged: onEvent,
      onTile: onEvent,
      onRenderFrame: onEvent,
      onRenderMap: onEvent,
      onGlyphs: onEvent,
      onSprite: onEvent,
      onRenderingChanged: onEvent,
      onResize: onEvent,
      onContextLost: onEvent,
      onContextRestored: onEvent,
      onProjectionChanged: onEvent,
    );
    // A callback missing in the list wouldn't make the map listen for it.
    expect(mapPluginCallbacksSet(plugin), everyElement(isTrue));
    expect(mapPluginCallbacksSet(const MapPlugin()), everyElement(isFalse));
  });

  group('rebuilds', () {
    testWidgets('only widgets that read the camera rebuild when it moves', (
      tester,
    ) async {
      final controllerBuilds = <int>[];
      final cameraBuilds = <int>[];
      final optionsBuilds = <int>[];
      await pumpMap(
        tester,
        children: [
          _BuildCounter(MapController.of, controllerBuilds),
          _BuildCounter(CameraPosition.of, cameraBuilds),
          _BuildCounter(MapOptions.of, optionsBuilds),
        ],
      );
      controllerBuilds.clear();
      cameraBuilds.clear();
      optionsBuilds.clear();
      platform.state.showCamera(3);
      await tester.pump();
      platform.state.showCamera(4);
      await tester.pump();
      expect(controllerBuilds, isEmpty);
      expect(optionsBuilds, isEmpty);
      expect(cameraBuilds, hasLength(2));
    });

    testWidgets('widgets rebuild for the aspect they read', (tester) async {
      final controllerBuilds = <int>[];
      final styleBuilds = <int>[];
      final controller = _State(_Camera());
      // The same children, which only rebuild when the model notifies them.
      final children = Column(
        children: [
          _BuildCounter(MapController.of, controllerBuilds),
          _BuildCounter(StyleController.maybeOf, styleBuilds),
        ],
      );
      Widget model({int styleRevision = 0, bool renderingPaused = false}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: MapLibreInheritedModel(
              mapController: controller,
              cameraPosition: null,
              styleRevision: styleRevision,
              renderingPaused: renderingPaused,
              child: children,
            ),
          );
      await tester.pumpWidget(model());
      controllerBuilds.clear();
      styleBuilds.clear();
      await tester.pumpWidget(model());
      expect(controllerBuilds, isEmpty);
      expect(styleBuilds, isEmpty);
      await tester.pumpWidget(model(styleRevision: 1));
      expect(controllerBuilds, isEmpty);
      expect(styleBuilds, hasLength(1));
      await tester.pumpWidget(model(styleRevision: 1, renderingPaused: true));
      expect(controllerBuilds, hasLength(1));
      expect(styleBuilds, hasLength(1));
    });

    testWidgets('a plugin that rebuilds unchanged leaves the map alone', (
      tester,
    ) async {
      final key = GlobalKey<_RebuildingState>();
      final layer = _PointLayer(list: [_point(0, 0)]);
      await pumpMap(
        tester,
        children: [
          _Rebuilding(key: key, layers: [layer]),
        ],
      );
      final updates = platform.state.callbackUpdates;
      final combined = platform.state.combined;
      key.currentState!.rebuild();
      await tester.pumpAndSettle();
      expect(platform.state.callbackUpdates, updates);
      expect(platform.state.combined, same(combined));
      // New layers update the map without the platform.
      key.currentState!.rebuild(
        layers: [
          _PointLayer(list: [_point(1, 0)]),
        ],
      );
      await tester.pumpAndSettle();
      expect(platform.state.callbackUpdates, updates);
      expect(
        platform.state.combined.layers.single.list.single,
        isNot(same(layer.list.single)),
      );
      // A new callback reaches the platform.
      key.currentState!.rebuild(onIdle: (_) {});
      await tester.pumpAndSettle();
      expect(platform.state.callbackUpdates, greaterThan(updates));
      expect(platform.state.combined.onIdle, isNotNull);
    });
  });

  group('combined widget', () {
    testWidgets('keeps every parameter of the app with a plugin present', (
      tester,
    ) async {
      void onEvent(Object? _) {}
      const options = MapOptions(minZoom: 3);
      final layers = [
        _PointLayer(list: [_point(0, 0)]),
      ];
      final children = [const MapPlugin()];
      final recognizers = <Factory<OneSequenceGestureRecognizer>>{};
      final app = MapLibreMap(
        options: options,
        gestureRecognizers: recognizers,
        onMapCreated: onEvent,
        onStyleLoaded: onEvent,
        onClick: onEvent,
        onDoubleClick: onEvent,
        onSecondaryClick: onEvent,
        onLongClick: onEvent,
        onDragStart: onEvent,
        onDrag: onEvent,
        onDragEnd: onEvent,
        onPointerMove: onEvent,
        onPointerLeave: onEvent,
        onCameraMoveStart: onEvent,
        onCameraMove: onEvent,
        onCameraMoveEnd: onEvent,
        onIdle: onEvent,
        onError: onEvent,
        onStyleImageMissing: onEvent,
        onLoadingStarted: onEvent,
        onLoadingFinished: onEvent,
        onSourceChanged: onEvent,
        onTile: onEvent,
        onRenderFrame: onEvent,
        onRenderMap: onEvent,
        onGlyphs: onEvent,
        onSprite: onEvent,
        onRenderingChanged: onEvent,
        onResize: onEvent,
        onContextLost: onEvent,
        onContextRestored: onEvent,
        onProjectionChanged: onEvent,
        layers: layers,
        paused: true,
        children: children,
      );
      tester.view
        ..physicalSize = _size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: app),
      );
      await tester.pumpAndSettle();
      final combined = platform.state.combined;
      expect(combined, isNot(same(app)));
      expect(combined.options, same(options));
      expect(combined.gestureRecognizers, same(recognizers));
      expect(combined.layers, layers);
      expect(combined.paused, isTrue);
      expect(combined.children, same(children));
      // No plugin listens, so every callback is the app's own.
      final callbacks = <Object? Function(MapLibreMap)>[
        (m) => m.onMapCreated,
        (m) => m.onStyleLoaded,
        (m) => m.onClick,
        (m) => m.onDoubleClick,
        (m) => m.onSecondaryClick,
        (m) => m.onLongClick,
        (m) => m.onPointerMove,
        (m) => m.onPointerLeave,
        (m) => m.onCameraMoveStart,
        (m) => m.onCameraMove,
        (m) => m.onCameraMoveEnd,
        (m) => m.onIdle,
        (m) => m.onError,
        (m) => m.onStyleImageMissing,
        (m) => m.onLoadingStarted,
        (m) => m.onLoadingFinished,
        (m) => m.onSourceChanged,
        (m) => m.onTile,
        (m) => m.onRenderFrame,
        (m) => m.onRenderMap,
        (m) => m.onGlyphs,
        (m) => m.onSprite,
        (m) => m.onRenderingChanged,
        (m) => m.onResize,
        (m) => m.onContextLost,
        (m) => m.onContextRestored,
        (m) => m.onProjectionChanged,
      ];
      for (final (index, callback) in callbacks.indexed) {
        expect(callback(combined), same(callback(app)), reason: '#$index');
      }
      expect(combined.onDragStart, same(app.onDragStart));
      expect(combined.onDrag, same(app.onDrag));
      expect(combined.onDragEnd, same(app.onDragEnd));
    });
  });
}

/// A plugin whose parameters a test changes.
class _Rebuilding extends StatefulWidget {
  const _Rebuilding({required this.layers, super.key});

  final List<Layer> layers;

  @override
  State<_Rebuilding> createState() => _RebuildingState();
}

class _RebuildingState extends State<_Rebuilding> {
  late List<Layer> _layers = widget.layers;
  MapEventCallback<MapEventIdle>? _onIdle;

  void rebuild({List<Layer>? layers, MapEventCallback<MapEventIdle>? onIdle}) =>
      setState(() {
        _layers = layers ?? _layers;
        _onIdle = onIdle ?? _onIdle;
      });

  @override
  Widget build(BuildContext context) =>
      MapPlugin(layers: _layers, onIdle: _onIdle);
}

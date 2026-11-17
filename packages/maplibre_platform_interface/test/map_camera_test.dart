import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Sink implements GestureCameraSink {
  Offset panned = Offset.zero;

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
  }) {}
}

/// Records the cameras that the shared map state hands to the platform.
class _State extends MapLibreMapState {
  _State(this.sink);

  final _Sink sink;
  final applied = <CameraPosition>[];

  /// What the platform takes as the initial camera when the map is created.
  CameraUpdate? created;

  @override
  void initState() {
    super.initState();
    isInitialized = true;
    created = initialCamera;
  }

  @override
  void applyCamera(CameraPosition camera) => applied.add(camera);

  @override
  StyleController? get style => null;

  @override
  GestureCameraSink get gestureCamera => sink;

  @override
  Widget buildPlatformWidget(BuildContext context) => const SizedBox.expand();

  // The controller calls are not under test.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlatform extends MapLibrePlatform with MockPlatformInterfaceMixin {
  final sink = _Sink();
  late _State state;

  @override
  MapLibreMapState createWidgetState() => state = _State(sink);
}

CameraPosition _camera(double lon) => CameraPosition(
  center: Geographic(lon: lon, lat: 10),
  zoom: 4,
  bearing: 0,
  pitch: 0,
);

void main() {
  late _FakePlatform platform;

  setUp(() => MapLibrePlatform.instance = platform = _FakePlatform());

  Future<void> pumpMap(
    WidgetTester tester, {
    CameraPosition? camera,
    MapOptions options = const MapOptions(),
    List<Widget> children = const [],
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: camera == null
          ? MapLibreMap(options: options, children: children)
          : MapLibreMap.withCamera(
              camera: camera,
              options: options,
              children: children,
            ),
    ),
  );

  Future<void> drag(WidgetTester tester) async {
    final gesture = await tester.startGesture(const Offset(300, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the map starts at the camera instead of initCamera', (
    tester,
  ) async {
    await pumpMap(
      tester,
      camera: _camera(1),
      options: MapOptions(initCamera: _camera(2).toCameraUpdate()),
    );
    final created = platform.state.created! as CameraUpdatePosition;
    expect(created.center, _camera(1).center);
    expect(created.zoom, 4);
    expect(platform.state.applied, isEmpty);
  });

  testWidgets('without a camera, the map starts at initCamera', (tester) async {
    final initCamera = _camera(2).toCameraUpdate();
    await pumpMap(tester, options: MapOptions(initCamera: initCamera));
    expect(platform.state.created, same(initCamera));
  });

  testWidgets('each new camera is applied once, while the map builds', (
    tester,
  ) async {
    await pumpMap(tester, camera: _camera(1));
    await pumpMap(tester, camera: _camera(1));
    expect(platform.state.applied, isEmpty);
    await pumpMap(tester, camera: _camera(2));
    await pumpMap(tester, camera: _camera(2));
    await pumpMap(tester, camera: _camera(3));
    expect(platform.state.applied, [_camera(2), _camera(3)]);
  });

  testWidgets('a map without a camera keeps applying none', (tester) async {
    await pumpMap(tester);
    await pumpMap(tester, options: const MapOptions(minZoom: 2));
    expect(platform.state.applied, isEmpty);
  });

  testWidgets('gestures move the camera only while none is set', (
    tester,
  ) async {
    await pumpMap(tester, camera: _camera(1));
    await drag(tester);
    expect(platform.sink.panned, Offset.zero);

    await pumpMap(tester);
    await drag(tester);
    expect(platform.sink.panned.dx, greaterThan(50));
  });

  testWidgets('plugins keep the camera of the map', (tester) async {
    await pumpMap(tester, camera: _camera(1), children: [const MapPlugin()]);
    await pumpMap(tester, camera: _camera(2), children: [const MapPlugin()]);
    expect(platform.state.applied, [_camera(2)]);
    await drag(tester);
    expect(platform.sink.panned, Offset.zero);
  });

  testWidgets('a live map switches to the camera of withCamera', (
    tester,
  ) async {
    await pumpMap(tester);
    await pumpMap(tester, camera: _camera(5));
    expect(platform.state.applied, [_camera(5)]);
    await drag(tester);
    expect(platform.sink.panned, Offset.zero);
  });
}

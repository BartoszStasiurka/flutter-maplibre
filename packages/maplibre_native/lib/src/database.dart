import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:maplibre_native/src/android/android_plugin.dart';
import 'package:maplibre_native/src/extensions.dart';
import 'package:maplibre_native_ffi/maplibre_native_ffi.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart'
    show MapLibreNetwork, RequestHeaders;
import 'package:path_provider/path_provider.dart';

Future<String>? _databasePath;

/// The database that every map caches its resources in, and that the offline
/// manager keeps its regions in: `maplibre_native.db` in the app's support
/// directory.
Future<String> databasePath() async {
  final path = _databasePath ??= _createDatabasePath();
  try {
    return await path;
  } on Object {
    _databasePath = null;
    rethrow;
  }
}

Future<String> _createDatabasePath() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return '${directory.path}${Platform.pathSeparator}maplibre_native.db';
}

/// Creates a runtime on the shared database. Runtimes on one database share
/// its resource cache and offline regions.
///
/// The runtime requests its resources with the settings of
/// [MapLibreNetwork], also after they change.
Future<RuntimeHandle> createRuntime() async {
  final path = await databasePath();
  // Android needs the C library initialized before its first use.
  if (Platform.isAndroid) AndroidPlugin.initialize();
  _applyNetworkStatus();
  final runtime = RuntimeHandle.create(
    options: RuntimeOptions(cachePath: path),
  );
  // Known before the first settings are applied, so a change meanwhile
  // reaches it too. Its commands run in order, so the latest settings win.
  _runtimes
    ..removeWhere((runtime) => runtime.isClosed)
    ..add(runtime);
  if (!_listensToNetwork) {
    MapLibreNetwork.changes.addListener(_onNetworkChanged);
    _listensToNetwork = true;
    _appliedHeaders = MapLibreNetwork.requestHeaders;
    _appliedTransform = MapLibreNetwork.urlTransform != null;
  }
  try {
    // A new runtime has no headers and no transform, so it only needs the
    // ones that are set.
    await _applyNetwork(
      runtime,
      headers: MapLibreNetwork.requestHeaders.any(
        (entry) => entry.kinds?.isEmpty != true,
      ),
      transform: MapLibreNetwork.urlTransform != null,
    );
  } on Object {
    _runtimes.remove(runtime);
    await runtime.release();
    rethrow;
  }
  return runtime;
}

/// The runtimes that [createRuntime] created, to apply [MapLibreNetwork]
/// changes to. Closed ones are dropped at the next change or creation.
final _runtimes = <RuntimeHandle>{};
var _listensToNetwork = false;

/// The headers, and whether there is a URL transform, as the runtimes have
/// them, so that a change of another setting doesn't send them again.
List<RequestHeaders> _appliedHeaders = const [];
var _appliedTransform = false;

void _onNetworkChanged() {
  // The C library is initialized, as a runtime was created before.
  _applyNetworkStatus();
  // The setter replaces the list on each change.
  final headers = !identical(MapLibreNetwork.requestHeaders, _appliedHeaders);
  final transform = (MapLibreNetwork.urlTransform != null) != _appliedTransform;
  _appliedHeaders = MapLibreNetwork.requestHeaders;
  _appliedTransform = MapLibreNetwork.urlTransform != null;
  if (!headers && !transform) return;
  _runtimes.removeWhere((runtime) => runtime.isClosed);
  for (final runtime in _runtimes) {
    unawaited(
      _applyNetwork(runtime, headers: headers, transform: transform).catchError(
        (Object error, StackTrace stack) {
          // A runtime that closed meanwhile needs no settings.
          if (runtime.isClosed) return;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'maplibre',
              context: ErrorDescription('while applying the network settings'),
            ),
          );
        },
      ),
    );
  }
}

/// The network status of the C library as this isolate last saw or set it,
/// or null before the isolate first used the library.
bool? _offline;

/// Sets [MapLibreNetwork.offline] as the network status of the C library,
/// which applies to every runtime of the process.
///
/// The status outlives the isolate: another engine, or this one before a hot
/// restart, may have set it. So the first call reads it, and if the process
/// is offline, sets [MapLibreNetwork.offline] to match. Later calls set only
/// changes.
void _applyNetworkStatus() {
  if (_offline == null) {
    final offline = getNetworkStatus() == NetworkStatus.offline;
    _offline = offline;
    if (offline && !MapLibreNetwork.offline) {
      // The first call comes before the listener, so this sets nothing.
      MapLibreNetwork.offline = true;
      return;
    }
  }
  final offline = MapLibreNetwork.offline;
  if (offline == _offline) return;
  setNetworkStatus(offline ? NetworkStatus.offline : NetworkStatus.online);
  _offline = offline;
}

/// Sets the [headers] and the URL [transform] of [MapLibreNetwork] on
/// [runtime], or clears the ones that are not set.
Future<void> _applyNetwork(
  RuntimeHandle runtime, {
  required bool headers,
  required bool transform,
}) async {
  if (headers) {
    // Entries without kinds match nothing, and an empty rule table is
    // invalid.
    final rules = [
      for (final entry in MapLibreNetwork.requestHeaders)
        if (entry.kinds?.isEmpty != true) entry.toMln(),
    ];
    if (rules.isNotEmpty) {
      await runtime.setHttpHeaderTransform(HttpHeaderTransform(rules: rules));
    } else {
      await runtime.clearHttpHeaderTransform();
    }
  }
  // The transform reads MapLibreNetwork.urlTransform for each request, so
  // only whether there is one matters. It waits for Dart on every request,
  // so it is only set while there is one.
  if (transform) {
    if (MapLibreNetwork.urlTransform != null) {
      await runtime.setResourceTransform(
        ResourceTransform(callback: _transformResource),
      );
    } else {
      await runtime.clearResourceTransform();
    }
  }
}

void _transformResource(
  ResourceKind kind,
  String url,
  ResourceTransformRequestHandle request,
) {
  final transformed = MapLibreNetwork.transformUrl(
    url,
    kind.toMapResourceKind(),
  );
  try {
    // An empty URL would fail the request, so it keeps its own instead.
    request.complete(transformed.isEmpty ? url : transformed);
  } on Object catch (error, stack) {
    // Native rejected the URL, which fails the request.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'maplibre',
        context: ErrorDescription('while transforming the URL $url'),
      ),
    );
  }
}

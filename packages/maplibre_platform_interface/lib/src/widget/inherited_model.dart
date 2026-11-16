import 'package:flutter/widgets.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';
import 'package:maplibre_platform_interface/src/widget/map_plugin_registry.dart';

/// What a widget below a [MapLibreMap] depends on, so that it only rebuilds
/// when that changes.
enum MapLibreAspect {
  /// The [MapController], its [MapOptions], which [StyleController] it has
  /// and whether its rendering is paused.
  controller,

  /// The [CameraPosition], which changes with every frame of a camera move.
  camera,

  /// The [StyleController] and its layers, sources and attributions.
  style,
}

/// The [InheritedModel] makes it possible to call `MapController.of(context)`.
///
/// https://api.flutter.dev/flutter/widgets/InheritedModel-class.html
class MapLibreInheritedModel extends InheritedModel<MapLibreAspect> {
  /// Default constructor
  const MapLibreInheritedModel({
    required super.child,
    required this.mapController,
    required this.cameraPosition,
    this.options,
    this.style,
    this.styleRevision = 0,
    this.renderingPaused = false,
    this.plugins,
    super.key,
  });

  /// [MapController] instance.
  final MapController mapController;

  /// [CameraPosition] instance.
  final CameraPosition? cameraPosition;

  /// The [MapController.options] when this model was built, so that the
  /// widgets that depend on the controller rebuild when they change.
  final MapOptions? options;

  /// The [MapController.style] when this model was built, so that the
  /// widgets that depend on the controller rebuild when it changes.
  final StyleController? style;

  /// Counts the notifications of [style], so that the widgets that depend on
  /// the style rebuild when its layers, sources or attributions change.
  final int styleRevision;

  /// [MapController.isRenderingPaused] when this model was built.
  final bool renderingPaused;

  /// The [MapPlugin]s below the map register here.
  final MapPluginRegistry? plugins;

  static MapLibreInheritedModel? _of(
    BuildContext context,
    MapLibreAspect aspect,
  ) => InheritedModel.inheritFrom<MapLibreInheritedModel>(
    context,
    aspect: aspect,
  );

  /// Get the in the widget tree injected [MapController]. The widget of
  /// [context] rebuilds when the controller, its options, its style or
  /// whether it is paused change, but not when the camera moves.
  /// Used in [MapController.maybeOf] and [MapOptions.maybeOf].
  static MapController? maybeMapControllerOf(BuildContext context) =>
      _of(context, MapLibreAspect.controller)?.mapController;

  /// Get the in the widget tree injected [CameraPosition]. The widget of
  /// [context] rebuilds whenever the camera moves.
  /// Used in [CameraPosition.maybeOf].
  static CameraPosition? maybeCameraPositionOf(BuildContext context) =>
      _of(context, MapLibreAspect.camera)?.cameraPosition;

  /// The loaded [StyleController] of the closest map. The widget of
  /// [context] rebuilds when it or its layers, sources or attributions
  /// change. Used in [StyleController.maybeOf].
  static StyleController? maybeStyleOf(BuildContext context) =>
      _of(context, MapLibreAspect.style)?.style;

  /// The registry of the closest map, without depending on it.
  static MapPluginRegistry? maybePluginsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MapLibreInheritedModel>()?.plugins;

  bool _controllerChanged(MapLibreInheritedModel oldWidget) =>
      !identical(mapController, oldWidget.mapController) ||
      options != oldWidget.options ||
      !identical(style, oldWidget.style) ||
      renderingPaused != oldWidget.renderingPaused;

  bool _styleChanged(MapLibreInheritedModel oldWidget) =>
      !identical(style, oldWidget.style) ||
      styleRevision != oldWidget.styleRevision;

  bool _cameraChanged(MapLibreInheritedModel oldWidget) =>
      cameraPosition != oldWidget.cameraPosition;

  @override
  bool updateShouldNotify(covariant MapLibreInheritedModel oldWidget) =>
      _controllerChanged(oldWidget) ||
      _cameraChanged(oldWidget) ||
      _styleChanged(oldWidget);

  @override
  bool updateShouldNotifyDependent(
    covariant MapLibreInheritedModel oldWidget,
    Set<MapLibreAspect> dependencies,
  ) =>
      (dependencies.contains(MapLibreAspect.controller) &&
          _controllerChanged(oldWidget)) ||
      (dependencies.contains(MapLibreAspect.camera) &&
          _cameraChanged(oldWidget)) ||
      (dependencies.contains(MapLibreAspect.style) && _styleChanged(oldWidget));
}

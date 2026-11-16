import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre/maplibre.dart';
import 'package:maplibre/src/location/user_location_style_layers.dart';

/// Shows the user location on the [MapLibreMap] by using it in
/// [MapLibreMap.children], and moves the camera with it while [tracking].
/// It is a [MapPlugin] of the map.
///
/// The layer takes its locations from a stream, so it works the same on
/// every platform and with any location source. It asks for no permission;
/// use a package such as `permission_handler` or `geolocator` for that, and
/// `maplibre_geolocator` to turn `geolocator` positions into locations.
///
/// A gesture that moves the map, such as a drag, a pinch or a scroll wheel
/// zoom, stops the tracking and reports [UserLocationTracking.none] to
/// [onTrackingChanged].
///
/// The location shows as a dot, a circle of its accuracy and a cone of its
/// heading, which [style] changes. They are style layers of the map, so the
/// map draws them in the same frame as everything else, and the accuracy and
/// the heading lie flat on a tilted map. [anchor] places them among the
/// layers of the style, for example below its labels.
///
/// {@category Location}
class UserLocationLayer extends StatefulWidget {
  /// Creates a layer that shows the latest of [locations].
  const UserLocationLayer({
    required this.locations,
    this.tracking = UserLocationTracking.none,
    this.onTrackingChanged,
    this.trackingZoom,
    this.trackingDuration = const Duration(milliseconds: 500),
    this.style = const UserLocationStyle(),
    this.anchor = const LayerAnchor.top(),
    this.onClick,
    super.key,
  });

  /// The locations of the user. The layer shows the latest one.
  final Stream<UserLocation> locations;

  /// How the camera moves with the user location.
  final UserLocationTracking tracking;

  /// Called when the tracking changes because the user moved the map.
  final ValueChanged<UserLocationTracking>? onTrackingChanged;

  /// The zoom the camera moves to when the tracking starts, or null to keep
  /// the zoom.
  final double? trackingZoom;

  /// How long the camera takes to follow a new location.
  final Duration trackingDuration;

  /// How the location is drawn.
  final UserLocationStyle style;

  /// Where the layers of the location go among the layers of the style, on
  /// top of them by default, see [Layer.anchor].
  final LayerAnchor anchor;

  /// Called when the user taps or clicks the location.
  final ValueChanged<UserLocation>? onClick;

  @override
  State<UserLocationLayer> createState() => _UserLocationLayerState();
}

class _UserLocationLayerState extends State<UserLocationLayer> {
  StreamSubscription<UserLocation>? _subscription;
  UserLocation? _location;
  late UserLocationTracking _tracking = widget.tracking;

  /// Whether the camera has moved to the location since the tracking
  /// started, so [UserLocationLayer.trackingZoom] applies only once.
  var _tracked = false;

  /// The PNGs of the heading cone, by color, the most recently used last.
  static final _headingImages = <Color, Future<Uint8List>>{};

  /// How many colors [_headingImages] keeps.
  static const _maxHeadingImages = 8;

  /// The heading cone in the color of [UserLocationLayer.style], once it is
  /// drawn.
  Uint8List? _headingImage;
  Color? _headingColor;

  /// The layers that show the location, which change only with the location,
  /// the widget and the heading image, so that a rebuild of the parent hands
  /// the plugin the same layers.
  List<Layer> _layers = const [];

  @override
  void initState() {
    super.initState();
    _subscribe();
    _loadHeadingImage();
  }

  @override
  void didUpdateWidget(UserLocationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locations != oldWidget.locations) {
      unawaited(_subscription?.cancel());
      _subscribe();
    }
    if (widget.tracking != oldWidget.tracking) {
      _tracking = widget.tracking;
      _tracked = false;
      _follow();
    }
    if (widget.style != oldWidget.style ||
        widget.anchor != oldWidget.anchor ||
        (widget.onClick == null) != (oldWidget.onClick == null)) {
      _loadHeadingImage();
      _updateLayers();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.locations.listen((location) {
      if (!mounted) return;
      setState(() {
        _location = location;
        _updateLayers();
      });
      _follow();
    });
  }

  /// Moves the camera to the latest location while tracking.
  void _follow() {
    final location = _location;
    final controller = MapController.maybeOf(context);
    if (location == null ||
        controller == null ||
        _tracking == UserLocationTracking.none) {
      return;
    }
    final zoom = _tracked ? null : widget.trackingZoom;
    _tracked = true;
    unawaited(
      controller.animateCamera(
        CameraUpdate.position(
          center: location.position,
          zoom: zoom,
          bearing: _tracking == UserLocationTracking.positionAndHeading
              ? location.heading
              : null,
        ),
        animation: CameraAnimation.fly(duration: widget.trackingDuration),
      ),
    );
  }

  /// Stops the tracking when the user moves the map.
  void _onCameraMoveStart(MapEventCameraMoveStart event) {
    if (event.reason != CameraChangeReason.gesture ||
        _tracking == UserLocationTracking.none) {
      return;
    }
    _tracking = UserLocationTracking.none;
    widget.onTrackingChanged?.call(UserLocationTracking.none);
  }

  /// Reports a tap on the location. A method, so that the layers of every
  /// location get the same callback.
  void _onClick(LayerFeatureEvent event) {
    if (_location case final location?) widget.onClick?.call(location);
  }

  /// Draws the heading cone in the color of [UserLocationLayer.style], once
  /// per color.
  void _loadHeadingImage() {
    final style = widget.style;
    if (!style.showHeading) return;
    final color = style.color;
    if (_headingColor == color) return;
    _headingColor = color;
    _headingImage = null;
    // Reinserting the color makes it the most recently used.
    final image = _headingImages.remove(color) ?? drawHeadingImage(color);
    _headingImages[color] = image;
    while (_headingImages.length > _maxHeadingImages) {
      _headingImages.remove(_headingImages.keys.first);
    }
    unawaited(
      image.then(
        (bytes) {
          if (mounted && _headingColor == color) {
            setState(() {
              _headingImage = bytes;
              _updateLayers();
            });
          }
        },
        onError: (Object error, StackTrace stack) {
          // A later layer of this color draws it again.
          if (identical(_headingImages[color], image)) {
            _headingImages.remove(color);
          }
          if (mounted && _headingColor == color) _headingColor = null;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'maplibre',
              context: ErrorDescription(
                'while drawing the user location heading',
              ),
            ),
          );
        },
      ),
    );
  }

  /// Makes the layers that show the location.
  void _updateLayers() {
    final location = _location;
    _layers = location == null
        ? const []
        : userLocationStyleLayers(
            location: location,
            style: widget.style,
            anchor: widget.anchor,
            onClick: widget.onClick == null ? null : _onClick,
            headingImage: _headingImage,
          );
  }

  @override
  Widget build(BuildContext context) =>
      MapPlugin(onCameraMoveStart: _onCameraMoveStart, layers: _layers);
}

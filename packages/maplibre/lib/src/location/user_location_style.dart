import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:maplibre/maplibre.dart';

/// How a [UserLocationLayer] draws the user location: a dot, a circle of
/// its accuracy and a cone of its heading, see [UserLocationLayer.style].
///
/// ```dart
/// UserLocationLayer(
///   locations: locations,
///   style: const UserLocationStyle(color: Color(0xFF2E7D32), radius: 10),
/// )
/// ```
///
/// {@category Location}
@immutable
class UserLocationStyle with Diagnosticable {
  /// Creates a style of the user location.
  const UserLocationStyle({
    this.color = const Color(0xFF1A73E8),
    this.radius = 8,
    this.showAccuracy = true,
    this.showHeading = true,
    this.icon,
    this.rotateIcon = true,
  }) : assert(radius > 0, 'radius must be positive');

  /// The color of the dot, of its accuracy circle and of its heading.
  final Color color;

  /// The radius of the dot in logical pixels. The heading scales with it.
  final double radius;

  /// Whether the accuracy of the location shows as a circle around it.
  final bool showAccuracy;

  /// Whether the heading of the location shows as a cone.
  final bool showHeading;

  /// The image that replaces the dot, such as an arrow, or null for the dot.
  ///
  /// While it turns with the heading, see [rotateIcon], it shows the heading
  /// instead of the cone.
  final MarkerIcon? icon;

  /// Whether [icon] turns with the heading of the location. If not, it
  /// stays upright on the screen.
  final bool rotateIcon;

  /// Creates a copy of this style with the given fields replaced.
  ///
  /// A null [icon] keeps the icon. To go back to the dot, create a new
  /// [UserLocationStyle] instead.
  UserLocationStyle copyWith({
    Color? color,
    double? radius,
    bool? showAccuracy,
    bool? showHeading,
    MarkerIcon? icon,
    bool? rotateIcon,
  }) => UserLocationStyle(
    color: color ?? this.color,
    radius: radius ?? this.radius,
    showAccuracy: showAccuracy ?? this.showAccuracy,
    showHeading: showHeading ?? this.showHeading,
    icon: icon ?? this.icon,
    rotateIcon: rotateIcon ?? this.rotateIcon,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserLocationStyle &&
          color == other.color &&
          radius == other.radius &&
          showAccuracy == other.showAccuracy &&
          showHeading == other.showHeading &&
          icon == other.icon &&
          rotateIcon == other.rotateIcon;

  @override
  int get hashCode =>
      Object.hash(color, radius, showAccuracy, showHeading, icon, rotateIcon);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(DoubleProperty('radius', radius))
      ..add(
        FlagProperty(
          'showAccuracy',
          value: showAccuracy,
          ifFalse: 'no accuracy',
        ),
      )
      ..add(
        FlagProperty('showHeading', value: showHeading, ifFalse: 'no heading'),
      )
      ..add(DiagnosticsProperty<MarkerIcon>('icon', icon, defaultValue: null))
      ..add(
        FlagProperty('rotateIcon', value: rotateIcon, ifFalse: 'upright icon'),
      );
  }
}

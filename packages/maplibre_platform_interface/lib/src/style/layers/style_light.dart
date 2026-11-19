part of 'style_layer.dart';

/// What [StyleLight] keeps: the light JSON of the style, and the map it
/// sends changes to. The typed properties are generated from the style spec.
abstract class _StyleLightBase with _JsonProperties {
  _StyleLightBase(this._backend);

  final StyleBackend _backend;

  /// The light JSON of the style, with the changes made since it loaded.
  final _json = <String, Object?>{};

  /// The keys that the map may hold a value of: those of the loaded light and
  /// those set since.
  final _mapKeys = <String>{};

  var _replaced = false;
  var _warnedReplaced = false;

  /// The JSON defaults of the properties of the style spec.
  Map<String, Object?> get _defaults;

  /// Reads the light from the `light` member of the style JSON. Platforms
  /// call it when the style loads.
  void load(Object? light) {
    _json.clear();
    if (light is Map<String, Object?>) _json.addAll(light);
    _mapKeys
      ..clear()
      ..addAll(_json.keys);
  }

  /// Detaches the light, when a new style is set on the map. Platforms call
  /// it. Its setters then only change the object.
  void markReplaced() => _replaced = true;

  /// The light as the light JSON of a style.
  Map<String, Object?> toJson() => {..._json};

  @override
  Object? _read(String name) => _json[name];

  @override
  void _write(String name, Object? value) {
    if (value == null) {
      _json.remove(name);
    } else {
      _json[name] = value;
    }
    if (_replaced) {
      if (!_warnedReplaced && kDebugMode) {
        debugPrint(
          'maplibre: the style was replaced, so changing its light no '
          'longer updates the map.',
        );
      }
      _warnedReplaced = true;
      return;
    }
    _mapKeys.add(name);
    // Both platforms take the whole light best: gl-js only has setLight.
    // gl-js keeps the keys that are left out, so a removed key goes back to
    // its default explicitly: the spec default for a value, an empty
    // transition for the style's default transition.
    _backend.setLight({
      for (final key in _mapKeys) key: ?(_json[key] ?? _resetValue(key)),
    });
  }

  Object? _resetValue(String key) =>
      key.endsWith('-transition') ? const <String, Object?>{} : _defaults[key];
}

import 'dart:collection';

import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';
import 'package:maplibre_platform_interface/src/style/expressions/expression_json.dart';

/// The global state of a map style, which layers read with the
/// `global-state` expression ([Expression.globalState]).
///
/// It is the `state` defaults of the style, overridden by
/// [MapOptions.globalState]. It is a read-only view that follows those
/// options: change [MapOptions.globalState] to change it.
///
/// {@category Style}
final class StyleGlobalState extends UnmodifiableMapBase<String, Object?> {
  StyleGlobalState._(this._backend);

  final StyleBackend _backend;

  /// The defaults of the style's `state`, or null until the style loaded.
  Map<String, Object?>? _defaults;

  /// The values of [MapOptions.globalState] that reached the map, without
  /// nulls.
  Map<String, Object?> _values = const {};

  /// The keys that the previous style of the map had set, which the next
  /// [_apply] resets unless the options still have them.
  Set<String> _previousKeys = const {};

  /// The keys to reset to their default once the style loaded and the
  /// defaults are known.
  final _pendingResets = <String>{};

  var _replaced = false;

  @override
  Object? operator [](Object? key) =>
      _values.containsKey(key) ? _values[key] : _defaults?[key];

  @override
  Iterable<String> get keys => {...?_defaults?.keys, ..._values.keys};

  void _load(Object? state) {
    final defaults = _defaults = {
      if (state is Map<String, Object?>)
        for (final MapEntry(:key, :value) in state.entries)
          if (value is Map<String, Object?>) key: value['default'],
    };
    if (_replaced) return;
    for (final key in _pendingResets) {
      _backend.setGlobalStateProperty(key, defaults[key]);
    }
    _pendingResets.clear();
  }

  void _apply(Map<String, Object?> values) {
    if (_replaced) return;
    final next = {
      for (final MapEntry(:key, :value) in values.entries) key: ?value,
    };
    final previousKeys = _previousKeys;
    _previousKeys = const {};
    for (final key in {...previousKeys, ..._values.keys, ...next.keys}) {
      if (next.containsKey(key)) {
        if (_values.containsKey(key) && jsonEquals(_values[key], next[key])) {
          continue;
        }
        _pendingResets.remove(key);
        _backend.setGlobalStateProperty(key, next[key]);
      } else if (_defaults case final defaults?) {
        // Removed: back to the style's default.
        _backend.setGlobalStateProperty(key, defaults[key]);
      } else {
        _pendingResets.add(key);
      }
    }
    _values = Map.unmodifiable(next);
  }
}

/// The parts of a style that every platform keeps in Dart alike: its
/// [light], its [globalState] and its default [transition]. Platforms mix
/// it into their [StyleController] and call [loadStyleState],
/// [applyGlobalState] and [markStyleStateReplaced].
mixin StyleStateMixin on StyleController implements StyleBackend {
  @override
  late final StyleLight light = StyleLight(this);

  @override
  late final StyleGlobalState globalState = StyleGlobalState._(this);

  @override
  StyleTransition get transition => _transition;
  var _transition = const StyleTransition();

  var _stateReplaced = false;

  @override
  set transition(StyleTransition value) {
    _transition = value;
    if (!_stateReplaced) setTransition(value);
  }

  /// Reads the light, the defaults of the global state and the transition
  /// from the JSON of the style that the map loaded.
  void loadStyleState(Map<String, Object?> style) {
    light.load(style['light']);
    globalState._load(style['state']);
    if (style['transition'] case final Map<String, Object?> transition) {
      _transition = StyleTransition.fromJson(transition);
    }
  }

  /// Sends the values of [MapOptions.globalState] that changed to the map. A
  /// key that is missing or null goes back to the style's default, once that
  /// is known.
  ///
  /// [previous] is the style that the map held before, on the first call:
  /// the keys it set go back to their default too, as a map can keep its
  /// global state when its style changes.
  void applyGlobalState(
    Map<String, Object?> values, {
    StyleStateMixin? previous,
  }) {
    if (previous != null) {
      globalState._previousKeys = {
        ...previous.globalState._values.keys,
        ...previous.globalState._pendingResets,
        ...previous.globalState._previousKeys,
      };
    }
    globalState._apply(values);
  }

  /// Detaches the light, the global state and the transition, when a new
  /// style is set on the map. Their changes no longer reach the map.
  void markStyleStateReplaced() {
    _stateReplaced = true;
    light.markReplaced();
    globalState._replaced = true;
  }
}

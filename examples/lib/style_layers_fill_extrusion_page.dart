import 'package:maplibre/maplibre.dart';
import 'package:maplibre_example/utils/map_styles.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class StyleLayersFillExtrusionPage extends StatefulWidget {
  const StyleLayersFillExtrusionPage({super.key});

  static const location = '/style-layers/fill-extrusion';

  @override
  State<StyleLayersFillExtrusionPage> createState() =>
      _StyleLayersFillExtrusionPageState();
}

const _sourceId = 'floorplan';

class _StyleLayersFillExtrusionPageState
    extends State<StyleLayersFillExtrusionPage> {
  StyleController? _style;
  var _night = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fill Extrusion Style Layer')),
      floatingActionButton: FloatingActionButton(
        tooltip: _night ? 'Day' : 'Night',
        onPressed: _toggleNight,
        child: Icon(_night ? Icons.light_mode : Icons.dark_mode),
      ),
      body: MapLibreMap(
        options: MapOptions(
          style: MapStyles.protomapsLight.style,
          // The layer reads it with Expression.globalState.
          globalState: {'night': _night},
          initCamera: const CameraUpdate.position(
            center: Geographic(lon: -87.61694, lat: 41.86625),
            zoom: 15.99,
            pitch: 40,
            bearing: 20,
          ),
        ),
        onStyleLoaded: _onStyleLoaded,
      ),
    );
  }

  void _toggleNight() {
    setState(() => _night = !_night);
    // The light is part of the style, so it changes on the style.
    _style?.light
      ?..colorTransition = const StyleTransition(duration: Duration(seconds: 1))
      ..color = .literal(_night ? const Color(0xFF8090FF) : Colors.white)
      ..intensity = .literal(_night ? 0.2 : 0.5);
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    _style = style;
    await style.sources.add(
      const GeoJsonSource.url(
        id: _sourceId,
        url: 'https://maplibre.org/maplibre-gl-js/docs/assets/indoor-3d-map.geojson',
      ),
    );
    await style.layers.add(_fillExtrusionStyleLayer);
  }
}

final _fillExtrusionStyleLayer = FillExtrusionStyleLayer(
  id: 'room-extrusion',
  sourceId: _sourceId,
  // See the MapLibre Style Specification for details on data expressions.
  // https://maplibre.org/maplibre-style-spec/expressions/

  // Get the color from the source 'color' property, or a dark gray at night.
  color: .select([
    (
      Expression.equal(.globalState('night'), const .literal(true)),
      const .literal(Color(0xFF404050)),
    ),
  ], fallback: .get('color').convertToColor()),

  // Get the height from the source 'height' property.
  height: .get('height').asNumber(),

  // Get the base from the source 'base_height' property.
  base: .get('base_height').asNumber(),

  // Make extrusions slightly opaque for see through indoor walls.
  opacity: const .literal(0.5),
);

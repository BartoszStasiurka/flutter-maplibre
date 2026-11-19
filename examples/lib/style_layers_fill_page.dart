import 'package:flutter/services.dart';
import 'package:maplibre/maplibre.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class StyleLayersFillPage extends StatefulWidget {
  const StyleLayersFillPage({super.key});

  static const location = '/style-layers/fill';

  @override
  State<StyleLayersFillPage> createState() => _StyleLayersFillPageState();
}

class _StyleLayersFillPageState extends State<StyleLayersFillPage> {
  static const _layerId = 'LakeConstance-Layer';
  static const _sourceId = 'LakeConstance-Source';

  late final MapController _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fill Style Layer')),
      body: MapLibreMap(
        options: const MapOptions(
          initCamera: CameraUpdate.position(
            zoom: 7,
            center: Geographic(lon: 9.17, lat: 47.68),
          ),
        ),
        onMapCreated: (controller) => _controller = controller,
        onStyleLoaded: _onStyleLoaded,
        onClick: (event) async {
          final features = await _controller.queryRenderedFeatures(
            .point(event.screenPoint),
            layerIds: [_layerId],
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    features.isEmpty
                        ? 'Clicked outside of Lake Constance'
                        : 'Clicked on Lake Constance',
                  ),
                ),
              );
          }
        },
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    final geojsonPolygon = await rootBundle.loadString(
      'assets/geojson/lake-constance.json',
    );
    await style.sources.add(
      GeoJsonSource.data(id: _sourceId, data: .text(geojsonPolygon)),
    );
    await style.layers.add(
      FillStyleLayer(
        id: _layerId,
        sourceId: _sourceId,
        // Darker while the mouse is over the lake: the feature state changes
        // the color without touching the data of the source.
        color: .select([
          (
            Expression.equal(.featureState('hover'), const .literal(true)),
            const .literal(Color(0xFF1565C0)),
          ),
        ], fallback: const .literal(Color(0xFF429EF5))),
        onEnter: (event) =>
            style.sources.setFeatureState(.of(event.feature), {'hover': true}),
        onLeave: (event) =>
            style.sources.setFeatureState(.of(event.feature), {'hover': false}),
      ),
    );
  }
}

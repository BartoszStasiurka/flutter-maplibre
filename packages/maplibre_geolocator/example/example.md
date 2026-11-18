Show the location of the device on a `MapLibreMap` with a `UserLocationLayer`:

```dart
import 'package:maplibre/maplibre.dart';
import 'package:maplibre_geolocator/maplibre_geolocator.dart';

MapLibreMap(
  options: MapOptions(
    style: MapStyle.url('https://demotiles.maplibre.org/style.json'),
  ),
  children: [
    UserLocationLayer(locations: geolocatorUserLocations()),
  ],
)
```

Ask for the location permission first, for example with
`Geolocator.requestPermission()`. The
[User Location chapter](https://maplibre.org/flutter-maplibre/docs/user-location/)
of the documentation covers permissions, platform setup and tracking, and the
example app
has a [complete page](https://github.com/maplibre/flutter-maplibre/blob/main/examples/lib/user_location_page.dart).

import Foundation
import MapLibre
import UIKit

// Update the header file for this class like this:
// cd maplibre_ios/ios/maplibre_ios/Sources/maplibre_ios/
// ./gen_swift_headers.sh

@objc(MapLibreRegistry)
public class MapLibreRegistry: NSObject {
    private static var mapViews: [Int64: MLNMapView] = [:]
    private static var flutterApis: [Int64: FlutterApi] = [:]
    private static var platformViews: [Int64: MapLibreView] = [:]

    /// Method to get the map for a given viewId
    @objc public static func getMap(viewId: Int64) -> MLNMapView? {
        mapViews[viewId]
    }

    /// Method to add a map to the registry
    @objc public static func addMap(viewId: Int64, map: MLNMapView) {
        mapViews[viewId] = map
    }

    /// Method to remove a map to the registry
    @objc public static func removeMap(viewId: Int64) {
        mapViews.removeValue(forKey: viewId)
    }

    /// Method to get the flutter api for a given viewId
    @objc public static func getFlutterApi(viewId: Int64) -> FlutterApi? {
        flutterApis[viewId]
    }

    /// Method to add a flutter api to the registry
    @objc public static func addFlutterApi(viewId: Int64, api: FlutterApi) {
        flutterApis[viewId] = api
        // Flush pending callbacks after a short delay to ensure Dart FFI is fully initialized
        // The delay is necessary because the FlutterApi object may exist before
        // Dart's FFI callback metadata is registered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            platformViews[viewId]?.flushPendingStyleLoad()
        }
    }

    /// Method to remove a flutter api to the registry
    @objc public static func removeFlutterApi(viewId: Int64) {
        flutterApis.removeValue(forKey: viewId)
    }
    
    /// Method to add a platform view to the registry
    static func addPlatformView(viewId: Int64, view: MapLibreView) {
        platformViews[viewId] = view
    }
}

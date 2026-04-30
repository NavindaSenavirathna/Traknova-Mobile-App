import '../models/geofence_models.dart';

/// Client-side GeoFence detection using ray casting algorithm.
///
/// This provides instant ENTRY/EXIT detection as a backup/complement
/// to server-side MongoDB $geoWithin detection.
class GeoFenceDetector {
  /// Track previous in/out state for each device-fence pair
  final Map<String, bool> _previousStates = {};

  /// Check if a point [lat, lng] is inside a polygon using ray casting.
  static bool isPointInPolygon(double lat, double lng, List<List<double>> polygon) {
    if (polygon.length < 3) return false;

    bool inside = false;
    final n = polygon.length;

    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i][0], yi = polygon[i][1];
      final xj = polygon[j][0], yj = polygon[j][1];

      final intersect = ((yi > lng) != (yj > lng)) &&
          (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi);

      if (intersect) inside = !inside;
    }

    return inside;
  }

  /// Check a device's position against all active geofences.
  /// Returns list of new ENTRY/EXIT events (transitions only).
  List<GeoFenceAlert> checkDevice({
    required String deviceCode,
    required String vehicleNo,
    required double lat,
    required double lng,
    required List<GeoFenceConfig> activeFences,
  }) {
    final alerts = <GeoFenceAlert>[];

    for (final fence in activeFences) {
      // Skip if fence doesn't apply to this device
      if (fence.mode == 'DEVICE' && !fence.devices.contains(deviceCode)) {
        continue;
      }

      // Skip expired fences
      if (!fence.isActive) continue;

      // Skip if no boundary
      if (fence.boundary.length < 3) continue;

      final key = '${deviceCode}_${fence.code}';
      final isInside = isPointInPolygon(lat, lng, fence.boundary);
      final wasInside = _previousStates[key];

      if (wasInside != null) {
        // ENTRY detection
        if (!wasInside && isInside && fence.alarmMode.contains('ENTRY')) {
          alerts.add(GeoFenceAlert(
            fenceName: fence.name,
            vehicleNo: vehicleNo,
            mode: 'ENTRY',
            time: _formatTime(DateTime.now()),
            alarmOptions: fence.alarmOptions,
          ));
        }

        // EXIT detection
        if (wasInside && !isInside && fence.alarmMode.contains('EXIT')) {
          alerts.add(GeoFenceAlert(
            fenceName: fence.name,
            vehicleNo: vehicleNo,
            mode: 'EXIT',
            time: _formatTime(DateTime.now()),
            alarmOptions: fence.alarmOptions,
          ));
        }
      }

      _previousStates[key] = isInside;
    }

    return alerts;
  }

  /// Reset all tracked states
  void reset() {
    _previousStates.clear();
  }

  /// Remove states for a specific device
  void removeDevice(String deviceCode) {
    _previousStates.removeWhere((key, _) => key.startsWith('${deviceCode}_'));
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

import 'package:latlong2/latlong.dart';

/// A single GPS fix from any source: hardware tracker via rr_new_git,
/// phone via TcpTrackerService / PhoneTrackerService, or structured API.
///
/// Handles two wire formats:
///
/// 1. **Flat (rr_new_git)**  — produced by `formattedMessage.js`
///    `{ typeCode, imei, lat, lon, speed, direction, time, protocol, device, io:{} }`
///
/// 2. **Structured (API/AMQ trip)** — produced by `VehicleSensorData`
///    `{ deviceId, timestamp, location:{ latitude, longitude, speed, bearing } }`
class TrackerPoint {
  final String deviceId;   // IMEI or phone ID
  final LatLng position;
  final double speed;      // km/h
  final double bearing;    // degrees
  final double? accuracy;  // metres (phone only)
  final DateTime timestamp;
  final String protocol;   // 'mobile', 'TK100', 'H02', etc.
  final String? tripId;

  const TrackerPoint({
    required this.deviceId,
    required this.position,
    required this.speed,
    required this.bearing,
    this.accuracy,
    required this.timestamp,
    this.protocol = 'unknown',
    this.tripId,
  });

  // ── Flat rr_new_git wire format ─────────────────────────────────────────
  static TrackerPoint? fromRawJson(Map<String, dynamic> json) {
    try {
      // Accept both String and num for lat/lon
      final lat  = _toDouble(json['lat']);
      final lon  = _toDouble(json['lon']);
      if (lat == null || lon == null) return null;
      if (lat == 0.0 && lon == 0.0)  return null;    // invalid fix

      final imei = json['imei']?.toString() ?? 'unknown';
      final spd  = _toDouble(json['speed']) ?? 0.0;
      final dir  = _toDouble(json['direction']) ?? 0.0;
      final prot = json['protocol']?.toString() ?? 'unknown';
      final ts   = _parseTime(json['time']?.toString());
      final io   = json['io'] as Map<String, dynamic>?;

      return TrackerPoint(
        deviceId  : imei,
        position  : LatLng(lat, lon),
        speed     : spd,
        bearing   : dir,
        accuracy  : _toDouble(io?['accuracy']),
        timestamp : ts,
        protocol  : prot,
        tripId    : io?['tripId']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Structured API / VehicleSensorData wire format ──────────────────────
  static TrackerPoint? fromStructuredJson(Map<String, dynamic> json) {
    try {
      final loc = json['location'] as Map<String, dynamic>?;
      if (loc == null) return null;

      final lat = _toDouble(loc['latitude']);
      final lon = _toDouble(loc['longitude']);
      if (lat == null || lon == null) return null;

      final id  = json['deviceId']?.toString() ?? 'unknown';
      final spd = _toDouble(loc['speed']) ?? 0.0;
      final brg = _toDouble(loc['bearing']) ?? 0.0;
      final ts  = DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now();

      return TrackerPoint(
        deviceId  : id,
        position  : LatLng(lat, lon),
        speed     : spd,
        bearing   : brg,
        timestamp : ts,
        protocol  : 'api',
      );
    } catch (_) {
      return null;
    }
  }

  /// Tries flat format first, then structured.
  static TrackerPoint? fromAnyJson(Map<String, dynamic> json) =>
      fromRawJson(json) ?? fromStructuredJson(json);

  // ── Helpers ──────────────────────────────────────────────────────────────
  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num)  return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static DateTime _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.now();
    // Handles 'YYYY-MM-DD HH:mm:ss' (rr_new_git) and ISO 8601
    return DateTime.tryParse(raw.replaceFirst(' ', 'T')) ?? DateTime.now();
  }

  @override
  String toString() =>
      'TrackerPoint($deviceId @ ${position.latitude.toStringAsFixed(5)}, '
      '${position.longitude.toStringAsFixed(5)}, '
      '${speed.toStringAsFixed(1)} km/h, ${bearing.toStringAsFixed(0)}°)';
}

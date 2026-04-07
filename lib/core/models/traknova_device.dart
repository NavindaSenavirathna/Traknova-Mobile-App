/// Model for a TrakNova vehicle/device extracted from the web dashboard.
///
/// Mirrors the DEVICES[] JavaScript variable injected into `/user/home`.
class TraknovaDevice {
  final String imei;
  final String deviceCode;
  final String deviceName;
  final String vehicleNo;
  final String? connectionNo;
  final String? deviceIcon;
  final int geoDiff; // minutes — offline threshold
  final int speedLimit;
  final bool engineMode;
  final String initState; // 'ONLINE' | 'OFFLINE'

  // Latest known position from page load (may be stale)
  final double? latitude;
  final double? longitude;
  final double? speed;
  final DateTime? lastSeen;

  // Runtime state — updated by MQTT
  double? liveLatitude;
  double? liveLongitude;
  double? liveSpeed;
  int? liveDirection;
  DateTime? liveTimestamp;
  bool? ignitionOn; // from io["239"]["Ignition"] — 0=off,1=on

  TraknovaDevice({
    required this.imei,
    required this.deviceCode,
    required this.deviceName,
    required this.vehicleNo,
    this.connectionNo,
    this.deviceIcon,
    this.geoDiff = 5,
    this.speedLimit = 70,
    this.engineMode = true,
    this.initState = 'OFFLINE',
    this.latitude,
    this.longitude,
    this.speed,
    this.lastSeen,
  });

  /// Whether the device is considered online.
  /// Uses live data if available, otherwise falls back to initial data.
  bool get isOnline {
    final ts = liveTimestamp ?? lastSeen;
    if (ts == null) return false;
    final diffMinutes = DateTime.now().difference(ts).inMinutes;
    return diffMinutes <= geoDiff;
  }

  /// Current lat (live > initial).
  double? get currentLatitude => liveLatitude ?? latitude;

  /// Current lon (live > initial).
  double? get currentLongitude => liveLongitude ?? longitude;

  /// Current speed (live > initial).
  double get currentSpeed => liveSpeed ?? speed ?? 0;

  /// Current direction / bearing (default 0).
  int get currentDirection => liveDirection ?? 0;

  /// Current timestamp.
  DateTime? get currentTimestamp => liveTimestamp ?? lastSeen;

  /// Has a valid position (live or initial).
  bool get hasPosition => currentLatitude != null && currentLongitude != null;

  /// Parse from the JSON object in DEVICES[] JavaScript variable.
  factory TraknovaDevice.fromJson(Map<String, dynamic> json) {
    // Parse latestGeoData
    double? lat, lon, spd;
    DateTime? lastTs;
    final geo = json['latestGeoData'];
    if (geo != null && geo is Map<String, dynamic>) {
      lat = _toDouble(geo['latitude']) ?? _toDouble((geo['geo'] as List?)?.firstOrNull);
      lon = _toDouble(geo['longitude']) ?? _toDouble((geo['geo'] as List?)?.elementAtOrNull(1));
      spd = _toDouble(geo['speed']);
      // Parse MongoDB timestamp format { "$date": { "$numberLong": "..." } }
      final tsMap = geo['timeStamp'];
      if (tsMap is Map) {
        final dateMap = tsMap['\$date'];
        if (dateMap is Map && dateMap['\$numberLong'] != null) {
          lastTs = DateTime.fromMillisecondsSinceEpoch(
            int.parse(dateMap['\$numberLong'].toString()),
          );
        } else if (dateMap is int) {
          lastTs = DateTime.fromMillisecondsSinceEpoch(dateMap);
        }
      }
    }

    return TraknovaDevice(
      imei: json['imei']?.toString() ?? '',
      deviceCode: json['deviceCode']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? json['vehicleNo']?.toString() ?? '',
      vehicleNo: json['vehicleNo']?.toString() ?? '',
      connectionNo: json['connectionNo']?.toString(),
      deviceIcon: json['deviceIcon']?.toString(),
      geoDiff: _toInt(json['geoDiff']) ?? 5,
      speedLimit: _toInt(json['speedLimit']) ?? 70,
      engineMode: json['engineMode'] == true,
      initState: json['initState']?.toString() ?? 'OFFLINE',
      latitude: lat,
      longitude: lon,
      speed: spd,
      lastSeen: lastTs,
    );
  }

  /// Update with MQTT live message data.
  void updateFromMqtt(Map<String, dynamic> data) {
    liveLatitude = _toDouble(data['lat']) ?? liveLatitude;
    liveLongitude = _toDouble(data['lon']) ?? liveLongitude;
    liveSpeed = _toDouble(data['speed']) ?? liveSpeed;
    liveDirection = _toInt(data['direction']) ?? liveDirection;

    // Parse time
    final timeStr = data['time']?.toString();
    if (timeStr != null && timeStr.isNotEmpty) {
      liveTimestamp = DateTime.tryParse(timeStr.replaceFirst(' ', 'T')) ?? DateTime.now();
    } else {
      liveTimestamp = DateTime.now();
    }

    // Parse ignition from io data
    final io = data['io'];
    if (io is Map) {
      // io["239"]["Ignition"] = 0 or 1
      final ign = io['239'];
      if (ign is Map) {
        final ignVal = ign['Ignition'] ?? ign.values.firstOrNull;
        if (ignVal != null) {
          ignitionOn = ignVal == 1 || ignVal == '1' || ignVal == true;
        }
      }
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  @override
  String toString() => 'TraknovaDevice($vehicleNo, imei=$imei, '
      'pos=${currentLatitude?.toStringAsFixed(4)},${currentLongitude?.toStringAsFixed(4)}, '
      'online=$isOnline)';
}

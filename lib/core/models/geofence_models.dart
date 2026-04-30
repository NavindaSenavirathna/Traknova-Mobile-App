import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  GeoFence Data Models — TrakNova Mobile App
// ═══════════════════════════════════════════════════════════════════════════════

/// GeoFence configuration from `/geo-fence/api/getDesigns`
class GeoFenceConfig {
  final String id;
  final String name;
  final String code;
  final String mode;           // "DEVICE" or "REGION"
  final String modal;          // "AREA" or "ROUTE"
  final String color;          // CSS color string: "rgb(0,128,0)"
  final String? desc;
  final String regionCode;
  final List<List<double>> boundary;  // [[lat, lng], ...] closed polygon
  final List<String> devices;
  final List<String> alarmMode;       // ["ENTRY", "EXIT"]
  final List<String> alarmOptions;    // ["NOTIFY", "ALARM_NOTIFY", ...]
  final List<String> alertEmails;
  final List<String> alertContacts;
  final String startTime;
  final String expireTime;
  final List<List<double>>? routeLine;  // ROUTE mode only
  final int? offset;                     // ROUTE mode buffer (meters)

  GeoFenceConfig({
    required this.id,
    required this.name,
    required this.code,
    required this.mode,
    required this.modal,
    required this.color,
    this.desc,
    required this.regionCode,
    required this.boundary,
    required this.devices,
    required this.alarmMode,
    required this.alarmOptions,
    required this.alertEmails,
    required this.alertContacts,
    required this.startTime,
    required this.expireTime,
    this.routeLine,
    this.offset,
  });

  factory GeoFenceConfig.fromJson(Map<String, dynamic> json) {
    return GeoFenceConfig(
      id: json['_id']?['\$oid']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'DEVICE',
      modal: json['modal']?.toString() ?? 'AREA',
      color: json['color']?.toString() ?? 'rgb(0,128,0)',
      desc: json['desc']?.toString(),
      regionCode: json['regionCode']?.toString() ?? '',
      boundary: _parseBoundary(json['boundary']),
      devices: List<String>.from(json['devices'] ?? []),
      alarmMode: List<String>.from(json['alarmMode'] ?? []),
      alarmOptions: List<String>.from(json['alarmOptions'] ?? []),
      alertEmails: List<String>.from(json['alertEmails'] ?? []),
      alertContacts: List<String>.from(json['alertContacts'] ?? []),
      startTime: json['startTime']?.toString() ?? '',
      expireTime: json['expireTime']?.toString() ?? '',
      routeLine: _parseBoundary(json['routeLine']),
      offset: _toInt(json['offset']),
    );
  }

  /// Check if this fence is currently active (not expired)
  bool get isActive {
    try {
      final expire = DateTime.tryParse(expireTime);
      if (expire == null) return true;
      return DateTime.now().isBefore(expire);
    } catch (_) {
      return true;
    }
  }

  /// Check if expiring soon (within 7 days)
  bool get isExpiringSoon {
    try {
      final expire = DateTime.tryParse(expireTime);
      if (expire == null) return false;
      final diff = expire.difference(DateTime.now()).inDays;
      return diff >= 0 && diff <= 7;
    } catch (_) {
      return false;
    }
  }

  /// Parse CSS color string to Flutter Color
  Color get flutterColor {
    try {
      final match = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(color);
      if (match != null) {
        return Color.fromRGBO(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          1.0,
        );
      }
      // Try hex format
      if (color.startsWith('#')) {
        final hex = color.replaceFirst('#', '');
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        }
      }
    } catch (_) {}
    return Colors.green;
  }

  static List<List<double>> _parseBoundary(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    try {
      return value
          .map((coord) => List<double>.from(
              (coord as List).map((c) => (c as num).toDouble())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  String toString() => 'GeoFenceConfig($name, code=$code, mode=$mode, '
      'boundary=${boundary.length} points)';
}

// ─────────────────────────────────────────────────────────────────────────────

/// Device-specific geofence configuration from `/user/home/api/geo-configs`
class DeviceGeoFence {
  final String configCode;
  final String deviceCode;
  final String vehicleNo;
  final List<String> detectionMode;
  final List<String> alarmOptions;
  final bool isActive;
  final bool isAchieved;
  final GeoFenceConfig? geoConfig;

  DeviceGeoFence({
    required this.configCode,
    required this.deviceCode,
    required this.vehicleNo,
    required this.detectionMode,
    required this.alarmOptions,
    required this.isActive,
    required this.isAchieved,
    this.geoConfig,
  });

  factory DeviceGeoFence.fromJson(Map<String, dynamic> json) {
    return DeviceGeoFence(
      configCode: json['configCode']?.toString() ?? '',
      deviceCode: json['deviceCode']?.toString() ?? '',
      vehicleNo: json['vehicleNo']?.toString() ?? '',
      detectionMode: List<String>.from(json['detectionMode'] ?? []),
      alarmOptions: List<String>.from(json['alarmOptions'] ?? []),
      isActive: json['isActive'] == true,
      isAchieved: json['isAchieved'] == true,
      geoConfig: json['geoConfig'] != null
          ? GeoFenceConfig.fromJson(json['geoConfig'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// GeoFence violation history entry from `/user/home/api/geo-history`
class GeoFenceViolation {
  final String deviceConfigCode;
  final String detectionMode;  // "ENTRY" or "EXIT"
  final DateTime detectedAt;
  final List<double> geoLocation;
  final double speed;
  final String time;
  final int direction;
  final String? fenceName;
  final String? fenceCode;
  final String? vehicleNo;

  GeoFenceViolation({
    required this.deviceConfigCode,
    required this.detectionMode,
    required this.detectedAt,
    required this.geoLocation,
    required this.speed,
    required this.time,
    required this.direction,
    this.fenceName,
    this.fenceCode,
    this.vehicleNo,
  });

  factory GeoFenceViolation.fromJson(Map<String, dynamic> json) {
    // Parse MongoDB date
    DateTime parsedDate;
    try {
      final dateVal = json['detectedAt'];
      if (dateVal is Map) {
        final dateInner = dateVal['\$date'];
        if (dateInner is Map && dateInner['\$numberLong'] != null) {
          parsedDate = DateTime.fromMillisecondsSinceEpoch(
            int.parse(dateInner['\$numberLong'].toString()),
          );
        } else if (dateInner is int) {
          parsedDate = DateTime.fromMillisecondsSinceEpoch(dateInner);
        } else if (dateInner is String) {
          parsedDate = DateTime.tryParse(dateInner) ?? DateTime.now();
        } else {
          parsedDate = DateTime.now();
        }
      } else if (dateVal is String) {
        parsedDate = DateTime.tryParse(dateVal) ?? DateTime.now();
      } else {
        parsedDate = DateTime.now();
      }
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return GeoFenceViolation(
      deviceConfigCode: json['deviceConfigCode']?.toString() ?? '',
      detectionMode: json['detectionMode']?.toString() ?? '',
      detectedAt: parsedDate,
      geoLocation: _parseGeoLocation(json['geoLocation']),
      speed: _toDouble(json['geoData']?['speed']) ?? 0,
      time: json['geoData']?['time']?.toString() ?? '',
      direction: _toInt(json['geoData']?['direction']) ?? 0,
      fenceName: json['geoConfig']?['name']?.toString(),
      fenceCode: json['geoConfig']?['code']?.toString(),
      vehicleNo: json['device']?['vehicleNo']?.toString(),
    );
  }

  bool get isEntry => detectionMode == 'ENTRY';
  bool get isExit => detectionMode == 'EXIT';

  double get latitude => geoLocation.isNotEmpty ? geoLocation[0] : 0;
  double get longitude => geoLocation.length > 1 ? geoLocation[1] : 0;

  static List<double> _parseGeoLocation(dynamic val) {
    if (val is List) {
      return val.map((e) => (e as num).toDouble()).toList();
    }
    return [0, 0];
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// GeoFence alert from MQTT real-time or from notification API
class GeoFenceAlert {
  final String fenceName;
  final String vehicleNo;
  final String mode;       // "ENTRY" or "EXIT"
  final String time;
  final String date;
  final String configName;
  final String detectionMode;
  final double speed;
  final double latitude;
  final double longitude;
  final List<String> alarmOptions;
  final DateTime receivedAt;

  GeoFenceAlert({
    required this.fenceName,
    required this.vehicleNo,
    required this.mode,
    required this.time,
    this.date = '',
    this.configName = '',
    this.detectionMode = '',
    this.speed = 0,
    this.latitude = 0,
    this.longitude = 0,
    List<String>? alarmOptions,
    DateTime? receivedAt,
  })  : alarmOptions = alarmOptions ?? [],
        receivedAt = receivedAt ?? DateTime.now();

  /// Parse from MQTT message payload
  factory GeoFenceAlert.fromMqttPayload(Map<String, dynamic> json) {
    final geo = json['geo'] as Map<String, dynamic>? ?? {};
    final config = json['config'] as Map<String, dynamic>? ?? {};
    final fenceMode = json['fenceMode']?.toString() ?? '';

    return GeoFenceAlert(
      fenceName: config['name']?.toString() ?? '',
      vehicleNo: json['vehicleNo']?.toString() ?? '',
      mode: fenceMode,
      time: geo['time']?.toString() ?? '',
      date: geo['date']?.toString() ?? '',
      configName: config['name']?.toString() ?? '',
      detectionMode: fenceMode,
      speed: (geo['speed'] as num?)?.toDouble() ?? 0,
      latitude: (geo['lat'] as num?)?.toDouble() ?? 0,
      longitude: (geo['lng'] as num?)?.toDouble() ?? 0,
      alarmOptions: List<String>.from(config['alarmOptions'] ?? []),
    );
  }

  /// Parse from notification API response
  factory GeoFenceAlert.fromApiResponse(Map<String, dynamic> json) {
    // Parse MongoDB date
    String timeStr = '';
    String dateStr = '';
    try {
      final dateVal = json['detectedAt'];
      if (dateVal is Map) {
        final dateInner = dateVal['\$date'];
        if (dateInner is Map && dateInner['\$numberLong'] != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(
            int.parse(dateInner['\$numberLong'].toString()),
          );
          timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
          dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      }
    } catch (_) {}

    final loc = (json['location'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [0, 0];
    final detMode = json['detectionMode']?.toString() ?? '';

    return GeoFenceAlert(
      fenceName: json['name']?.toString() ?? '',
      vehicleNo: json['vehicleNo']?.toString() ?? '',
      mode: detMode,
      time: timeStr,
      date: dateStr,
      configName: json['name']?.toString() ?? '',
      detectionMode: detMode,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      latitude: loc.isNotEmpty ? loc[0] : 0,
      longitude: loc.length > 1 ? loc[1] : 0,
    );
  }

  bool get isEntry => mode == 'ENTRY';
  bool get isExit => mode == 'EXIT';
  bool get isAlarm => alarmOptions.contains('ALARM_NOTIFY');

  /// Unique key for de-duplication
  String get dedupeKey => '${vehicleNo}_${fenceName}_${mode}_${time}';
}

// ─────────────────────────────────────────────────────────────────────────────

/// GeoFence report entry from `/user/add-on/geo-fence/report`
class GeoFenceReportEntry {
  final String vehicleNo;
  final String geoFenceName;
  final String detectionMode;
  final String detectedAt;
  final double speed;
  final List<double> location;

  GeoFenceReportEntry({
    required this.vehicleNo,
    required this.geoFenceName,
    required this.detectionMode,
    required this.detectedAt,
    required this.speed,
    required this.location,
  });

  factory GeoFenceReportEntry.fromJson(Map<String, dynamic> json) {
    return GeoFenceReportEntry(
      vehicleNo: json['vehicleNo']?.toString() ?? '',
      geoFenceName: json['geoFenceName']?.toString() ?? '',
      detectionMode: json['detectionMode']?.toString() ?? '',
      detectedAt: json['detectedAt']?.toString() ?? '',
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      location: (json['location'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [0, 0],
    );
  }

  bool get isEntry => detectionMode == 'ENTRY';
}

// ─────────────────────────────────────────────────────────────────────────────

/// Color scheme used throughout the geofence UI
class GeoFenceColors {
  static const Color entry = Color(0xFF4CAF50);    // Green
  static const Color exit = Color(0xFFE53935);      // Red
  static const Color active = Color(0xFF4CAF50);    // Green
  static const Color expired = Color(0xFFFF9800);   // Orange
  static const Color archived = Color(0xFF9E9E9E);  // Grey
  static const Color fenceFill = Color(0x4000C896); // Semi-transparent accent
  static const Color fenceBorder = Color(0xFF00C896);
}

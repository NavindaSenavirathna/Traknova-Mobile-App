class AmqConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String exchange;
  final String topic;
  final bool isDurable;

  /// RabbitMQ virtual host — NOT the server hostname.
  /// Default is '/' which is RabbitMQ's built-in default vhost.
  final String virtualHost;

  AmqConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.exchange,
    required this.topic,
    required this.isDurable,
    this.virtualHost = '/',
  });

  factory AmqConfig.fromJson(Map<String, dynamic> json) {
    return AmqConfig(
      host: json['host'] ?? '',
      port: json['port'] ?? 15675,
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      exchange: json['exchange'] ?? 'amq.topic',
      topic: json['topic'] ?? '',
      isDurable: json['isDurable'] ?? true,
      virtualHost: json['virtualHost'] ?? json['vhost'] ?? '/',
    );
  }

  @override
  String toString() {
    return 'AmqConfig{host: $host, port: $port, username: $username, exchange: $exchange, topic: $topic, virtualHost: $virtualHost}';
  }
}

class VehicleSensorData {
  final String? deviceId;
  final DateTime timestamp;
  final LocationData? location;
  final double? temperature;
  final DoorStatus? doors;
  final SeatBeltStatus? seatBelts;
  final Map<String, dynamic> rawData;

  VehicleSensorData({
    this.deviceId,
    required this.timestamp,
    this.location,
    this.temperature,
    this.doors,
    this.seatBelts,
    required this.rawData,
  });

  factory VehicleSensorData.fromJson(Map<String, dynamic> json) {
    return VehicleSensorData(
      deviceId: json['deviceId'],
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      location: json['location'] != null ? LocationData.fromJson(json['location']) : null,
      temperature: json['temperature']?.toDouble(),
      doors: json['doors'] != null ? DoorStatus.fromJson(json['doors']) : null,
      seatBelts: json['seatBelts'] != null ? SeatBeltStatus.fromJson(json['seatBelts']) : null,
      rawData: json,
    );
  }
}

class LocationData {
  final double latitude;
  final double longitude;
  final double? speed;
  final double? bearing;
  final double? altitude;

  LocationData({
    required this.latitude,
    required this.longitude,
    this.speed,
    this.bearing,
    this.altitude,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      speed: json['speed']?.toDouble(),
      bearing: json['bearing']?.toDouble(),
      altitude: json['altitude']?.toDouble(),
    );
  }
}

class DoorStatus {
  final bool driver;
  final bool passenger;
  final bool rear;
  final bool trunk;
  final bool anyOpen;

  DoorStatus({
    required this.driver,
    required this.passenger,
    required this.rear,
    required this.trunk,
    required this.anyOpen,
  });

  factory DoorStatus.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] ?? false;
    final passenger = json['passenger'] ?? false;
    final rear = json['rear'] ?? false;
    final trunk = json['trunk'] ?? false;
    final anyOpen = json['open'] ?? (driver || passenger || rear || trunk);

    return DoorStatus(
      driver: driver,
      passenger: passenger,
      rear: rear,
      trunk: trunk,
      anyOpen: anyOpen,
    );
  }
}

class SeatBeltStatus {
  final bool driver;
  final List<bool> passengers;
  final bool allFastened;

  SeatBeltStatus({
    required this.driver,
    required this.passengers,
    required this.allFastened,
  });

  factory SeatBeltStatus.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] ?? false;
    final passengers = (json['passengers'] as List?)?.cast<bool>() ?? [];
    final allFastened = json['fastened'] ?? (driver && passengers.every((belt) => belt));

    return SeatBeltStatus(
      driver: driver,
      passengers: passengers,
      allFastened: allFastened,
    );
  }
}
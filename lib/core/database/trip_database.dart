import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class TripDatabase {
  static Database? _database;
  static final TripDatabase _instance = TripDatabase._internal();
  
  factory TripDatabase() => _instance;
  TripDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'trip_database.db');
    
    return await openDatabase(
      path,
      version: 4, // Incremented version for release_note_number and container_number fields
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE active_trips(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_trip_id TEXT,
        vehicle_number TEXT NOT NULL,
        vehicle_uuid TEXT NOT NULL,
        route_uuid TEXT NOT NULL,
        route_name TEXT,
        schedule_uuid TEXT NOT NULL,
        release_note_number TEXT,
        container_number TEXT,
        engagement_timestamp INTEGER NOT NULL,
        start_trip_timestamp INTEGER,
        start_odometer REAL NOT NULL,
        end_odometer REAL,
        start_latitude REAL NOT NULL,
        start_longitude REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_trip_started INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE trip_locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        speed REAL DEFAULT 0,
        heading REAL DEFAULT 0,
        accuracy REAL DEFAULT 0,
        FOREIGN KEY (trip_id) REFERENCES active_trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_trip_locations_trip_id ON trip_locations(trip_id)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_trip_locations_timestamp ON trip_locations(timestamp)
    ''');
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    print('🔄 Upgrading trip database from version $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      // Add server_trip_id column to existing tables
      await db.execute('ALTER TABLE active_trips ADD COLUMN server_trip_id TEXT');
      print('✅ Added server_trip_id column to active_trips table');
    }
    
    if (oldVersion < 3) {
      // Add end_odometer column to existing tables
      await db.execute('ALTER TABLE active_trips ADD COLUMN end_odometer REAL');
      print('✅ Added end_odometer column to active_trips table');
    }
    
    if (oldVersion < 4) {
      // Add release_note_number and container_number columns
      await db.execute('ALTER TABLE active_trips ADD COLUMN release_note_number TEXT');
      await db.execute('ALTER TABLE active_trips ADD COLUMN container_number TEXT');
      print('✅ Added release_note_number and container_number columns to active_trips table');
    }
  }

  // Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

class ActiveTrip {
  final int? id;
  final String? serverTripId; // Server-generated trip ID (e.g., "DMT_68CBF35BB0609")
  final String vehicleNumber;
  final String vehicleUuid;
  final String routeUuid;
  final String? routeName;
  final String scheduleUuid;
  final String? releaseNoteNumber;
  final String? containerNumber;
  final DateTime engagementTimestamp;
  final DateTime? startTripTimestamp;
  final double startOdometer;
  final double? endOdometer;
  final double startLatitude;
  final double startLongitude;
  final bool isActive;
  final bool isTripStarted;
  final DateTime createdAt;
  final DateTime updatedAt;

  ActiveTrip({
    this.id,
    this.serverTripId,
    required this.vehicleNumber,
    required this.vehicleUuid,
    required this.routeUuid,
    this.routeName,
    required this.scheduleUuid,
    this.releaseNoteNumber,
    this.containerNumber,
    required this.engagementTimestamp,
    this.startTripTimestamp,
    required this.startOdometer,
    this.endOdometer,
    required this.startLatitude,
    required this.startLongitude,
    this.isActive = true,
    this.isTripStarted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_trip_id': serverTripId,
      'vehicle_number': vehicleNumber,
      'vehicle_uuid': vehicleUuid,
      'route_uuid': routeUuid,
      'route_name': routeName,
      'schedule_uuid': scheduleUuid,
      'release_note_number': releaseNoteNumber,
      'container_number': containerNumber,
      'engagement_timestamp': engagementTimestamp.millisecondsSinceEpoch,
      'start_trip_timestamp': startTripTimestamp?.millisecondsSinceEpoch,
      'start_odometer': startOdometer,
      'end_odometer': endOdometer,
      'start_latitude': startLatitude,
      'start_longitude': startLongitude,
      'is_active': isActive ? 1 : 0,
      'is_trip_started': isTripStarted ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ActiveTrip.fromMap(Map<String, dynamic> map) {
    return ActiveTrip(
      id: map['id']?.toInt(),
      serverTripId: map['server_trip_id'],
      vehicleNumber: map['vehicle_number'] ?? '',
      vehicleUuid: map['vehicle_uuid'] ?? '',
      routeUuid: map['route_uuid'] ?? '',
      routeName: map['route_name'],
      scheduleUuid: map['schedule_uuid'] ?? '',
      releaseNoteNumber: map['release_note_number'],
      containerNumber: map['container_number'],
      engagementTimestamp: DateTime.fromMillisecondsSinceEpoch(map['engagement_timestamp'] ?? 0),
      startTripTimestamp: map['start_trip_timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['start_trip_timestamp'])
          : null,
      startOdometer: (map['start_odometer'] ?? 0).toDouble(),
      endOdometer: map['end_odometer'] != null ? (map['end_odometer'] as num).toDouble() : null,
      startLatitude: (map['start_latitude'] ?? 0).toDouble(),
      startLongitude: (map['start_longitude'] ?? 0).toDouble(),
      isActive: (map['is_active'] ?? 1) == 1,
      isTripStarted: (map['is_trip_started'] ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] ?? 0),
    );
  }

  // Calculate elapsed time from engagement (always counting)
  Duration get elapsedTimeFromEngagement => DateTime.now().difference(engagementTimestamp);
  
  // Calculate elapsed time from trip start (only if trip actually started)
  Duration get elapsedTimeFromTripStart {
    if (startTripTimestamp == null) return Duration.zero;
    return DateTime.now().difference(startTripTimestamp!);
  }
  
  int get elapsedSecondsFromEngagement => elapsedTimeFromEngagement.inSeconds;
  int get elapsedSecondsFromTripStart => elapsedTimeFromTripStart.inSeconds;
  
  ActiveTrip copyWith({
    int? id,
    String? serverTripId,
    String? vehicleNumber,
    String? vehicleUuid,
    String? routeUuid,
    String? routeName,
    String? scheduleUuid,
    String? releaseNoteNumber,
    String? containerNumber,
    DateTime? engagementTimestamp,
    DateTime? startTripTimestamp,
    double? startOdometer,
    double? endOdometer,
    double? startLatitude,
    double? startLongitude,
    bool? isActive,
    bool? isTripStarted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ActiveTrip(
      id: id ?? this.id,
      serverTripId: serverTripId ?? this.serverTripId,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleUuid: vehicleUuid ?? this.vehicleUuid,
      routeUuid: routeUuid ?? this.routeUuid,
      routeName: routeName ?? this.routeName,
      scheduleUuid: scheduleUuid ?? this.scheduleUuid,
      releaseNoteNumber: releaseNoteNumber ?? this.releaseNoteNumber,
      containerNumber: containerNumber ?? this.containerNumber,
      engagementTimestamp: engagementTimestamp ?? this.engagementTimestamp,
      startTripTimestamp: startTripTimestamp ?? this.startTripTimestamp,
      startOdometer: startOdometer ?? this.startOdometer,
      endOdometer: endOdometer ?? this.endOdometer,
      startLatitude: startLatitude ?? this.startLatitude,
      startLongitude: startLongitude ?? this.startLongitude,
      isActive: isActive ?? this.isActive,
      isTripStarted: isTripStarted ?? this.isTripStarted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

class TripLocation {
  final int? id;
  final int tripId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double speed;
  final double heading;
  final double accuracy;

  TripLocation({
    this.id,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed = 0,
    this.heading = 0,
    this.accuracy = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
    };
  }

  factory TripLocation.fromMap(Map<String, dynamic> map) {
    return TripLocation(
      id: map['id']?.toInt(),
      tripId: map['trip_id']?.toInt() ?? 0,
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      speed: (map['speed'] ?? 0).toDouble(),
      heading: (map['heading'] ?? 0).toDouble(),
      accuracy: (map['accuracy'] ?? 0).toDouble(),
    );
  }
}
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:geolocator/geolocator.dart';
import '../database/trip_database.dart';

class TripPersistenceService {
  static final TripPersistenceService _instance = TripPersistenceService._internal();
  factory TripPersistenceService() => _instance;
  TripPersistenceService._internal();

  final TripDatabase _tripDatabase = TripDatabase();
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStream;

  // Save vehicle engagement (not yet trip started)
  Future<int> saveVehicleEngagement({
    required String vehicleNumber,
    required String vehicleUuid,
    required String routeUuid,
    String? routeName,
    required String scheduleUuid,
    required double startOdometer,
    required double startLatitude,
    required double startLongitude,
  }) async {
    try {
      print('🚗 Saving vehicle engagement to database...');
      final db = await _tripDatabase.database;
      
      // Clear any existing active engagements first
      await clearActiveTrips();
      
      // Create engagement record (trip not yet started)
      final activeTrip = ActiveTrip(
        vehicleNumber: vehicleNumber,
        vehicleUuid: vehicleUuid,
        routeUuid: routeUuid,
        routeName: routeName,
        scheduleUuid: scheduleUuid,
        engagementTimestamp: DateTime.now(), // This is when user engaged with vehicle
        startTripTimestamp: null, // Trip not started yet
        startOdometer: startOdometer,
        startLatitude: startLatitude,
        startLongitude: startLongitude,
        isActive: true,
        isTripStarted: false, // Just engaged, not started trip
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      // Insert engagement record
      final id = await db.insert(
        'active_trips',
        activeTrip.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('✅ Vehicle engagement saved with ID: $id');
      print('⏰ Engagement started at: ${activeTrip.engagementTimestamp}');
      
      return id;
    } catch (e) {
      print('❌ Error saving vehicle engagement: $e');
      rethrow;
    }
  }

  // Mark trip as officially started
  Future<void> markTripAsStarted(
    int tripId, {
    String? serverTripId,
    double? startOdometer,
    String? releaseNoteNumber,
    String? containerNumber,
  }) async {
    try {
      print('🚀 Marking trip as officially started...');
      final db = await _tripDatabase.database;
      
      final updateData = <String, dynamic>{
        'start_trip_timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_trip_started': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Add server trip ID if provided
      if (serverTripId != null) {
        updateData['server_trip_id'] = serverTripId;
        print('🆔 Setting server trip ID: $serverTripId');
      } else {
        print('⚠️ WARNING: serverTripId is null - not updating server_trip_id field');
      }
      
      // Add start odometer if provided
      if (startOdometer != null) {
        updateData['start_odometer'] = startOdometer;
        print('🚗 Updating start odometer to: $startOdometer');
      }
      
      // Add release note number if provided
      if (releaseNoteNumber != null) {
        updateData['release_note_number'] = releaseNoteNumber;
        print('📋 Setting release note number: $releaseNoteNumber');
      }
      
      // Add container number if provided
      if (containerNumber != null) {
        updateData['container_number'] = containerNumber;
        print('📦 Setting container number: $containerNumber');
      }
      
      print('📋 About to update with data: $updateData');
      final rowsUpdated = await db.update(
        'active_trips',
        updateData,
        where: 'id = ?',
        whereArgs: [tripId],
      );
      
      print('✅ Trip marked as started - $rowsUpdated row(s) updated');
      
      // Verify the update by reading back the record
      final verifyData = await db.query(
        'active_trips',
        where: 'id = ?',
        whereArgs: [tripId],
      );
      
      if (verifyData.isNotEmpty) {
        final updatedRecord = verifyData.first;
        print('� Verification - Updated record server_trip_id: ${updatedRecord['server_trip_id']}');
        print('🔍 Verification - Full record: $updatedRecord');
      } else {
        print('❌ ERROR: Could not find record with ID $tripId after update');
      }
      
      // Start location tracking now that trip is officially started
      await _startLocationTracking(tripId);
      
    } catch (e) {
      print('❌ Error marking trip as started: $e');
      rethrow;
    }
  }

  // Save active trip to database (for compatibility)
  Future<int> saveActiveTrip(ActiveTrip trip) async {
    try {
      print('💾 Saving active trip to database...');
      print('📋 Trip data - Release Note: ${trip.releaseNoteNumber}, Container: ${trip.containerNumber}');
      final db = await _tripDatabase.database;
      
      // Clear any existing active trips first
      await clearActiveTrips();
      
      // Get the map to see what's being saved
      final tripMap = trip.toMap();
      print('📋 Database map - release_note_number: ${tripMap['release_note_number']}, container_number: ${tripMap['container_number']}');
      
      // Insert new active trip
      final id = await db.insert(
        'active_trips',
        tripMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('✅ Active trip saved with ID: $id');
      
      // Verify what was actually saved
      final saved = await db.query('active_trips', where: 'id = ?', whereArgs: [id]);
      if (saved.isNotEmpty) {
        print('✅ Verified in DB - release_note_number: ${saved.first['release_note_number']}, container_number: ${saved.first['container_number']}');
      }
      
      // Start location tracking if trip is started
      if (trip.isTripStarted) {
        await _startLocationTracking(id);
      }
      
      return id;
    } catch (e) {
      print('❌ Error saving active trip: $e');
      rethrow;
    }
  }

  // Get current active trip
  Future<ActiveTrip?> getActiveTrip() async {
    try {
      final db = await _tripDatabase.database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        'active_trips',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'created_at DESC',
        limit: 1,
      );

      if (maps.isNotEmpty) {
        final trip = ActiveTrip.fromMap(maps.first);
        print('📍 Found active engagement: ${trip.vehicleNumber} engaged at ${trip.engagementTimestamp}');
        print('🆔 Server Trip ID: ${trip.serverTripId ?? "NULL"}');
        print('🚗 ACTIVE TRIP ODOMETER DEBUG - Start: ${trip.startOdometer}, End: ${trip.endOdometer ?? 'NULL'}');
        print('📊 Trip Status - Started: ${trip.isTripStarted}, Active: ${trip.isActive}');
        if (trip.isTripStarted && trip.startTripTimestamp != null) {
          print('🚀 Trip officially started at: ${trip.startTripTimestamp}');
        }
        return trip;
      }
      
      print('📭 No active trip found in database');
      return null;
    } catch (e) {
      print('❌ Error getting active trip: $e');
      return null;
    }
  }

  // Check if there's an active trip
  Future<bool> hasActiveTrip() async {
    final activeTrip = await getActiveTrip();
    return activeTrip != null;
  }

  // Clear all active trips
  Future<void> clearActiveTrips() async {
    try {
      print('🗑️ Clearing all active trips...');
      final db = await _tripDatabase.database;
      
      await db.update(
        'active_trips',
        {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'is_active = ?',
        whereArgs: [1],
      );
      
      // Stop location tracking
      await _stopLocationTracking();
      
      print('✅ All active trips cleared');
    } catch (e) {
      print('❌ Error clearing active trips: $e');
    }
  }

  // End specific trip
  Future<void> endTrip(int tripId) async {
    try {
      print('🏁 Ending trip with ID: $tripId');
      final db = await _tripDatabase.database;
      
      await db.update(
        'active_trips',
        {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [tripId],
      );
      
      // Stop location tracking
      await _stopLocationTracking();
      
      print('✅ Trip $tripId ended successfully');
    } catch (e) {
      print('❌ Error ending trip: $e');
    }
  }

  // Mark trip as ended but keep vehicle engagement for release
  Future<void> markTripAsEnded(int tripId, {double? endOdometer}) async {
    try {
      print('🏁 Marking trip as ended but keeping engagement: $tripId');
      final db = await _tripDatabase.database;
      
      final updateData = <String, dynamic>{
        'is_trip_started': 0, // Mark trip as not started (ended)
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Add end odometer if provided
      if (endOdometer != null) {
        updateData['end_odometer'] = endOdometer;
        print('🚗 STORING END ODOMETER: $endOdometer (Type: ${endOdometer.runtimeType})');
      } else {
        print('⚠️ WARNING: endOdometer is NULL - not updating end_odometer field');
      }
      
      await db.update(
        'active_trips',
        updateData,
        where: 'id = ?',
        whereArgs: [tripId],
      );
      
      // Stop location tracking
      await _stopLocationTracking();
      
      print('✅ Trip $tripId marked as ended, vehicle still engaged');
    } catch (e) {
      print('❌ Error marking trip as ended: $e');
    }
  }

  // Update end odometer for a trip
  Future<void> updateEndOdometer(int tripId, double endOdometer) async {
    try {
      print('🚗 Updating end odometer for trip $tripId to: $endOdometer');
      final db = await _tripDatabase.database;
      
      final rowsUpdated = await db.update(
        'active_trips',
        {
          'end_odometer': endOdometer,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [tripId],
      );
      
      print('✅ End odometer updated - $rowsUpdated row(s) affected');
    } catch (e) {
      print('❌ Error updating end odometer: $e');
      rethrow;
    }
  }
  
  // Update server trip ID for an existing trip
  Future<void> updateServerTripId(int tripId, String serverTripId) async {
    try {
      print('🔧 Updating server trip ID for trip $tripId to: $serverTripId');
      final db = await _tripDatabase.database;
      
      final rowsUpdated = await db.update(
        'active_trips',
        {
          'server_trip_id': serverTripId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [tripId],
      );
      
      print('✅ Server trip ID updated - $rowsUpdated row(s) affected');
    } catch (e) {
      print('❌ Error updating server trip ID: $e');
      rethrow;
    }
  }

  // Save location point for trip tracking
  Future<void> saveLocation(TripLocation location) async {
    try {
      final db = await _tripDatabase.database;
      
      await db.insert(
        'trip_locations',
        location.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('📍 Location saved: ${location.latitude}, ${location.longitude}');
    } catch (e) {
      print('❌ Error saving location: $e');
    }
  }

  // Get trip locations for analysis
  Future<List<TripLocation>> getTripLocations(int tripId, {int? limit}) async {
    try {
      final db = await _tripDatabase.database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        'trip_locations',
        where: 'trip_id = ?',
        whereArgs: [tripId],
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      return List.generate(maps.length, (i) {
        return TripLocation.fromMap(maps[i]);
      });
    } catch (e) {
      print('❌ Error getting trip locations: $e');
      return [];
    }
  }

  // Start continuous location tracking for active trip
  Future<void> _startLocationTracking(int tripId) async {
    try {
      print('📍 Starting location tracking for trip $tripId...');
      
      // Check location permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Location permissions are permanently denied');
        return;
      }

      // Configure location settings for high accuracy
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      // Start location stream
      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) async {
        // Save location to database
        final location = TripLocation(
          tripId: tripId,
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now(),
          speed: position.speed,
          heading: position.heading,
          accuracy: position.accuracy,
        );
        
        await saveLocation(location);
      });

      print('✅ Location tracking started successfully');
      
    } catch (e) {
      print('❌ Error starting location tracking: $e');
    }
  }

  // Stop location tracking
  Future<void> _stopLocationTracking() async {
    try {
      print('📍 Stopping location tracking...');
      
      _positionStream?.cancel();
      _positionStream = null;
      
      _locationTimer?.cancel();
      _locationTimer = null;
      
      print('✅ Location tracking stopped');
    } catch (e) {
      print('❌ Error stopping location tracking: $e');
    }
  }

  // Get trip statistics
  Future<Map<String, dynamic>> getTripStats(int tripId) async {
    try {
      // First try to get odometer-based distance from specific trip
      double odometerDistance = 0.0;
      
      // Query the specific trip by ID to get odometer readings
      final db = await _tripDatabase.database;
      final tripData = await db.query(
        'active_trips',
        where: 'id = ?',
        whereArgs: [tripId],
        limit: 1,
      );
      
      if (tripData.isNotEmpty) {
        final trip = ActiveTrip.fromMap(tripData.first);
        print('🚗 TRIP STATS DEBUG - Trip ID: $tripId');
        print('   - Start Odometer: ${trip.startOdometer}');
        print('   - End Odometer: ${trip.endOdometer ?? 'NULL'}');
        print('   - Is Trip Started: ${trip.isTripStarted}');
        
        if (trip.endOdometer != null && trip.startOdometer > 0) {
          // Use odometer readings for accurate distance (convert km to meters)
          odometerDistance = (trip.endOdometer! - trip.startOdometer) * 1000;
          print('📏 CALCULATED odometer distance: ${trip.endOdometer! - trip.startOdometer} km (${odometerDistance} meters)');
        } else {
          print('⚠️ WARNING: Cannot calculate odometer distance - endOdometer: ${trip.endOdometer}, startOdometer: ${trip.startOdometer}');
        }
      }
      
      // Get GPS tracking data for speed statistics
      final locations = await getTripLocations(tripId);
      
      if (locations.isEmpty) {
        return {
          'totalDistance': odometerDistance, // Use odometer if available, otherwise 0
          'averageSpeed': 0.0,
          'maxSpeed': 0.0,
          'locationCount': 0,
        };
      }

      // Calculate GPS-based distance as fallback
      double gpsDistance = 0.0;
      double totalSpeed = 0.0;
      double maxSpeed = 0.0;

      for (int i = 0; i < locations.length - 1; i++) {
        final current = locations[i];
        final next = locations[i + 1];
        
        // Calculate distance between consecutive points
        final distance = Geolocator.distanceBetween(
          current.latitude,
          current.longitude,
          next.latitude,
          next.longitude,
        );
        
        gpsDistance += distance;
        totalSpeed += current.speed;
        maxSpeed = current.speed > maxSpeed ? current.speed : maxSpeed;
      }

      // Use odometer distance if available and reasonable, otherwise use GPS distance
      double finalDistance = odometerDistance;
      if (odometerDistance <= 0 || odometerDistance > gpsDistance * 10) {
        // Fall back to GPS distance if odometer seems unreasonable
        finalDistance = gpsDistance;
        print('📏 Using GPS distance fallback: ${gpsDistance} meters');
      }

      return {
        'totalDistance': finalDistance, // in meters - preferring odometer accuracy
        'averageSpeed': locations.isNotEmpty ? totalSpeed / locations.length : 0.0, // m/s
        'maxSpeed': maxSpeed, // m/s
        'locationCount': locations.length,
        'odometerDistance': odometerDistance, // in meters
        'gpsDistance': gpsDistance, // in meters
      };
    } catch (e) {
      print('❌ Error calculating trip stats: $e');
      return {
        'totalDistance': 0.0,
        'averageSpeed': 0.0,
        'maxSpeed': 0.0,
        'locationCount': 0,
        'odometerDistance': 0.0,
        'gpsDistance': 0.0,
      };
    }
  }

  // Initialize service - call this on app startup
  Future<void> initialize() async {
    try {
      print('🔧 Initializing TripPersistenceService...');
      
      // Check if there's an active trip and resume location tracking
      final activeTrip = await getActiveTrip();
      if (activeTrip != null) {
        print('📍 Resuming location tracking for existing trip: ${activeTrip.vehicleNumber}');
        await _startLocationTracking(activeTrip.id!);
      }
      
      print('✅ TripPersistenceService initialized');
    } catch (e) {
      print('❌ Error initializing TripPersistenceService: $e');
    }
  }

  // Dispose service
  Future<void> dispose() async {
    await _stopLocationTracking();
    await _tripDatabase.close();
  }
}
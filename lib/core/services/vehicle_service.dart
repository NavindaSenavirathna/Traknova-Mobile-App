import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:drive_master_app/core/services/auth_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'trip_persistence_service.dart';
import 'trip_tracking_service.dart';
import 'amq_service.dart';
import 'locator.dart';
import '../database/trip_database.dart';
import '../models/amq_models.dart';

class VehicleService {
  final ApiService _apiService;
  final TripPersistenceService _tripPersistence;
  final TripTrackingService _tripTracking;
  final AmqService _amqService = AmqService();
  
  // Timer for foreground drop point calls
  Timer? _dropPointTimer;
  bool _isAppInForeground = true; // Assume foreground initially

  VehicleService(this._apiService, this._tripPersistence, this._tripTracking);

  // Get schedules from the API
  Future<List<Schedule>> getSchedules() async {
    try {
      print('📅 Fetching schedules...');

      final response =
          await _apiService.get('/ext/drive-master/api/v1/index/schedules');

      print('📥 Schedules response status: ${response.statusCode}');
      print('📥 Schedules response body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonData = json.decode(response.body);

        if (jsonData['status'] == 200 && jsonData['result'] != null) {
          return (jsonData['result'] as List)
              .map((schedule) => Schedule.fromJson(schedule))
              .toList();
        } else {
          throw VehicleEngagementException('Invalid schedules response format');
        }
      } else {
        throw VehicleEngagementException(
            'Failed to fetch schedules (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Schedules fetch error: $e');
      if (e is VehicleEngagementException) {
        rethrow;
      }
      throw VehicleEngagementException(
          'Network error while fetching schedules: $e');
    }
  }

  // Engage vehicle after QR code scan
  Future<VehicleEngagementResponse> engageVehicle(String vehicleNumber, {String? scheduleUuid}) async {
    try {
      final requestBody = {
        'vehicleUuid':
            vehicleNumber, // API expects vehicleUuid, not vehicleNumber
        "scheduleUuid": scheduleUuid ?? "DMRS_68CBE78E38090" // Use provided scheduleUuid or default
      };

      print('🚗 Engaging vehicle: $vehicleNumber');
      print('📤 Request body: ${json.encode(requestBody)}');

      final response = await _apiService.post(
        '/ext/drive-master/api/v1/vehicle/engage-vehicle',
        body: requestBody,
      );

      print('📥 Vehicle engagement response status: ${response.statusCode}');
      print('📥 Vehicle engagement response body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonData = json.decode(response.body);

        // Debug: Log JSON structure
        print('🔍 JSON Structure Debug:');
        print('   - Root keys: ${jsonData.keys.toList()}');
        if (jsonData['content'] != null) {
          final content = jsonData['content'] as Map<String, dynamic>;
          print('   - Content keys: ${content.keys.toList()}');
          if (content['vehicle'] != null) {
            final vehicle = content['vehicle'] as Map<String, dynamic>;
            print('   - Vehicle keys: ${vehicle.keys.toList()}');
            print('   - Vehicle data: $vehicle');
          }
          if (content['schedules'] != null) {
            final schedules = content['schedules'] as List;
            print('   - Schedules count: ${schedules.length}');
            if (schedules.isNotEmpty) {
              print(
                  '   - First schedule keys: ${(schedules.first as Map<String, dynamic>).keys.toList()}');
              print('   - First schedule data: ${schedules.first}');
            }
          }
        }

        return VehicleEngagementResponse.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw VehicleEngagementException(
            'Authentication failed. Please login again. (${response.statusCode}): ${response.body}');
      } else {
        throw VehicleEngagementException(
            'Vehicle engagement failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Vehicle engagement error: $e');
      if (e is VehicleEngagementException) {
        rethrow;
      }
      throw VehicleEngagementException(
          'Network error during vehicle engagement: $e');
    }
  }

  // Save vehicle engagement to local database (when QR is scanned and vehicle is engaged)
  Future<int> saveVehicleEngagementToLocal({
    required String vehicleNumber,
    required String vehicleUuid,
    required String routeUuid,
    String? routeName,
    required String scheduleUuid,
    required String odometerReading,
    double? latitude,
    double? longitude,
  }) async {
    try {
      print('🚗 Saving vehicle engagement to local database...');

      // Get live location if not provided
      double engagementLatitude;
      double engagementLongitude;
      
      if (latitude != null && longitude != null) {
        // Use provided coordinates
        engagementLatitude = latitude;
        engagementLongitude = longitude;
        print('🗺️ Using provided location for engagement: $latitude, $longitude');
      } else {
        // Get live location from device
        try {
          print('📍 Getting live location for vehicle engagement...');
          final currentLocation = await _getCurrentLocation();
          if (currentLocation != null) {
            engagementLatitude = currentLocation['latitude']!;
            engagementLongitude = currentLocation['longitude']!;
            print('✅ Live location obtained for engagement: $engagementLatitude, $engagementLongitude');
          } else {
            throw Exception('Failed to get current location');
          }
        } catch (locationError) {
          print('❌ Failed to get live location for engagement: $locationError');
          throw Exception(
              'Unable to get current location for vehicle engagement. Please ensure GPS is enabled and location permissions are granted.');
        }
      }

      final engagementId = await _tripPersistence.saveVehicleEngagement(
        vehicleNumber: vehicleNumber,
        vehicleUuid: vehicleUuid,
        routeUuid: routeUuid,
        routeName: routeName,
        scheduleUuid: scheduleUuid,
        startOdometer: double.tryParse(odometerReading) ?? 0.0,
        startLatitude: engagementLatitude,
        startLongitude: engagementLongitude,
      );

      print('✅ Vehicle engagement saved with ID: $engagementId');
      print('⏰ Timer will start counting from engagement time');

      return engagementId;
    } catch (e) {
      print('❌ Error saving vehicle engagement: $e');
      rethrow;
    }
  }

  // Get active trip status
  Future<ActiveTripResponse> getActiveTrip() async {
    try {
      print('🔍 Checking for active trip...');

      final response =
          await _apiService.get('/ext/drive-master/api/v1/trip/active');

      print('📥 Active trip response status: ${response.statusCode}');
      print('📥 Active trip response body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonData = json.decode(response.body);
        return ActiveTripResponse.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw VehicleEngagementException(
            'Authentication failed. Please login again. (${response.statusCode}): ${response.body}');
      } else {
        throw VehicleEngagementException(
            'Failed to get active trip (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Get active trip error: $e');
      if (e is VehicleEngagementException) {
        rethrow;
      }
      throw VehicleEngagementException(
          'Network error while getting active trip: $e');
    }
  }

  // Start trip after vehicle engagement with proper flow
  // Updated API format includes: releaseNoteNumber, containerNumber, startOdoValue (instead of startOdometer)
  Future<TripStartResponse> startTrip({
    required String vehicleNumber,
    required String vehicleUuid,
    required String routeUuid,
    required String odometerReading,
    required String scheduleUuid,
    double? latitude,
    double? longitude,
    String? releaseNoteNumber, // New optional field for release note number
    String? containerNumber,   // New optional field for container number
  }) async {
    try {
      print('🚀 Starting trip flow for vehicle: $vehicleNumber');

      // Step 1: Check local database for existing active trip first
      print('🔍 Step 1: Checking local database for active trip...');
      final localActiveTrip = await _tripPersistence.getActiveTrip();

      if (localActiveTrip != null) {
        print(
            '⚠️ Found existing engagement/trip in local database: ${localActiveTrip.vehicleNumber}');
        print('🔍 Trip started status: ${localActiveTrip.isTripStarted}');

        // Only return early if the trip is actually started (not just engaged)
        if (localActiveTrip.isTripStarted) {
          print('✅ Trip already started, returning existing trip response');
          return TripStartResponse(
            status: 200,
            result: TripResult(
              status: true,
              message: 'Trip already active - continuing from local database',
              statusCode: 200,
            ),
          );
        } else {
          print(
              'ℹ️ Vehicle engaged but trip not started, proceeding with trip initiation on server...');
          // Continue with trip initiation process
        }
      }

      // Step 2: Check API for active trip as backup
      print('🔍 Step 2: Checking API for active trip...');
      final activeTrip = await getActiveTrip();

      if (activeTrip.hasActiveTrip) {
        print('⚠️ Active trip found on server but not in local database');
        // This suggests the app was reinstalled or data was cleared
        // We could try to sync with the server trip here
        throw VehicleEngagementException(
            'There is already an active trip on the server. Please end the current trip first.');
      }

      print(
          '✅ No active trip found locally or on server, proceeding with trip initiation');

      // Step 2: Get current location for trip initiation
      Map<String, double> startLocation;
      if (latitude != null && longitude != null) {
        // Use provided coordinates
        startLocation = {
          'latitude': latitude,
          'longitude': longitude,
        };
        print('🗺️ Using provided location: $latitude, $longitude');
      } else {
        // Get live location from device
        try {
          print('📍 Getting live location for trip start...');
          final currentLocation = await _getCurrentLocation();
          if (currentLocation != null) {
            startLocation = currentLocation;
            print('✅ Live location obtained: ${startLocation['latitude']}, ${startLocation['longitude']}');
          } else {
            throw Exception('Failed to get current location');
          }
        } catch (locationError) {
          print('❌ Failed to get live location for trip start: $locationError');
          throw VehicleEngagementException(
              'Unable to get current location for trip start. Please ensure GPS is enabled and location permissions are granted, then try again.');
        }
      }

      // Step 3: Prepare request body for trip initiation (matching API structure)
      final requestBody = {
        'routeId': routeUuid,
        'vehicleUuid': vehicleUuid.isNotEmpty
            ? vehicleUuid
            : vehicleNumber, // Use vehicleNumber as UUID if vehicleUuid is empty
        'scheduleId': scheduleUuid.isNotEmpty
            ? scheduleUuid
            : 'DMRS_68CBE78E38090', // Use default if empty
        'releaseNoteNumber': releaseNoteNumber ?? 'RN-2025-0001', // User input or default release note number
        'containerNumber': containerNumber ?? 'CONT-DEFAULT001', // User input or default container number
        'startLocation': {
          'latitude': startLocation['latitude'],
          'longitude': startLocation['longitude']
        },
        'startOdoValue': double.tryParse(odometerReading) ?? 0.0, // Changed from startOdometer to startOdoValue
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      print('🚀 Trip initiation request body (Updated API format): ${json.encode(requestBody)}');
      print("meka thama body eka: ${requestBody}");
      print('📋 Request Details:');
      print('   - releaseNoteNumber: ${requestBody['releaseNoteNumber']}');
      print('   - containerNumber: ${requestBody['containerNumber']}');
      // Step 3: Call trip initiation API (Updated format with releaseNoteNumber, containerNumber, startOdoValue)
      final AuthService authService = locator.get<AuthService>();
      final headers = await authService.getAuthHeaders();
      final uri = Uri.parse('http://192.168.8.165:8000/ext/drive-master/api/v1/trip/initiate');
      
      print('🌐 Trip Initiate API POST to: $uri');
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      print('📥 Trip initiation response status: ${response.statusCode}');
      print('📥 Trip initiation response body: ${response.body}');
      
      // ═══════════════════════════════════════════════════════════
      // 🔍 BACKEND API FIELD VERIFICATION TEST
      // ═══════════════════════════════════════════════════════════
      print('\n═══════════════════════════════════════════════════════════');
      print('🧪 TESTING: Does backend API store & return new fields?');
      print('═══════════════════════════════════════════════════════════');
      
      try {
        final responseJson = json.decode(response.body);
        print('✅ Response is valid JSON');
        
        // Log entire response structure
        print('\n📋 FULL RESPONSE STRUCTURE:');
        print(json.encode(responseJson));
        
        // Check what we sent vs what we got back
        print('\n📤 WHAT WE SENT TO API:');
        print('   - releaseNoteNumber: ${requestBody['releaseNoteNumber']}');
        print('   - containerNumber: ${requestBody['containerNumber']}');
        
        print('\n📥 WHAT API RETURNED:');
        
        // Check top level
        if (responseJson['releaseNoteNumber'] != null) {
          print('   ✅ Found at TOP LEVEL:');
          print('      - releaseNoteNumber: ${responseJson['releaseNoteNumber']}');
        }
        if (responseJson['containerNumber'] != null) {
          print('      - containerNumber: ${responseJson['containerNumber']}');
        }
        
        // Check result level
        if (responseJson['result'] != null) {
          final result = responseJson['result'];
          print('   📦 Checking result object...');
          
          if (result['releaseNoteNumber'] != null || result['containerNumber'] != null) {
            print('   ✅ Found in RESULT:');
            print('      - releaseNoteNumber: ${result['releaseNoteNumber']}');
            print('      - containerNumber: ${result['containerNumber']}');
          }
          
          // Check result.content level
          if (result['content'] != null) {
            final content = result['content'];
            print('   📦 Checking result.content object...');
            
            if (content['releaseNoteNumber'] != null || content['containerNumber'] != null) {
              print('   ✅ Found in RESULT.CONTENT:');
              print('      - releaseNoteNumber: ${content['releaseNoteNumber']}');
              print('      - containerNumber: ${content['containerNumber']}');
            } else {
              print('   ❌ NOT FOUND in result.content');
              print('   📋 Available fields in content: ${content.keys.toList()}');
            }
          } else {
            print('   ⚠️ result.content is NULL');
          }
        } else {
          print('   ⚠️ result object is NULL');
        }
        
        // Final verdict
        print('\n🎯 VERDICT:');
        bool foundInResponse = false;
        String location = '';
        
        if (responseJson['releaseNoteNumber'] != null) {
          foundInResponse = true;
          location = 'top level';
        } else if (responseJson['result']?['releaseNoteNumber'] != null) {
          foundInResponse = true;
          location = 'result object';
        } else if (responseJson['result']?['content']?['releaseNoteNumber'] != null) {
          foundInResponse = true;
          location = 'result.content';
        }
        
        if (foundInResponse) {
          print('   ✅ Backend IS storing and returning the new fields!');
          print('   📍 Found in: $location');
        } else {
          print('   ❌ Backend is NOT returning the new fields!');
          print('   ⚠️  This means:');
          print('      1. Backend API received the fields (we sent them)');
          print('      2. BUT backend did NOT save them to database');
          print('      3. OR backend saved them but not returning in response');
          print('   🔧 Backend developer needs to update the API endpoint!');
        }
        
      } catch (e) {
        print('❌ Error parsing response: $e');
      }
      
      print('═══════════════════════════════════════════════════════════\n');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonData = json.decode(response.body);
        final tripResponse = TripStartResponse.fromJson(jsonData);

        if (tripResponse.isSuccess) {
          print('✅ Trip started successfully on server');
          print('🔍 Full API Response: ${json.encode(jsonData)}');
          print(
              '🔍 TripResult: status=${tripResponse.result?.status}, message=${tripResponse.result?.message}');

          // Initialize AMQ connection if liveAmq config is available
          await _initializeAmqConnection(jsonData);

          // Get server trip ID from TripResult (which now correctly extracts from content.tripUuid)
          var serverTripId = tripResponse.result?.tripId;
          print('📋 Server trip ID from TripResult: $serverTripId');

          // If TripResult didn't extract it, try additional locations as fallback
          if (serverTripId == null) {
            // Try direct response fields
            serverTripId = jsonData['tripId'] ?? jsonData['trip_id'] ?? jsonData['id'];
            
            // Try in result.content (this should now be handled by TripResult.fromJson)
            if (serverTripId == null && jsonData['result'] != null && jsonData['result']['content'] != null) {
              final content = jsonData['result']['content'] as Map<String, dynamic>;
              serverTripId = content['tripUuid'] ?? content['tripId'] ?? content['trip_id'];
              print('📋 Found tripUuid in result.content: $serverTripId');
            }
          }

          // If still no trip ID, generate one based on timestamp and vehicle info
          if (serverTripId == null) {
            final timestamp =
                DateTime.now().millisecondsSinceEpoch.toString().substring(5);
            serverTripId =
                'DMT_$timestamp${vehicleUuid.substring(vehicleUuid.length - 3)}';
            print('📋 Generated fallback trip ID: $serverTripId');
          }

          print(
              '🎯 FINAL SERVER TRIP ID to use: $serverTripId'); // Step 4: Check if we already have an engagement, if not create one
          print('🔍 Checking for existing engagement...');
          var existingTrip = await _tripPersistence.getActiveTrip();

          if (existingTrip != null && !existingTrip.isTripStarted) {
            // We have an engagement, now mark trip as officially started and update with server trip ID and odometer
            print(
                '✅ Found existing engagement, marking trip as started with server ID and odometer');
            print(
                '🎯 Calling markTripAsStarted with ID: ${existingTrip.id}, serverTripId: $serverTripId, odometer: ${double.tryParse(odometerReading) ?? 0.0}');
            print('📋 Release Note: $releaseNoteNumber, Container: $containerNumber');
            await _tripPersistence.markTripAsStarted(
              existingTrip.id!,
              serverTripId: serverTripId,
              startOdometer: double.tryParse(odometerReading) ?? 0.0,
              releaseNoteNumber: releaseNoteNumber,
              containerNumber: containerNumber,
            );
            // Reload the updated trip
            existingTrip = await _tripPersistence.getActiveTrip();
            print(
                '🔍 After reload - trip serverTripId: ${existingTrip?.serverTripId}, startOdometer: ${existingTrip?.startOdometer}');
          } else {
            // No engagement found, create complete trip record
            print('💾 Creating new trip record...');
            print('📋 Release Note Number: $releaseNoteNumber');
            print('📋 Container Number: $containerNumber');
            final activeTrip = ActiveTrip(
              serverTripId: serverTripId,
              vehicleNumber: vehicleNumber,
              vehicleUuid: vehicleUuid,
              routeUuid: routeUuid,
              scheduleUuid: scheduleUuid,
              releaseNoteNumber: releaseNoteNumber,
              containerNumber: containerNumber,
              engagementTimestamp:
                  DateTime.now(), // Both engagement and trip start at same time
              startTripTimestamp: DateTime.now(),
              startOdometer: double.tryParse(odometerReading) ?? 0.0,
              startLatitude: startLocation['latitude']!,
              startLongitude: startLocation['longitude']!,
              isTripStarted: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

            final tripId = await _tripPersistence.saveActiveTrip(activeTrip);
            print('✅ Trip saved to local database with ID: $tripId');
            print('✅ Saved with Release Note: ${activeTrip.releaseNoteNumber}, Container: ${activeTrip.containerNumber}');
            existingTrip = activeTrip.copyWith(id: tripId);
          }

          // Step 5: Set up sync callback and start background tracking service
          print(
              '🚀 Setting up trip sync and starting background tracking service...');
          if (existingTrip != null) {
            // Set the sync callback for the trip tracking service
            _tripTracking.setSyncCallback(syncTripRecords);

            final serviceStarted =
                await _tripTracking.startTripTracking(existingTrip);

            if (serviceStarted) {
              print('✅ Background tracking service started successfully');
              print('🔄 Trip sync will occur every 5 seconds');
            } else {
              print('⚠️ Failed to start background tracking service');
            }

            // Start foreground drop point timer
            _startForegroundDropPointTimer();
            print('📍 Foreground drop point timer started (5-second interval)');
          }
        } else {
          print(
              '⚠️ Trip initiation response indicates failure: ${tripResponse.message}');
          // Handle specific error cases
          if (tripResponse.result?.statusCode == 400) {
            print('❌ Bad request: ${tripResponse.message}');
            // Still return the response so the UI can show the specific message
          }
        }

        return tripResponse;
      } else if (response.statusCode == 401) {
        throw VehicleEngagementException(
            'Authentication failed. Please login again. (${response.statusCode}): ${response.body}');
      } else if (response.statusCode == 400) {
        // Parse the error message from response body
        final jsonData = json.decode(response.body);
        final errorMessage = jsonData['message'] ?? 'Bad request';

        print('❌ Bad request error: $errorMessage');

        // Check if the error is about vehicle already being engaged
        if (errorMessage.toLowerCase().contains('already engaged') ||
            errorMessage.toLowerCase().contains('vehicle is already engaged')) {
          print(
              '🔍 Detected vehicle engagement conflict, attempting to resolve...');

          // Try to release the vehicle first and then retry
          try {
            print('🚗 Attempting to release vehicle: $vehicleUuid');
            final releaseSuccess = await releaseVehicle(
              vehicleUuid: vehicleUuid.isNotEmpty ? vehicleUuid : vehicleNumber,
              finalOdometer: double.tryParse(odometerReading) ?? 0.0,
              releaseReason: 'ENGAGEMENT_CONFLICT_RESOLUTION',
            );

            if (releaseSuccess) {
              print(
                  '✅ Vehicle released successfully, retrying trip initiation...');
              // Wait a moment for server state to update
              await Future.delayed(const Duration(seconds: 2));

              // Retry the trip initiation request
              final AuthService retryAuthService = locator.get<AuthService>();
              final retryHeaders = await retryAuthService.getAuthHeaders();
              final retryUri = Uri.parse('http://192.168.8.165:8000/ext/drive-master/api/v1/trip/initiate');
              
              print('🌐 Retry Trip Initiate API POST to: $retryUri');
              final retryResponse = await http.post(
                retryUri,
                headers: retryHeaders,
                body: json.encode(requestBody),
              ).timeout(const Duration(seconds: 30));

              print(
                  '📥 Retry trip initiation response status: ${retryResponse.statusCode}');
              print(
                  '📥 Retry trip initiation response body: ${retryResponse.body}');

              if (retryResponse.statusCode >= 200 &&
                  retryResponse.statusCode < 300) {
                final retryJsonData = json.decode(retryResponse.body);
                final retryTripResponse =
                    TripStartResponse.fromJson(retryJsonData);

                if (retryTripResponse.isSuccess) {
                  print('✅ Trip initiated successfully after vehicle release');

                  // Get server trip ID using same logic as main flow
                  var serverTripId = retryTripResponse.result?.tripId;
                  if (serverTripId == null) {
                    // Try direct response fields
                    serverTripId = retryJsonData['tripId'] ?? retryJsonData['trip_id'] ?? retryJsonData['id'];
                    
                    // Try in result.content
                    if (serverTripId == null && retryJsonData['result'] != null && retryJsonData['result']['content'] != null) {
                      final content = retryJsonData['result']['content'] as Map<String, dynamic>;
                      serverTripId = content['tripUuid'] ?? content['tripId'] ?? content['trip_id'];
                      print('📋 Found tripUuid in retry result.content: $serverTripId');
                    }
                  }
                  if (serverTripId == null) {
                    final timestamp = DateTime.now()
                        .millisecondsSinceEpoch
                        .toString()
                        .substring(5);
                    serverTripId =
                        'DMT_$timestamp${vehicleUuid.substring(vehicleUuid.length - 3)}';
                  }

                  // Create new trip record since we released the previous engagement
                  print('💾 Creating new trip record after vehicle release...');
                  final activeTrip = ActiveTrip(
                    serverTripId: serverTripId,
                    vehicleNumber: vehicleNumber,
                    vehicleUuid: vehicleUuid,
                    routeUuid: routeUuid,
                    scheduleUuid: scheduleUuid,
                    releaseNoteNumber: releaseNoteNumber,
                    containerNumber: containerNumber,
                    engagementTimestamp: DateTime.now(),
                    startTripTimestamp: DateTime.now(),
                    startOdometer: double.tryParse(odometerReading) ?? 0.0,
                    startLatitude: startLocation['latitude']!,
                    startLongitude: startLocation['longitude']!,
                    isTripStarted: true,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );

                  final tripId =
                      await _tripPersistence.saveActiveTrip(activeTrip);
                  print('✅ New trip saved to local database with ID: $tripId');

                  // Start background tracking service
                  final updatedTrip = activeTrip.copyWith(id: tripId);
                  _tripTracking.setSyncCallback(syncTripRecords);
                  final serviceStarted =
                      await _tripTracking.startTripTracking(updatedTrip);

                  if (serviceStarted) {
                    print('✅ Background tracking service started successfully');
                  }

                  // Start foreground drop point timer for retry case
                  _startForegroundDropPointTimer();
                  print('📍 Foreground drop point timer started (5-second interval)');

                  return retryTripResponse;
                } else {
                  throw VehicleEngagementException(
                      'Trip initiation failed after vehicle release: ${retryTripResponse.message}');
                }
              } else {
                throw VehicleEngagementException(
                    'Trip initiation retry failed (${retryResponse.statusCode}): ${retryResponse.body}');
              }
            } else {
              throw VehicleEngagementException(
                  'Vehicle is already engaged with another driver. Failed to automatically release the vehicle.');
            }
          } catch (releaseError) {
            print('❌ Error during vehicle release and retry: $releaseError');
            throw VehicleEngagementException(
                'Vehicle is already engaged. Automatic recovery failed: $releaseError');
          }
        } else {
          throw VehicleEngagementException(
              'Trip initiation failed: $errorMessage');
        }
      } else {
        throw VehicleEngagementException(
            'Trip initiation failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Trip start error: $e');
      if (e is VehicleEngagementException) {
        rethrow;
      }
      throw VehicleEngagementException('Network error during trip start: $e');
    }
  }

  // Get current local active trip
  Future<ActiveTrip?> getLocalActiveTrip() async {
    try {
      final trip = await _tripPersistence.getActiveTrip();

      // If trip exists but has no server trip ID, try to fix it
      if (trip != null && trip.serverTripId == null) {
        print('⚠️ Found trip with NULL server trip ID, attempting to fix...');
        await _fixNullServerTripId(trip);
        // Return the updated trip
        return await _tripPersistence.getActiveTrip();
      }

      return trip;
    } catch (e) {
      print('❌ Error getting local active trip: $e');
      return null;
    }
  }

  // Helper method to fix NULL server trip IDs
  Future<void> _fixNullServerTripId(ActiveTrip trip) async {
    try {
      if (trip.id == null) return;

      // Generate a fallback server trip ID
      final timestamp =
          DateTime.now().millisecondsSinceEpoch.toString().substring(5);
      final fallbackTripId =
          'DMT_FIX_$timestamp${trip.vehicleUuid.length >= 3 ? trip.vehicleUuid.substring(trip.vehicleUuid.length - 3) : 'XXX'}';

      print('🔧 Fixing NULL server trip ID with: $fallbackTripId');

      // Update the database directly
      await _tripPersistence.updateServerTripId(trip.id!, fallbackTripId);

      print('✅ Server trip ID fixed successfully');
    } catch (e) {
      print('❌ Error fixing server trip ID: $e');
    }
  }

  // Check if there's a local active trip
  Future<bool> hasLocalActiveTrip() async {
    return await _tripPersistence.hasActiveTrip();
  }

  // Initialize trip services
  Future<void> initializeTripServices() async {
    try {
      await _tripPersistence.initialize();

      // Check for any orphaned vehicle engagements and clean them up
      await _checkAndCleanupOrphanedEngagements();
    } catch (e) {
      print('❌ Error initializing trip services: $e');
    }
  }

  // Check for orphaned vehicle engagements and clean them up
  Future<void> _checkAndCleanupOrphanedEngagements() async {
    try {
      print('🔍 Checking for orphaned vehicle engagements...');

      // Get local active trip
      final localTrip = await _tripPersistence.getActiveTrip();

      if (localTrip != null) {
        print('📱 Found local engagement: ${localTrip.vehicleNumber}');
        print('📱 Trip started status: ${localTrip.isTripStarted}');

        // IMPORTANT: Don't clean up post-trip engagements!
        // After a trip ends, vehicle remains engaged for release:
        // - isTripStarted = false (trip ended)
        // - is_active = 1 (vehicle still engaged, awaiting release)
        // - Server has no active trip (because trip ended)
        // This is the CORRECT state, not an orphaned engagement!

        if (!localTrip.isTripStarted) {
          print(
              '✅ Found post-trip engagement awaiting release - this is correct, not orphaned');
          print(
              '🚗 Vehicle ${localTrip.vehicleNumber} is engaged and ready for release');
          return; // Exit early - don't clean up post-trip engagements
        }

        // Only check server state for active trips (isTripStarted = true)
        try {
          final serverActiveTrip = await getActiveTrip();

          if (!serverActiveTrip.hasActiveTrip) {
            print('⚠️ Local active trip exists but no server trip found');
            print(
                '🧹 This appears to be a true orphaned engagement - cleaning up...');
            await _tripPersistence.clearActiveTrips();
            print('✅ Orphaned active trip cleaned up');
          } else {
            print('✅ Local and server states are in sync for active trip');
          }
        } catch (e) {
          print('⚠️ Could not check server state: $e');
          // Don't clean up if we can't verify server state
        }
      } else {
        print('📱 No local engagement found');
      }
    } catch (e) {
      print('❌ Error during orphaned engagement cleanup: $e');
    }
  }

  // Helper function to get current location
  Future<Map<String, double>?> _getCurrentLocation() async {
    try {
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('! Location services are disabled');
        throw Exception(
            'Location services are disabled. Please enable GPS in device settings.');
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        print('🔐 Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Location permissions denied');
          throw Exception(
              'Location permission denied. Please grant location access in app settings.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Location permissions permanently denied');
        throw Exception(
            'Location permission permanently denied. Please enable location access in app settings.');
      }

      print('📍 Getting current location...');
      // Get current position with timeout and fallback
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      print('✅ Location obtained: ${position.latitude}, ${position.longitude}, Speed: ${position.speed} m/s');
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'speed': position.speed, // Speed in meters per second from GPS
      };
    } catch (e) {
      print('❌ Error getting current location: $e');
      // Provide more specific error messages
      if (e.toString().contains('PERMISSION_DENIED')) {
        throw Exception(
            'Location permission denied. Please grant location access in app settings.');
      } else if (e.toString().contains('location service')) {
        throw Exception(
            'Location services are disabled. Please enable GPS in device settings.');
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException')) {
        throw Exception(
            'Location request timed out. Please check GPS signal and try again.');
      } else {
        throw Exception('Unable to get location: ${e.toString()}');
      }
    }
  }

  // Update trip status API call
  Future<bool> updateTripStatus({
    required String tripId,
    required int status, // 0: started/resume, 1: paused, 2: ended
    required int isPaused, // 0: not paused, 1: paused
    required String vehicleUuid,
    required String schedulingUuid,
  }) async {
    try {
      print('🔄 Updating trip status: status=$status, isPaused=$isPaused');

      // Get current location for trip status update
      Map<String, double> location;
      try {
        print('📍 Getting live location for trip status update...');
        final currentLocation = await _getCurrentLocation();
        if (currentLocation != null) {
          location = currentLocation;
          print('✅ Live location obtained for trip update: ${location['latitude']}, ${location['longitude']}');
        } else {
          throw Exception('Failed to get current location');
        }
      } catch (locationError) {
        print('❌ Failed to get live location for trip update: $locationError');
        throw Exception(
            'Unable to get current location for trip status update. Please ensure GPS is enabled and try again.');
      }

      // Prepare request body matching API specification
      final requestBody = {
        'tripId': tripId,
        'status': status,
        'isPaused': isPaused,
        'vehicleUuid': vehicleUuid,
        'schedulingUuid': schedulingUuid,
        'location': {
          'latitude': location['latitude'],
          'longitude': location['longitude'],
        }
      };

      print('📤 Trip status update request: ${json.encode(requestBody)}');

      // Make API call
      final response = await _apiService.put(
        '/ext/drive-master/api/v1/vehicle/trip-status',
        body: requestBody,
      );

      print('📥 Trip status response status: ${response.statusCode}');
      print('📥 Trip status response body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ Trip status updated successfully');
        return true;
      } else {
        print(
            '❌ Failed to update trip status: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error updating trip status: $e');
      return false;
    }
  }

  // Pause trip API call
  Future<bool> pauseTrip(ActiveTrip trip) async {
    try {
      String? tripId = trip.serverTripId;

      // If no server trip ID, try to get it from the latest trip data
      if (tripId == null) {
        print(
            '⚠️ No server trip ID available, attempting to refresh trip data...');
        final currentTrip = await getLocalActiveTrip();
        if (currentTrip != null && currentTrip.serverTripId != null) {
          tripId = currentTrip.serverTripId;
          print('✅ Found server trip ID from refreshed data: $tripId');
        }
      }

      // If still no trip ID, we cannot update server status
      if (tripId == null) {
        print('❌ Cannot pause trip on server - no server trip ID available');
        print(
            '   This means the trip was not properly started or synced with server');
        // Return false to indicate server update failed
        return false;
      }

      print('⏸️ Pausing trip with server ID: $tripId');
      final success = await updateTripStatus(
        tripId: tripId,
        status: 1, // Paused status
        isPaused: 1, // Is paused
        vehicleUuid: trip.vehicleUuid,
        schedulingUuid: trip.scheduleUuid,
      );

      if (success) {
        print('✅ Trip paused successfully on server');
      } else {
        print('❌ Failed to pause trip on server');
      }

      return success;
    } catch (e) {
      print('❌ Error pausing trip: $e');
      // Don't allow local pause if server call fails - we need database consistency
      return false;
    }
  }

  // Resume trip API call
  Future<bool> resumeTrip(ActiveTrip trip) async {
    try {
      String? tripId = trip.serverTripId;

      // If no server trip ID, try to get it from the latest trip data
      if (tripId == null) {
        print(
            '⚠️ No server trip ID available, attempting to refresh trip data...');
        final currentTrip = await getLocalActiveTrip();
        if (currentTrip != null && currentTrip.serverTripId != null) {
          tripId = currentTrip.serverTripId;
          print('✅ Found server trip ID from refreshed data: $tripId');
        }
      }

      // If still no trip ID, we cannot update server status
      if (tripId == null) {
        print('❌ Cannot resume trip on server - no server trip ID available');
        print(
            '   This means the trip was not properly started or synced with server');
        // Return false to indicate server update failed
        return false;
      }

      print('▶️ Resuming trip with server ID: $tripId');
      final success = await updateTripStatus(
        tripId: tripId,
        status: 0, // Active/resumed status
        isPaused: 0, // Not paused
        vehicleUuid: trip.vehicleUuid,
        schedulingUuid: trip.scheduleUuid,
      );

      if (success) {
        print('✅ Trip resumed successfully on server');
      } else {
        print('❌ Failed to resume trip on server');
      }

      return success;
    } catch (e) {
      print('❌ Error resuming trip: $e');
      // Don't allow local resume if server call fails - we need database consistency
      return false;
    }
  }

  // Sync trip records API call - called every 5 seconds during trip
  Future<bool> syncTripRecords({
    required String tripId,
    required String vehicleUuid,
    required String schedulingUuid,
    required List<TripLocation> locations,
    required ActiveTrip tripData,
  }) async {
    try {
      print('🔄 Syncing trip records for trip: $tripId');

      // Get current location for latest record
      Map<String, double>? currentLocation;
      try {
        currentLocation = await _getCurrentLocation();
      } catch (locationError) {
        print('⚠️ Could not get current location for sync: $locationError');
        currentLocation = null;
      }

      // Prepare sync records array according to API specification
      final List<Map<String, dynamic>> syncRecords = [];

      // Add historical locations from database
      for (final loc in locations) {
        syncRecords.add({
          'timestamp': loc.timestamp.toUtc().toIso8601String(),
          'location': {
            'latitude': loc.latitude,
            'longitude': loc.longitude,
            'accuracy': loc.accuracy,
            'speed': loc.speed,
            'bearing': loc.heading,
          },
          'odometer': tripData.startOdometer.toInt(),
          'fuelLevel':
              85.5, // Default value - update if you have fuel level data
          'engineStatus': 'RUNNING',
        });
      }

      // Add current location if available
      if (currentLocation != null) {
        syncRecords.add({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'location': {
            'latitude': currentLocation['latitude'],
            'longitude': currentLocation['longitude'],
            'accuracy': 5.0,
            'speed': currentLocation['speed'] ?? 0.0, // Use actual GPS speed from device
            'bearing': 0.0,
          },
          'odometer': tripData.startOdometer,
          'fuelLevel': 85.5, // Default value
          'engineStatus': 'RUNNING',
        });
      }

      // Prepare API request body according to specification
      final requestBody = {
        'tripId': tripId, // Note: API uses 'tripId' for continuous sync
        'syncRecords': syncRecords,
      };

      print(
          '📤 Sync request: tripId=$tripId, Records count=${syncRecords.length}');

      // Make API call to sync records
      final response = await _apiService.post(
        '/ext/drive-master/api/v1/trip/sync/records',
        body: requestBody,
      );

      print('📥 Sync response status: ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ Trip records synced successfully');
        return true;
      } else {
        print(
            '❌ Failed to sync trip records: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error syncing trip records: $e');
      return false;
    }
  }

  // End trip with proper API call
  Future<void> endTrip({double? endOdometerReading}) async {
    try {
      print('🏁 ============ STARTING END TRIP PROCESS ============');
      print('🏁 ENDING TRIP - endOdometerReading parameter: ${endOdometerReading ?? 'NULL'}');
      print('🏁 Parameter type: ${endOdometerReading.runtimeType}');

      // Get current trip before clearing local data
      final currentTrip = await _tripPersistence.getActiveTrip();

      if (currentTrip == null) {
        print('❌ No active trip found to end');
        throw Exception('No active trip found to end');
      }

      print('🚗 Current trip details:');
      print('   - Vehicle: ${currentTrip.vehicleNumber}');
      print('   - Server Trip ID: ${currentTrip.serverTripId ?? 'NULL'}');
      print('   - Start Odometer: ${currentTrip.startOdometer}');
      print('   - Is Trip Started: ${currentTrip.isTripStarted}');
      print('   - Is Active: ${currentTrip.isActive}');

      // Get current location for end trip
      Map<String, double> location;
      try {
        print('📍 Getting live location for trip end...');
        final currentLocation = await _getCurrentLocation();
        if (currentLocation != null) {
          location = currentLocation;
          print('✅ Live location obtained for trip end: ${location['latitude']}, ${location['longitude']}');
        } else {
          throw Exception('Failed to get current location');
        }
      } catch (locationError) {
        print('❌ Failed to get live location for trip end: $locationError');
        throw Exception(
            'Unable to get current location for trip end. Please ensure GPS is enabled and try again.');
      }

      // Calculate trip timing data
      final endTime = DateTime.now();

      // Get trip locations to calculate distance
      List<TripLocation> tripLocations = [];
      if (currentTrip.id != null) {
        tripLocations =
            await _tripPersistence.getTripLocations(currentTrip.id!);
      }

      // Calculate total distance (basic calculation)
      double totalDistance = 0.0;
      if (tripLocations.length > 1) {
        for (int i = 1; i < tripLocations.length; i++) {
          final prevLoc = tripLocations[i - 1];
          final currLoc = tripLocations[i];

          // Calculate distance between consecutive points using Haversine formula
          final distance = _calculateDistance(prevLoc.latitude,
              prevLoc.longitude, currLoc.latitude, currLoc.longitude);
          totalDistance += distance;
        }
      }

      // Use provided odometer reading or current trip's start odometer + calculated distance as fallback
      // Note: totalDistance is in meters, startOdometer is in km, so convert meters to km
      final endOdometer =
          endOdometerReading ?? (currentTrip.startOdometer + (totalDistance / 1000));

      // DEBUG: Log odometer values ALWAYS (outside serverTripId condition)
      print('🚗 ODOMETER DEBUG - Start: ${currentTrip.startOdometer}, End: ${endOdometer.toInt()}, User Input: ${endOdometerReading ?? 'NULL'}');
      print('🚗 DISTANCE CALCULATION: ${endOdometer - currentTrip.startOdometer} km');
      print('🔍 SERVER TRIP ID STATUS: ${currentTrip.serverTripId ?? 'NULL'}');
      
      // Check for potential issue
      if (endOdometer == currentTrip.startOdometer) {
        print('⚠️ WARNING: Start and end odometer are identical - this will result in 0 distance!');
        print('   - This might mean the user entered the same value, or there is a bug in the flow');
      }

      if (currentTrip.serverTripId != null) {
        // Format datetime strings in the required format (Y-m-d H:i:s)
        final startDateTime =
            currentTrip.startTripTimestamp ?? currentTrip.engagementTimestamp;
        final startDateTimeStr =
            '${startDateTime.year.toString().padLeft(4, '0')}-${startDateTime.month.toString().padLeft(2, '0')}-${startDateTime.day.toString().padLeft(2, '0')} ${startDateTime.hour.toString().padLeft(2, '0')}:${startDateTime.minute.toString().padLeft(2, '0')}:${startDateTime.second.toString().padLeft(2, '0')}';
        final endDateTimeStr =
            '${endTime.year.toString().padLeft(4, '0')}-${endTime.month.toString().padLeft(2, '0')}-${endTime.day.toString().padLeft(2, '0')} ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:${endTime.second.toString().padLeft(2, '0')}';

        // Generate unique sync record UUID
        final syncRecordUuid =
            'sync_record_${DateTime.now().millisecondsSinceEpoch}';

        // Get pause records if any exist (for future implementation)
        List<Map<String, dynamic>> pauseRecords = [];
        // TODO: If you implement pause/resume functionality, get pause records from database here
        
        // Call the correct trip sync records API endpoint
        final requestBody = {
          'records': [
            {
              'uuid': syncRecordUuid,
              'tripUuid': currentTrip.serverTripId!,
              'vehicleUuid': currentTrip.vehicleUuid,
              'scheduleId': currentTrip.scheduleUuid.isNotEmpty
                  ? currentTrip.scheduleUuid
                  : 'DMRS_68CBE78E38090', // Use default if empty
              'isFinished': 1, // Mark trip as finished
              'startRecord': {
                'datetime': startDateTimeStr,
                'latitude': currentTrip.startLatitude,
                'longitude': currentTrip.startLongitude,
                'altitude': 0,
                'address': 'Start location address',
                'odoValue': currentTrip.startOdometer.toInt(),
              },
              'endRecord': {
                'datetime': endDateTimeStr,
                'latitude': location['latitude'],
                'longitude': location['longitude'],
                'altitude': 0,
                'address': 'End location address',
                'odoValue': endOdometer.toInt(),
              },
              'pauseRecords': pauseRecords,
            }
          ]
        };

        print(
            '📤 End trip sync records API request body: ${json.encode(requestBody)}');

        // Call the trip sync records API
        final response = await _apiService.post(
          '/ext/drive-master/api/v1/trip/sync/records',
          body: requestBody,
        );

        print(
            '📥 End trip sync records API response status: ${response.statusCode}');
        print('📥 End trip sync records API response body: ${response.body}');

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final jsonData = json.decode(response.body);
          if (jsonData['status'] == 200 &&
              jsonData['result']?['status'] == true) {
            final successRecords =
                jsonData['result']?['content']?['success'] ?? [];
            final failedRecords =
                jsonData['result']?['content']?['failed'] ?? [];

            if (successRecords.isNotEmpty) {
              print('✅ Trip sync records completed successfully');
              print('📋 Success records: ${successRecords.length}');
              for (var record in successRecords) {
                print('   - ${record['message'] ?? 'Trip sync success!'}');
              }
            }

            if (failedRecords.isNotEmpty) {
              print(
                  '⚠️ Some trip records failed to sync: ${failedRecords.length}');
              for (var record in failedRecords) {
                print('   - Failed: ${record['message'] ?? 'Unknown error'}');
              }
            }
          } else {
            print('⚠️ Trip sync records API returned false status');
          }
        } else {
          print(
              '⚠️ Failed to sync trip records on server: ${response.statusCode} - ${response.body}');
          // Continue with local cleanup even if API call fails
        }
      } else {
        print(
            '⚠️ No server trip ID available for sync operation, proceeding with local cleanup');
      }

      // 🗺️ SEND COMPLETE ROUTE PATH FOR MAP VISUALIZATION
      print('🗺️ ===== SENDING ROUTE PATH FOR MAP VISUALIZATION =====');
      if (currentTrip.serverTripId != null && currentTrip.id != null) {
        try {
          // Get all GPS locations from the trip
          print('📍 Gathering GPS coordinates for route visualization...');
          final tripLocations = await _tripPersistence.getTripLocations(currentTrip.id!);
          
          if (tripLocations.isNotEmpty) {
            print('✅ Found ${tripLocations.length} GPS points for route');
            
            // Format coordinates array for route visualization (reverse order for chronological)
            final List<Map<String, dynamic>> routeCoordinates = [];
            
            // Add start point first
            routeCoordinates.add({
              'latitude': currentTrip.startLatitude,
              'longitude': currentTrip.startLongitude,
              'timestamp': currentTrip.startTripTimestamp?.toUtc().toIso8601String() ?? 
                           currentTrip.engagementTimestamp.toUtc().toIso8601String(),
              'type': 'start'
            });
            
            // Add all tracked locations (reverse to get chronological order)
            final reversedLocations = tripLocations.reversed.toList();
            for (var location in reversedLocations) {
              routeCoordinates.add({
                'latitude': location.latitude,
                'longitude': location.longitude,
                'timestamp': location.timestamp.toUtc().toIso8601String(),
                'speed': location.speed,
                'accuracy': location.accuracy,
                'type': 'tracking'
              });
            }
            
            // Add end point
            routeCoordinates.add({
              'latitude': location['latitude'],
              'longitude': location['longitude'],
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'type': 'end'
            });
            
            // Send route path to server for map visualization
            final routeRequestBody = {
              'tripUuid': currentTrip.serverTripId!,
              'vehicleUuid': currentTrip.vehicleUuid,
              'vehicleNo': currentTrip.vehicleNumber,
              'routePath': routeCoordinates,
              'totalPoints': routeCoordinates.length,
              'startTime': currentTrip.startTripTimestamp?.toUtc().toIso8601String() ?? 
                          currentTrip.engagementTimestamp.toUtc().toIso8601String(),
              'endTime': DateTime.now().toUtc().toIso8601String(),
            };
            
            print('🗺️ Sending route path with ${routeCoordinates.length} coordinates...');
            print('📤 Route API request: /ext/drive-master/api/v1/trip/route-path');
            
            final routeResponse = await _apiService.post(
              '/ext/drive-master/api/v1/trip/route-path',
              body: routeRequestBody,
            );
            
            print('📥 Route path API response status: ${routeResponse.statusCode}');
            print('📥 Route path API response body: ${routeResponse.body}');
            
            if (routeResponse.statusCode >= 200 && routeResponse.statusCode < 300) {
              print('✅ Route path sent successfully! Map should now display complete trip route.');
            } else {
              print('⚠️ Failed to send route path: ${routeResponse.statusCode} - ${routeResponse.body}');
              print('ℹ️ Trip will still complete, but route may not display on web dashboard');
            }
          } else {
            print('⚠️ No GPS tracking data found - cannot create route path');
            print('ℹ️ This might happen if GPS tracking was disabled during the trip');
          }
        } catch (e) {
          print('❌ Error sending route path: $e');
          print('ℹ️ Trip will still complete, but route visualization may not work');
        }
      } else {
        print('⚠️ No server trip ID available for route path - skipping route visualization');
      }
      print('🗺️ ===== ROUTE PATH PROCESSING COMPLETED =====');

      // Stop foreground drop point timer
      _stopForegroundDropPointTimer();

      // Disconnect AMQ connection
      await _disconnectAmqConnection();

      // Stop background tracking service
      await _tripTracking.stopTripTracking();
      print('✅ Background tracking stopped');

      // Mark trip as ended but keep vehicle engagement for release
      print(
          '🔍 Current trip before ending: ${currentTrip.vehicleNumber} (UUID: ${currentTrip.vehicleUuid})');
      print(
          '🔍 Trip ID: ${currentTrip.id}, Server ID: ${currentTrip.serverTripId}');
      print('🚗 Ending trip with odometer reading: $endOdometer');
      await _tripPersistence.markTripAsEnded(currentTrip.id!, endOdometer: endOdometer);
      print('✅ Trip marked as ended with final odometer, vehicle still engaged for release');

      // Verify the trip is still in database but marked as ended
      final verifyTrip = await _tripPersistence.getActiveTrip();
      if (verifyTrip != null) {
        print(
            '✅ Verified: Vehicle ${verifyTrip.vehicleNumber} still engaged (trip_started: ${verifyTrip.isTripStarted})');
      } else {
        print(
            '❌ ERROR: No active trip found after markTripAsEnded - this should not happen!');
      }
    } catch (e) {
      print('❌ Error ending trip: $e');
      rethrow;
    }
  }

  // Helper method to calculate distance between two points using Haversine formula
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth radius in kilometers

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c; // Distance in kilometers
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  // Release vehicle API call
  Future<bool> releaseVehicle({
    required String vehicleUuid,
    required double finalOdometer,
    String releaseReason = 'TRIP_COMPLETED',
  }) async {
    try {
      print('🚗 Starting vehicle release process...');
      print('   - Vehicle UUID: $vehicleUuid');
      print('   - Final Odometer: $finalOdometer');
      print('   - Release Reason: $releaseReason');
      
      // Debug: Check if this matches expected format from API examples
      print('🔍 Release UUID Debug:');
      print('   - UUID Length: ${vehicleUuid.length}');
      print('   - Starts with DMV_: ${vehicleUuid.startsWith('DMV_')}');
      print('   - Expected format: DMV_XXXXXXXXXXXXX (17 chars total)');

      // Validate required parameters
      if (vehicleUuid.isEmpty) {
        print('❌ Vehicle UUID is empty - cannot release vehicle');
        throw Exception('Vehicle UUID is required for release');
      }

      if (finalOdometer < 0) {
        print('❌ Invalid final odometer reading: $finalOdometer');
        throw Exception('Final odometer must be a positive number');
      }

      // Validate release reason is one of the allowed values
      const allowedReasons = ['TRIP_COMPLETED', 'EMERGENCY', 'SHIFT_END'];
      if (!allowedReasons.contains(releaseReason)) {
        print(
            '⚠️ Invalid release reason: $releaseReason, using TRIP_COMPLETED');
        releaseReason = 'TRIP_COMPLETED';
      }

      // Get current location for vehicle release
      Map<String, double> currentLocation;
      try {
        print('📍 Getting live location for vehicle release...');
        final location = await _getCurrentLocation();
        if (location != null) {
          currentLocation = location;
          print('✅ Live location obtained for vehicle release: ${currentLocation['latitude']}, ${currentLocation['longitude']}');
        } else {
          throw Exception('Failed to get current location');
        }
      } catch (locationError) {
        print('❌ Failed to get live location for vehicle release: $locationError');
        throw Exception(
            'Unable to get current location for vehicle release. Please ensure GPS is enabled and try again.');
      }

      // Construct request body exactly matching API specification
      final requestBody = {
        'vehicleUuid': vehicleUuid,
        'releaseReason': releaseReason,
        'finalOdometer': finalOdometer,
        'location': {
          'latitude': currentLocation['latitude']!,
          'longitude': currentLocation['longitude']!,
        },
      };

      print('📤 Release vehicle API call:');
      print('   - URL: /ext/drive-master/api/v1/vehicle/release-vehicle');
      print('   - Method: POST');
      print('   - Body: ${json.encode(requestBody)}');
      
      // Log token for debugging
      try {
        // Import the locator to access AuthService
        final AuthService authService = locator.get<AuthService>();
        final token = await authService.getStoredToken();
        
        if (token != null && token.isNotEmpty) {
          print('🔐 API Token (FULL): $token');
          print('🔐 Token Length: ${token.length}');
          print('🔐 Token is Valid: ${token.contains('.')}');
        } else {
          print('⚠️ No authentication token found');
        }
      } catch (tokenError) {
        print('⚠️ Could not retrieve token for logging: $tokenError');
      }

      final response = await _apiService.post(
        '/ext/drive-master/api/v1/vehicle/release-vehicle',
        body: requestBody,
      );
      
      print('📥 Release vehicle API response:');
      print('   - Status Code: ${response.statusCode}');
      print('   - Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ Vehicle released successfully on server');

        // Parse response to check for additional success indicators
        try {
          final jsonResponse = json.decode(response.body);
          print('📋 Parsed response: ${json.encode(jsonResponse)}');
          
          final message = jsonResponse['message'] ?? '';

          // Check for specific API responses
          if (message.toLowerCase().contains('active trip to be finished')) {
            print('⚠️ Server indicates there is still an active trip to be finished');
            print('   This means the trip must be ended before vehicle release');
            // Even though server says this, if status is true, we'll proceed
            // The dashboard should have already ended the trip by now
            if (jsonResponse['status'] == true) {
              print('✅ Server still returned success despite the message');
            }
          } else if (jsonResponse['status'] == true || jsonResponse['success'] == true) {
            print('✅ Server confirms vehicle release success');
          } else {
            print('⚠️ Server response indicates potential issue: $message');
          }
        } catch (parseError) {
          print('⚠️ Could not parse response JSON: $parseError');
        }

        // Stop foreground drop point timer
        _stopForegroundDropPointTimer();

        // Disconnect AMQ connection before clearing data
        await _disconnectAmqConnection();

        // Clear local vehicle engagement data after successful release
        print('🗑️ Clearing local vehicle engagement data...');
        await _tripPersistence.clearActiveTrips();
        print('✅ Local data cleared successfully');

        return true;
      } else {
        print('❌ Vehicle release failed on server:');
        print('   - Status Code: ${response.statusCode}');
        print('   - Error Response: ${response.body}');

        // Try to parse error message for better debugging
        try {
          final errorJson = json.decode(response.body);
          final errorMessage =
              errorJson['message'] ?? errorJson['error'] ?? 'Unknown error';
          print('   - Parsed Error: $errorMessage');
        } catch (parseError) {
          print('   - Raw Error (could not parse): ${response.body}');
        }

        return false;
      }
    } catch (e) {
      print('❌ Exception during vehicle release: $e');
      print('   - Error Type: ${e.runtimeType}');
      return false;
    }
  }

  // Add fuel entry for vehicle
  Future<bool> addFuelEntry({
    required String vehicleUuid,
    required double quantity,
    required String fuelType,
    required double unitPrice,
    required double totalAmount,
    required double odometerReading,
    required String fuelStationName,
    String? remarks,
  }) async {
    try {
      print('⛽ Adding fuel entry for vehicle: $vehicleUuid');

      // Get current location - will throw exception with specific message if failed
      final currentLocation = await _getCurrentLocation();
      if (currentLocation == null) {
        throw Exception('Unexpected error: Location data is null');
      }

      // Format current datetime in ISO 8601 format
      final now = DateTime.now().toUtc();
      final datetime = now.toIso8601String();

      final requestBody = {
        'vehicleUuid': vehicleUuid,
        'quantity': quantity.toString(),
        'fuelType': fuelType.toLowerCase(),
        'unitPrice': unitPrice.toString(),
        'totalAmount': totalAmount.toString(),
        'odometerReading': odometerReading.toString(),
        'fuelStationName': fuelStationName,
        'location': {
          'latitude': currentLocation['latitude'].toString(),
          'longitude': currentLocation['longitude'].toString(),
        },
        'datetime': datetime,
        'remarks': remarks ?? '',
      };

      print('📤 Fuel entry API request body:');
      print('   URL: /ext/drive-master/api/v1/vehicle/add/fuel-entry');
      print('   Body: ${json.encode(requestBody)}');

      final response = await _apiService.post(
        '/ext/drive-master/api/v1/vehicle/add/fuel-entry',
        body: requestBody,
      );

      print('📥 Fuel entry API response:');
      print('   Status: ${response.statusCode}');
      print('   Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['status'] == true) {
          print('✅ Fuel entry added successfully');
          return true;
        } else {
          print(
              '❌ Fuel entry API returned false status: ${jsonResponse['message']}');
          throw Exception('API Error: ${jsonResponse['message']}');
        }
      } else {
        print(
            '❌ Failed to add fuel entry - API returned ${response.statusCode}');
        final errorBody =
            response.body.isNotEmpty ? response.body : 'Unknown error';
        throw Exception('API Error (${response.statusCode}): $errorBody');
      }
    } catch (e) {
      print('❌ Error adding fuel entry: $e');
      rethrow; // Re-throw to let the UI handle the specific error message
    }
  }

  // Add drop point during active trip
  Future<bool> addDropPoint() async {
    try {
      print('📍 Starting drop point addition...');

      // Get active trip details
      final activeTrip = await getLocalActiveTrip();
      if (activeTrip == null) {
        print(
            '❌ No active trip found for drop point - user must start a trip first');
        throw Exception('No active trip found. Please start a trip first.');
      }

      // Allow drop points for both engaged and started trips
      print(
          'ℹ️ Trip status - Engaged: ${activeTrip.isActive}, Started: ${activeTrip.isTripStarted}');
      if (!activeTrip.isActive) {
        print('❌ Trip is not active - cannot add drop point');
        throw Exception('Trip is not active. Please engage a vehicle first.');
      }

      print(
          '✅ Active trip found: ${activeTrip.vehicleNumber} (Trip ID: ${activeTrip.serverTripId})');

      // Get current location
      print('📍 Getting current location...');
      final currentLocation = await _getCurrentLocation();
      if (currentLocation == null) {
        print('❌ Could not get current location for drop point');
        throw Exception(
            'Unable to get current location. Please check GPS permissions.');
      }

      print(
          '✅ Location obtained: ${currentLocation['latitude']}, ${currentLocation['longitude']}');

      // Generate mobile sync ID
      final mobileSyncId = 'DROP_${DateTime.now().millisecondsSinceEpoch}';

      // Format current time in the required format (Y-m-d H:i:s)
      final now = DateTime.now();
      final dropAt =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final requestBody = {
        'tripUuid': activeTrip.serverTripId ??
            'DMT_${DateTime.now().millisecondsSinceEpoch}',
        'vehicleUuid': activeTrip.vehicleUuid,
        'vehicleNo': activeTrip.vehicleNumber,
        'mobileSyncId': mobileSyncId,
        'dropAt': dropAt,
        'latitude': currentLocation['latitude']!,
        'longitude': currentLocation['longitude']!,
        'speed': currentLocation['speed'] ?? 0.0, // Use actual GPS speed from device
        'altitude': 0.0, // Optional - set to 0.0 as default
        'accuracy': 10.0, // Optional - set to 10.0 as default
        'bearing': 0.0, // Optional - set to 0.0 as default
      };

      print('📤 Drop point API request body:');
      print('   URL: /ext/drive-master/api/v1/trip/sync/add/drop-point');
      print('   Body: ${json.encode(requestBody)}');

      final response = await _apiService.post(
        '/ext/drive-master/api/v1/trip/sync/add/drop-point',
        body: requestBody,
      );

      print('📥 Drop point API response:');
      print('   Status: ${response.statusCode}');
      print('   Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print(
            '✅ Drop point added successfully to trip ${activeTrip.serverTripId}');
        return true;
      } else {
        print(
            '❌ Failed to add drop point - API returned ${response.statusCode}');
        throw Exception('API Error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('❌ Error adding drop point: $e');
      rethrow; // Re-throw to let the UI handle the specific error message
    }
  }

  /// Start foreground drop point timer for automatic API calls every 5 seconds
  void _startForegroundDropPointTimer() {
    // Cancel any existing timer
    _dropPointTimer?.cancel();
    
    print('🕐 Starting foreground drop point timer - calls every 5 seconds when app is in foreground');
    
    _dropPointTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // Only make drop point calls when app is in foreground
      if (_isAppInForeground) {
        print('📍 [FOREGROUND DROP POINT] Making automatic drop point call...');
        
        try {
          final success = await _addDropPointWithLogging();
          if (success) {
            print('✅ [FOREGROUND DROP POINT] Drop point added successfully: ${success}');
          } else {
            print('⚠️ [FOREGROUND DROP POINT] Drop point call failed');
          }
        } catch (e) {
          print('❌ [FOREGROUND DROP POINT] Error in automatic drop point call: $e');
        }
      } else {
        print('📱 [FOREGROUND DROP POINT] App in background - skipping drop point call');
      }
    });
  }

  /// Stop foreground drop point timer
  void _stopForegroundDropPointTimer() {
    _dropPointTimer?.cancel();
    _dropPointTimer = null;
    print('🛑 Foreground drop point timer stopped');
  }

  /// Set app foreground state (to be called by app lifecycle observer)
  void setAppForegroundState(bool isInForeground) {
    _isAppInForeground = isInForeground;
    print('📱 App lifecycle changed - Foreground: $isInForeground');
  }

  /// Enhanced drop point method with detailed logging
  Future<bool> _addDropPointWithLogging() async {
    try {
      final timestamp = DateTime.now();
      print('📍 [DROP POINT API] Starting automatic drop point call at ${timestamp.toIso8601String()}');

      // Get active trip details
      final activeTrip = await getLocalActiveTrip();
      if (activeTrip == null) {
        print('❌ [DROP POINT API] No active trip found for drop point');
        return false;
      }

      // Allow drop points for both engaged and started trips
      print('✅ [DROP POINT API] Active trip found:');
      print('   - Vehicle: ${activeTrip.vehicleNumber}');
      print('   - Trip ID: ${activeTrip.serverTripId}');
      print('   - Engaged: ${activeTrip.isActive}');
      print('   - Started: ${activeTrip.isTripStarted}');

      if (!activeTrip.isActive) {
        print('❌ [DROP POINT API] Trip is not active - cannot add drop point');
        return false;
      }

      // Get current location
      print('📍 [DROP POINT API] Getting current location...');
      final currentLocation = await _getCurrentLocation();
      if (currentLocation == null) {
        print('❌ [DROP POINT API] Could not get current location for drop point');
        return false;
      }

      print('✅ [DROP POINT API] Location obtained:');
      print('   - Latitude: ${currentLocation['latitude']}');
      print('   - Longitude: ${currentLocation['longitude']}');

      // Generate mobile sync ID
      final mobileSyncId = 'DROP_${DateTime.now().millisecondsSinceEpoch}';

      // Format current time in the required format (Y-m-d H:i:s)
      final now = DateTime.now();
      final dropAt =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final requestBody = {
        'tripUuid': activeTrip.serverTripId ??
            'DMT_${DateTime.now().millisecondsSinceEpoch}',
        'vehicleUuid': activeTrip.vehicleUuid,
        'vehicleNo': activeTrip.vehicleNumber,
        'mobileSyncId': mobileSyncId,
        'dropAt': dropAt,
        'latitude': currentLocation['latitude']!,
        'longitude': currentLocation['longitude']!,
        'speed': currentLocation['speed'] ?? 0.0, // Use actual GPS speed from device
        'altitude': 0.0, // Optional - set to 0.0 as default
        'accuracy': 10.0, // Optional - set to 10.0 as default
        'bearing': 0.0, // Optional - set to 0.0 as default
      };

      print('📤 [DROP POINT API] Request details:');
      print('   - URL: /ext/drive-master/api/v1/trip/sync/add/drop-point');
      print('   - Method: POST');
      print('   - Body: ${json.encode(requestBody)}');

      final response = await _apiService.post(
        '/ext/drive-master/api/v1/trip/sync/add/drop-point',
        body: requestBody,
      );

      print('📥 [DROP POINT API] Response received:');
      print('   - Status: ${response.statusCode}');
      print('   - Body: ${response.body}');
      print('   - Headers: ${response.headers}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ [DROP POINT API] SUCCESS - Drop point added to trip ${activeTrip.serverTripId}');
        print('   - Mobile Sync ID: $mobileSyncId');
        print('   - Drop Time: $dropAt');
        print('   - Location: ${currentLocation['latitude']}, ${currentLocation['longitude']}');
        return true;
      } else {
        print('❌ [DROP POINT API] FAILED - API returned status ${response.statusCode}');
        print('   - Error Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ [DROP POINT API] EXCEPTION occurred: $e');
      print('   - Error Type: ${e.runtimeType}');
      return false;
    }
  }

  /// Initialize AMQ connection for real-time vehicle sensor data
  Future<void> _initializeAmqConnection(Map<String, dynamic> tripResponse) async {
    try {
      print('🐰 Attempting to initialize AMQ connection...');
      
      // Look for liveAmq configuration in various locations of the response
      Map<String, dynamic>? liveAmqConfig;
      
      // Check in result.content.liveAmq (most likely location based on your example)
      if (tripResponse['result'] != null && 
          tripResponse['result']['content'] != null &&
          tripResponse['result']['content']['liveAmq'] != null) {
        liveAmqConfig = tripResponse['result']['content']['liveAmq'] as Map<String, dynamic>;
        print('🔍 Found liveAmq config in result.content: $liveAmqConfig');
      }
      
      // Check in result.liveAmq as fallback
      if (liveAmqConfig == null && 
          tripResponse['result'] != null && 
          tripResponse['result']['liveAmq'] != null) {
        liveAmqConfig = tripResponse['result']['liveAmq'] as Map<String, dynamic>;
        print('🔍 Found liveAmq config in result: $liveAmqConfig');
      }
      
      // Check in root level as another fallback
      if (liveAmqConfig == null && tripResponse['liveAmq'] != null) {
        liveAmqConfig = tripResponse['liveAmq'] as Map<String, dynamic>;
        print('🔍 Found liveAmq config in root: $liveAmqConfig');
      }

      if (liveAmqConfig != null) {
        print('✅ Found AMQ configuration, creating connection...');
        
        final amqConfig = AmqConfig.fromJson(liveAmqConfig);
        print('🔧 AMQ Config - Host: ${amqConfig.host}, Port: ${amqConfig.port}, Topic: ${amqConfig.topic}');
        
        final success = await _amqService.initializeConnection(amqConfig);
        
        if (success) {
          print('🎉 AMQ connection established successfully!');
          
          // Listen to sensor data for logging (optional)
          _amqService.sensorDataStream.listen(
            (sensorData) {
              print('📊 Real-time sensor update received');
              // Here you could emit to UI streams or update local state
            },
            onError: (error) {
              print('❌ AMQ sensor data stream error: $error');
            },
          );
          
          // Send initial driver status
          await _amqService.sendDriverStatus('TRIP_STARTED', {
            'tripId': tripResponse['result']?['content']?['tripUuid'],
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          
        } else {
          print('⚠️ Failed to establish AMQ connection');
        }
      } else {
        print('ℹ️ No liveAmq configuration found in trip response - AMQ integration skipped');
        print('🔍 Available keys in response: ${tripResponse.keys.toList()}');
        if (tripResponse['result'] != null) {
          print('🔍 Available keys in result: ${(tripResponse['result'] as Map<String, dynamic>).keys.toList()}');
          if (tripResponse['result']['content'] != null) {
            print('🔍 Available keys in content: ${(tripResponse['result']['content'] as Map<String, dynamic>).keys.toList()}');
          }
        }
      }
    } catch (e) {
      print('❌ Error initializing AMQ connection: $e');
      // Don't throw - AMQ is optional, trip should continue without it
    }
  }

  /// Disconnect AMQ connection when trip ends
  Future<void> _disconnectAmqConnection() async {
    try {
      if (_amqService.isConnected) {
        print('🐰 Disconnecting from AMQ...');
        
        // Send final driver status
        await _amqService.sendDriverStatus('TRIP_ENDED', {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        
        // Close the connection
        await _amqService.closeConnection();
        print('✅ AMQ connection closed successfully');
      } else {
        print('ℹ️ AMQ not connected, no need to disconnect');
      }
    } catch (e) {
      print('❌ Error disconnecting AMQ: $e');
      // Don't throw - this shouldn't prevent trip end
    }
  }

  /// Get AMQ service for external access (e.g., for UI components)
  AmqService get amqService => _amqService;
}

// Response model for vehicle engagement - matching actual API structure
class VehicleEngagementResponse {
  final bool status;
  final int statusCode;
  final String message;
  final EngagementContent? content;

  VehicleEngagementResponse({
    required this.status,
    required this.statusCode,
    required this.message,
    this.content,
  });

  factory VehicleEngagementResponse.fromJson(Map<String, dynamic> json) {
    return VehicleEngagementResponse(
      status: json['status'] ?? false,
      statusCode: json['statusCode'] ?? 0,
      message: json['message'] ?? '',
      content: json['content'] != null
          ? EngagementContent.fromJson(json['content'])
          : null,
    );
  }
}

// Content structure from actual API
class EngagementContent {
  final VehicleInfo vehicle;
  final List<Schedule> schedules;

  EngagementContent({
    required this.vehicle,
    required this.schedules,
  });

  factory EngagementContent.fromJson(Map<String, dynamic> json) {
    return EngagementContent(
      vehicle: VehicleInfo.fromJson(json['vehicle']),
      schedules: (json['schedules'] as List)
          .map((schedule) => Schedule.fromJson(schedule))
          .toList(),
    );
  }
}

// Vehicle info from actual API response
class VehicleInfo {
  final String vehicleNo;
  final String vehicleUuid;
  final String activeDeviceImei;

  VehicleInfo({
    required this.vehicleNo,
    required this.vehicleUuid,
    required this.activeDeviceImei,
  });

  factory VehicleInfo.fromJson(Map<String, dynamic> json) {
    // Try different possible field names for vehicleUuid
    String vehicleUuid = json['vehicleUuid'] ??
        json['vehicleUUID'] ??
        json['vehicle_uuid'] ??
        json['uuid'] ??
        json['id'] ??
        '';

    print('🔍 VehicleInfo Debug:');
    print('   - JSON keys: ${json.keys.toList()}');
    print('   - vehicleUuid value: "$vehicleUuid"');
    print('   - vehicleNo: "${json['vehicleNo'] ?? json['vehicleNumber'] ?? ''}"');
    print('   - Raw JSON: $json');
    
    if (vehicleUuid.isEmpty) {
      print('⚠️ WARNING: Empty vehicleUuid extracted from response!');
    } else {
      print('✅ Successfully extracted vehicleUuid: $vehicleUuid');
    }

    return VehicleInfo(
      vehicleNo: json['vehicleNo'] ?? json['vehicleNumber'] ?? '',
      vehicleUuid: vehicleUuid,
      activeDeviceImei: json['activeDeviceImei'] ?? json['deviceImei'] ?? '',
    );
  }
}

// Schedule model - matching actual API structure
class Schedule {
  final String id;
  final String uuid;
  final SchedulePeriod schedulePeriod;
  final ScheduleVehicle vehicle;
  final RouteInfo route;

  Schedule({
    required this.id,
    required this.uuid,
    required this.schedulePeriod,
    required this.vehicle,
    required this.route,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['_id']?['\$oid'] ?? '',
      uuid: json['uuid'] ?? '',
      schedulePeriod: SchedulePeriod.fromJson(json['schedulePeriod']),
      vehicle: ScheduleVehicle.fromJson(json['vehicle']),
      route: RouteInfo.fromJson(json['route']),
    );
  }
}

// Schedule period
class SchedulePeriod {
  final String startFrom;
  final String endTo;

  SchedulePeriod({
    required this.startFrom,
    required this.endTo,
  });

  factory SchedulePeriod.fromJson(Map<String, dynamic> json) {
    return SchedulePeriod(
      startFrom: json['startFrom'] ?? '',
      endTo: json['endTo'] ?? '',
    );
  }
}

// Vehicle in schedule
class ScheduleVehicle {
  final String uuid;
  final String vehicleNo;
  final bool isEngaged;

  ScheduleVehicle({
    required this.uuid,
    required this.vehicleNo,
    required this.isEngaged,
  });

  factory ScheduleVehicle.fromJson(Map<String, dynamic> json) {
    return ScheduleVehicle(
      uuid: json['uuid'] ?? '',
      vehicleNo: json['vehicleNo'] ?? '',
      isEngaged: json['isEngaged'] ?? false,
    );
  }
}

// Route information
class RouteInfo {
  final String uuid;
  final String routeName;
  final String routeNo;
  final RoutePoint startPoint;
  final RoutePoint endPoint;

  RouteInfo({
    required this.uuid,
    required this.routeName,
    required this.routeNo,
    required this.startPoint,
    required this.endPoint,
  });

  factory RouteInfo.fromJson(Map<String, dynamic> json) {
    return RouteInfo(
      uuid: json['uuid'] ?? '',
      routeName: json['routeName'] ?? '',
      routeNo: json['routeNo'] ?? '',
      startPoint: RoutePoint.fromJson(json['startPoint']),
      endPoint: RoutePoint.fromJson(json['endPoint']),
    );
  }
}

// Route point (start/end)
class RoutePoint {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final List<double> geoPoint;
  final bool status;
  final bool isActive;

  RoutePoint({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.geoPoint,
    required this.status,
    required this.isActive,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      id: json['_id']?['\$oid'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      geoPoint: (json['geoPoint'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      status: json['status'] ?? false,
      isActive: json['isActive'] ?? false,
    );
  }
}

// Active Trip Response model
class ActiveTripResponse {
  final int status;
  final List<dynamic> result;

  ActiveTripResponse({
    required this.status,
    required this.result,
  });

  factory ActiveTripResponse.fromJson(Map<String, dynamic> json) {
    return ActiveTripResponse(
      status: json['status'] ?? 0,
      result: json['result'] ?? [],
    );
  }

  bool get hasActiveTrip => result.isNotEmpty;
}

// Trip Start Response model - based on API structure
class TripStartResponse {
  final int status;
  final TripResult? result;

  TripStartResponse({
    required this.status,
    this.result,
  });

  factory TripStartResponse.fromJson(Map<String, dynamic> json) {
    return TripStartResponse(
      status: json['status'] ?? 0,
      result:
          json['result'] != null ? TripResult.fromJson(json['result']) : null,
    );
  }

  bool get isSuccess => status == 200 && result?.status == true;
  String get message => result?.message ?? '';
}

// Trip Result nested model
class TripResult {
  final bool status;
  final String message;
  final int statusCode;
  final String? tripId; // Server-generated trip ID

  TripResult({
    required this.status,
    required this.message,
    required this.statusCode,
    this.tripId,
  });

  factory TripResult.fromJson(Map<String, dynamic> json) {
    print('🔍 Parsing TripResult from JSON: ${json.toString()}');
    
    // Try multiple locations for trip ID
    String? tripId = json['tripId'] ?? json['trip_id'] ?? json['id'];
    
    // Check if tripUuid is in content object (matching actual API response structure)
    if (tripId == null && json['content'] != null) {
      final content = json['content'] as Map<String, dynamic>;
      tripId = content['tripUuid'] ?? content['tripId'] ?? content['trip_id'] ?? content['id'];
      print('🔍 Found tripId in content: $tripId');
    }
    
    print('🔍 Extracted tripId: $tripId');

    return TripResult(
      status: json['status'] ?? false,
      message: json['message'] ?? '',
      statusCode: json['statusCode'] ?? 0,
      tripId: tripId, // Handle multiple formats
    );
  }
}

// Custom exception for vehicle engagement errors
class VehicleEngagementException implements Exception {
  final String message;

  VehicleEngagementException(this.message);

  @override
  String toString() => 'VehicleEngagementException: $message';
}

import 'dart:async';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../database/trip_database.dart';
import 'trip_persistence_service.dart';

class TripTrackingService {
  static final TripTrackingService _instance = TripTrackingService._internal();
  factory TripTrackingService() => _instance;
  TripTrackingService._internal();

  bool _isServiceRunning = false;
  Timer? _updateTimer;
  Timer? _syncTimer;
  
  // Callback function for trip sync - will be set by VehicleService
  Future<bool> Function({
    required String tripId,
    required String vehicleUuid, 
    required String schedulingUuid,
    required List<TripLocation> locations,
    required ActiveTrip tripData
  })? _syncCallback;
  
  // Set the sync callback function
  void setSyncCallback(Future<bool> Function({
    required String tripId,
    required String vehicleUuid, 
    required String schedulingUuid,
    required List<TripLocation> locations,
    required ActiveTrip tripData
  }) callback) {
    _syncCallback = callback;
  }

  // Initialize foreground service
  Future<void> initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'trip_tracking_channel',
        channelName: 'Trip Tracking',
        channelDescription: 'This notification appears when tracking your trip in background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
        buttons: [
          const NotificationButton(
            id: 'pause_trip',
            text: 'Pause Trip',
          ),
          const NotificationButton(
            id: 'end_trip', 
            text: 'End Trip',
          ),
        ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000, // Update every 5 seconds
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // Start trip tracking service
  Future<bool> startTripTracking(ActiveTrip trip) async {
    try {
      print('🚀 Starting trip tracking service...');
      
      // Initialize foreground task if not done
      await initForegroundTask();
      
      // Check if service can start
      if (await FlutterForegroundTask.isRunningService) {
        print('⚠️ Foreground service is already running');
        return false;
      }

      // Start the foreground service
      final bool started = await FlutterForegroundTask.startService(
        notificationTitle: 'DriveMaster - Trip Active',
        notificationText: 'Vehicle: ${trip.vehicleNumber} • ${_formatElapsedTime(trip.elapsedTimeFromEngagement)}',
        callback: startTripTrackingCallback,
      );

      if (started) {
        _isServiceRunning = true;
        print('✅ Trip tracking service started successfully');
        
        // Start periodic notification updates
        _startNotificationUpdates(trip);
      } else {
        print('❌ Failed to start trip tracking service');
      }

      return started;
    } catch (e) {
      print('❌ Error starting trip tracking service: $e');
      return false;
    }
  }

  // Starts a single 5-second timer that handles BOTH notification updates
  // and API sync – previously two separate timers were doing the same tick.
  void _startNotificationUpdates(ActiveTrip trip) {
    _updateTimer?.cancel();
    _syncTimer?.cancel(); // ensure no old sync timer survives a restart

    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isServiceRunning || !await FlutterForegroundTask.isRunningService) {
        timer.cancel();
        return;
      }

      // 1. Update foreground notification
      final elapsed = trip.elapsedTimeFromEngagement;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'DriveMaster - Trip Active',
        notificationText: 'Vehicle: ${trip.vehicleNumber} • ${_formatElapsedTime(elapsed)}',
      );

      // 2. Sync DB locations to server (previously a separate _syncTimer)
      await _performSync();
    });
  }

  // _startSyncTimer is kept for API compatibility but is now a no-op because
  // the sync runs inside the single _updateTimer tick above.
  void _startSyncTimer() {
    // Intentionally empty – sync is driven by _startNotificationUpdates().
  }
  
  // Perform sync operation in main isolate
  Future<void> _performSync() async {
    try {
      if (_syncCallback == null) {
        print('⚠️ Sync callback not set, skipping sync');
        return;
      }
      
      // Get current active trip
      final persistenceService = TripPersistenceService();
      final activeTrip = await persistenceService.getActiveTrip();
      
      if (activeTrip != null && activeTrip.isTripStarted && activeTrip.serverTripId != null) {
        // Get recent locations for sync
        final locations = await persistenceService.getTripLocations(activeTrip.id!, limit: 10);
        
        print('🔄 Performing background sync for trip ${activeTrip.serverTripId}');
        
        // Call the sync callback
        final success = await _syncCallback!(
          tripId: activeTrip.serverTripId!,
          vehicleUuid: activeTrip.vehicleUuid,
          schedulingUuid: activeTrip.scheduleUuid,
          locations: locations,
          tripData: activeTrip,
        );
        
        if (success) {
          print('✅ Background sync successful');
        } else {
          print('❌ Background sync failed');
        }
      }
    } catch (e) {
      print('❌ Error in background sync: $e');
    }
  }

  // Stop trip tracking service
  Future<void> stopTripTracking() async {
    try {
      print('🛑 Stopping trip tracking service...');
      
      _updateTimer?.cancel();
      _updateTimer = null;
      _syncTimer?.cancel();
      _syncTimer = null;
      
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        _isServiceRunning = false;
        print('✅ Trip tracking service stopped');
      } else {
        print('⚠️ Trip tracking service was not running');
      }
    } catch (e) {
      print('❌ Error stopping trip tracking service: $e');
    }
  }

  // Check if service is running
  Future<bool> isServiceRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }

  // Handle notification button presses
  void setNotificationButtonCallback(Function(String) callback) {
    FlutterForegroundTask.setOnLockScreenVisibility(true);
  }

  // Format elapsed time for display
  String _formatElapsedTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}

// Foreground task callback function
@pragma('vm:entry-point')
void startTripTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(TripTrackingTaskHandler());
}

class TripTrackingTaskHandler extends TaskHandler {
  final TripPersistenceService _persistenceService = TripPersistenceService();
  
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    print('🔧 Trip tracking task started at $timestamp');
    _persistenceService.initialize();
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    try {
      // Get current active trip and update tracking in background
      _updateTripTracking();
    } catch (e) {
      print('❌ Error in trip tracking repeat event: $e');
    }
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    print('🛑 Trip tracking task destroyed at $timestamp');
    _persistenceService.dispose();
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('🔘 Notification button pressed: $id');
    // Handle button presses here if needed
  }

  // Update trip tracking and sync records (async operation called from sync method)
  void _updateTripTracking() async {
    try {
      final activeTrip = await _persistenceService.getActiveTrip();
      if (activeTrip != null) {
        final elapsed = activeTrip.elapsedTimeFromEngagement;
        print('⏱️ Trip ${activeTrip.vehicleNumber} running for ${elapsed.inSeconds} seconds');
        
        // Update notification
        FlutterForegroundTask.updateService(
          notificationTitle: 'DriveMaster - Trip Active',
          notificationText: 'Vehicle: ${activeTrip.vehicleNumber} • ${_formatElapsedTime(elapsed)}',
        );
        
        // Note: Trip sync is now handled by the main isolate timer
      }
    } catch (e) {
      print('❌ Error updating trip tracking: $e');
    }
  }
  


  String _formatElapsedTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}
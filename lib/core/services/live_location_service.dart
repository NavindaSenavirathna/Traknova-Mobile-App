import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

/// A single GPS reading with derived speed in km/h.
class LocationSnapshot {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;    // m/s from GPS
  final double altitude;
  final double bearing;  // heading in degrees
  final DateTime timestamp;

  LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.altitude,
    required this.bearing,
    required this.timestamp,
  });

  double get speedKmh => speed * 3.6;
}

/// Stream-based live location service that POSTs points to the backend.
///
/// Optimisations over the old polling approach:
///   • Uses [Geolocator.getPositionStream()] (event-driven) instead of
///     [getCurrentPosition()] inside a [Timer] – saves a GPS fix request
///     every tick and dramatically reduces battery usage.
///   • Platform-specific [LocationSettings] (Android / Apple) for best
///     chipset behaviour on each OS.
///   • Minimum-movement gate: a point is only sent if the vehicle moved
///     ≥ [_minDistanceMeters] OR [_keepaliveSeconds] elapsed without a
///     send (ensures at least one heartbeat per interval).
///   • Offline queue with retry: up to [_maxQueueSize] unsent points are
///     buffered and flushed on the next successful send.
///   • Trip-mode guard: call [setTripActive(true)] when VehicleService starts
///     a trip so this service stops posting to the drop-point endpoint and
///     avoids duplicate server calls.
///   • Real [accuracy] and [bearing] are sent in every payload.
///
/// Usage:
///   liveLocationService.setApiService(locator<ApiService>());
///   await liveLocationService.start();
///   await liveLocationService.stop();
///   liveLocationService.locationStream → Stream<LocationSnapshot>
class LiveLocationService {
  static final LiveLocationService _instance = LiveLocationService._internal();
  factory LiveLocationService() => _instance;
  LiveLocationService._internal();

  ApiService? _api;

  /// Must be called once (e.g. in [initState]) before [start].
  void setApiService(ApiService api) => _api = api;

  // ── Tuning constants ──────────────────────────────────────────────────────
  /// Minimum distance (metres) the device must move before a new point is sent.
  static const double _minDistanceMeters = 15.0;

  /// Even if stationary, send a keepalive point this often (seconds).
  static const int _keepaliveSeconds = 30;

  /// Maximum number of unsent points buffered for retry.
  static const int _maxQueueSize = 50;

  /// Discard positions with accuracy worse than this (metres).
  static const double _maxAccuracyMeters = 60.0;

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isTracking = false;
  bool _tripActive = false; // when true, skip sending to avoid duplicate calls
  StreamSubscription<Position>? _positionSub;
  int _updatesSent = 0;
  LocationSnapshot? _lastLocation;
  LocationSnapshot? _lastSentLocation;
  DateTime? _lastSentAt;

  bool get isTracking => _isTracking;
  int get updatesSent => _updatesSent;
  LocationSnapshot? get lastLocation => _lastLocation;

  /// Call with [true] when VehicleService starts a trip so this service
  /// pauses its own API calls (VehicleService's drop-point timer takes over).
  /// Call with [false] again when the trip ends.
  void setTripActive(bool active) {
    _tripActive = active;
    print('📍 LiveLocationService: trip-mode ${active ? "ON (pausing own API sends)" : "OFF (resuming API sends)"}');
  }

  // ── Offline queue ─────────────────────────────────────────────────────────
  final List<LocationSnapshot> _pendingQueue = [];

  void _enqueue(LocationSnapshot snap) {
    if (_pendingQueue.length >= _maxQueueSize) {
      _pendingQueue.removeAt(0); // drop oldest
    }
    _pendingQueue.add(snap);
  }

  // ── Public stream ─────────────────────────────────────────────────────────
  final StreamController<LocationSnapshot> _controller =
      StreamController<LocationSnapshot>.broadcast();

  Stream<LocationSnapshot> get locationStream => _controller.stream;

  // ── Permissions ───────────────────────────────────────────────────────────
  Future<bool> _requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      print('❌ LiveLocationService: Location services disabled');
      return false;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        print('❌ LiveLocationService: Permission denied');
        return false;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      print('❌ LiveLocationService: Permission permanently denied');
      return false;
    }
    return true;
  }

  // ── Foreground service setup ──────────────────────────────────────────────
  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'live_location_channel',
        channelName: 'Live Location',
        channelDescription: 'Keeps location tracking active in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 10000, // handler tick – only keeps process alive
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Build platform-specific [LocationSettings] for best GPS behaviour.
  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        // Only wake the app when the device has moved at least this far.
        distanceFilter: _minDistanceMeters.toInt(),
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Tracking your location…',
          notificationTitle: 'Traknova – Live Location',
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: _minDistanceMeters.toInt(),
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    // Fallback for other platforms (web, desktop)
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _minDistanceMeters.toInt(),
    );
  }

  // ── Start / Stop ──────────────────────────────────────────────────────────

  /// Start the location stream. [start] is idempotent.
  Future<bool> start() async {
    if (_isTracking) return true;

    if (!await _requestPermissions()) return false;

    try {
      await _initForegroundTask();

      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Traknova – Live Location',
          notificationText: 'Locating…',
          callback: _foregroundCallback,
        );
      }

      _isTracking = true;
      _updatesSent = 0;
      _lastSentAt = null;
      _lastSentLocation = null;

      _positionSub = Geolocator.getPositionStream(
        locationSettings: _buildLocationSettings(),
      ).listen(
        _onPosition,
        onError: (e) => print('❌ LiveLocationService: stream error – $e'),
        cancelOnError: false,
      );

      print('✅ LiveLocationService: started (stream-based, minDist: ${_minDistanceMeters}m, keepalive: ${_keepaliveSeconds}s)');
      return true;
    } catch (e) {
      print('❌ LiveLocationService: Failed to start – $e');
      _isTracking = false;
      return false;
    }
  }

  /// Stop the stream and shut down the foreground service.
  Future<void> stop() async {
    if (!_isTracking) return;

    _isTracking = false;
    await _positionSub?.cancel();
    _positionSub = null;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      print('⚠️ LiveLocationService: Error stopping foreground service – $e');
    }

    print('🛑 LiveLocationService: Stopped. Total updates sent: $_updatesSent');
  }

  // ── Position handler ──────────────────────────────────────────────────────
  void _onPosition(Position pos) {
    // Discard low-accuracy fixes (e.g. first network-based fix).
    if (pos.accuracy > _maxAccuracyMeters) {
      print('⚠️ LiveLocationService: Skipping low-accuracy fix (${pos.accuracy.toStringAsFixed(1)}m)');
      return;
    }

    final snap = LocationSnapshot(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      speed: pos.speed < 0 ? 0 : pos.speed,
      altitude: pos.altitude,
      bearing: pos.heading,
      timestamp: DateTime.now(),
    );

    _lastLocation = snap;
    if (!_controller.isClosed) _controller.add(snap);

    // ── Movement gate ────────────────────────────────────────────────────
    final now = snap.timestamp;
    final secondsSinceLastSend = _lastSentAt == null
        ? _keepaliveSeconds + 1
        : now.difference(_lastSentAt!).inSeconds;
    final movedFar = _lastSentLocation == null ||
        Geolocator.distanceBetween(
              _lastSentLocation!.latitude,
              _lastSentLocation!.longitude,
              snap.latitude,
              snap.longitude,
            ) >=
            _minDistanceMeters;

    final shouldSend = movedFar || secondsSinceLastSend >= _keepaliveSeconds;

    if (!shouldSend) return; // vehicle hasn't moved enough – skip API call

    // ── Notification update ───────────────────────────────────────────────
    _updateNotification(snap);

    // ── Skip API send when a trip is active (VehicleService handles it) ──
    if (_tripActive) {
      _lastSentLocation = snap;
      _lastSentAt = now;
      return;
    }

    // ── Send queued + current point ───────────────────────────────────────
    _enqueue(snap);
    _flushQueue();
  }

  Future<void> _flushQueue() async {
    if (_api == null || _pendingQueue.isEmpty) return;

    // Work on a snapshot so the list can be mutated while we iterate.
    final toSend = List<LocationSnapshot>.from(_pendingQueue);
    _pendingQueue.clear();

    for (final snap in toSend) {
      final sent = await _sendToServer(snap);
      if (!sent) {
        // Re-queue failed points (they'll be retried on the next flush).
        _enqueue(snap);
      }
    }
  }

  // ── API call ──────────────────────────────────────────────────────────────
  Future<bool> _sendToServer(LocationSnapshot snap) async {
    if (_api == null) return false;

    try {
      final now = snap.timestamp;
      final dropAt =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      final body = {
        'mobileSyncId': 'LOC_${now.millisecondsSinceEpoch}',
        'dropAt': dropAt,
        'latitude': snap.latitude,
        'longitude': snap.longitude,
        'speed': snap.speed,
        'altitude': snap.altitude,
        'accuracy': snap.accuracy,   // real GPS accuracy
        'bearing': snap.bearing,     // real GPS heading
      };

      final response = await _api!.post(
        '/ext/drive-master/api/v1/trip/sync/add/drop-point',
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _updatesSent++;
        _lastSentLocation = snap;
        _lastSentAt = snap.timestamp;
        print('✅ LiveLocationService: Sent #$_updatesSent '
            '(${snap.latitude.toStringAsFixed(5)}, ${snap.longitude.toStringAsFixed(5)})');
        return true;
      } else {
        print('❌ LiveLocationService: Server ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ LiveLocationService: Send error – $e');
      return false;
    }
  }

  // ── Notification helper ───────────────────────────────────────────────────
  Future<void> _updateNotification(LocationSnapshot snap) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Traknova – Live Location',
          notificationText:
              '${snap.latitude.toStringAsFixed(5)}, '
              '${snap.longitude.toStringAsFixed(5)}  '
              '${snap.speedKmh.toStringAsFixed(1)} km/h',
        );
      }
    } catch (_) {}
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

// ── Foreground task (top-level, AOT-safe) ────────────────────────────────────
@pragma('vm:entry-point')
void _foregroundCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

class _LocationTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    // No-op: location stream is driven by geolocator in the main isolate.
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // Keeps the process alive so the OS doesn't kill the app.
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    // No-op.
  }
}

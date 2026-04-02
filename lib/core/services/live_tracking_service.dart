import 'dart:async';
import 'dart:convert';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:latlong2/latlong.dart';
import '../models/tracker_point.dart';
import 'live_location_service.dart';

/// Connection credentials for the rr_new_git RabbitMQ server.
class TrackerServerConfig {
  final String host;
  final int port;
  final String username;
  final String password;

  /// Exchange name used by rr_new_git AMGLiveDataProducer (fanout).
  final String exchange;

  const TrackerServerConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.exchange = 'aionliveexchange',
  });
}

/// Live tracking state — passed to the ViewModel on every update.
class TrackingState {
  /// Latest position per deviceId (imei).
  final Map<String, TrackerPoint> trackers;

  /// Phone's own current position (null until first GPS fix).
  final TrackerPoint? phonePosition;

  /// Recent breadcrumb trail for the phone (newest last).
  final List<LatLng> phonePath;

  const TrackingState({
    required this.trackers,
    this.phonePosition,
    required this.phonePath,
  });

  TrackingState copyWith({
    Map<String, TrackerPoint>? trackers,
    TrackerPoint? phonePosition,
    List<LatLng>? phonePath,
  }) => TrackingState(
    trackers     : trackers      ?? this.trackers,
    phonePosition: phonePosition ?? this.phonePosition,
    phonePath    : phonePath     ?? this.phonePath,
  );
}

/// Aggregates ALL tracker data (hardware GPSs + this phone) from:
///   • RabbitMQ `aionliveexchange` (fanout, messages from rr_new_git server)
///   • [LiveLocationService] position stream (phone's own GPS)
///
/// Call [connect] to start. Subscribe to [stateStream] for updates.
///
/// This mirrors exactly what the web dashboard receives: every message
/// the server pushes to the exchange arrives here in real time.
class LiveTrackingService {
  static final LiveTrackingService _instance = LiveTrackingService._internal();
  factory LiveTrackingService() => _instance;
  LiveTrackingService._internal();

  // ── State ──────────────────────────────────────────────────────────────────
  TrackerServerConfig? _config;
  StompClient? _stompClient;
  StreamSubscription<LocationSnapshot>? _gpsSub;
  bool _isConnected  = false;
  bool _isRunning    = false;

  final Map<String, TrackerPoint> _trackers = {};
  TrackerPoint? _phonePosition;
  final List<LatLng> _phonePath = [];

  /// Maximum trail length for phone breadcrumbs.
  static const int _maxTrailPoints = 500;

  // ── Public stream ──────────────────────────────────────────────────────────
  final StreamController<TrackingState> _controller =
      StreamController<TrackingState>.broadcast();

  Stream<TrackingState> get stateStream => _controller.stream;
  bool get isConnected => _isConnected;
  bool get isRunning   => _isRunning;

  TrackingState get currentState => TrackingState(
    trackers     : Map.unmodifiable(_trackers),
    phonePosition: _phonePosition,
    phonePath    : List.unmodifiable(_phonePath),
  );

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Connect to the RabbitMQ exchange and start listening to phone GPS.
  ///
  /// Safe to call multiple times — reconnects if already stopped.
  Future<void> connect(TrackerServerConfig config) async {
    if (_isRunning) return;
    _config   = config;
    _isRunning = true;
    _trackers.clear();
    _phonePath.clear();

    print('🗺️ [LiveTrackingService] Connecting to ${config.host}:${config.port}');

    // ── RabbitMQ / STOMP ──────────────────────────────────────────────────
    _stompClient = StompClient(
      config: StompConfig(
        url: 'ws://${config.host}:${config.port}/ws',
        onConnect: _onStompConnected,
        beforeConnect: () async {
          print('🔄 [LiveTrackingService] Opening STOMP connection...');
        },
        onWebSocketError: (e) {
          print('❌ [LiveTrackingService] WebSocket error: $e');
          _isConnected = false;
        },
        onStompError: (StompFrame f) {
          print('❌ [LiveTrackingService] STOMP error: ${f.body}');
        },
        onDisconnect: (_) {
          print('🔌 [LiveTrackingService] Disconnected');
          _isConnected = false;
        },
        heartbeatIncoming: const Duration(seconds: 20),
        heartbeatOutgoing: const Duration(seconds: 20),
        connectionTimeout: const Duration(seconds: 30),
        stompConnectHeaders: {
          'login'   : config.username,
          'passcode': config.password,
          'host'    : config.host,
        },
      ),
    );
    _stompClient!.activate();

    // ── Phone GPS ─────────────────────────────────────────────────────────
    _gpsSub = LiveLocationService().locationStream.listen(_onPhonePosition);
    print('📍 [LiveTrackingService] Subscribed to phone GPS stream');
  }

  /// Disconnect everything and release resources.
  Future<void> disconnect() async {
    _isRunning   = false;
    _isConnected = false;
    await _gpsSub?.cancel();
    _gpsSub = null;
    _stompClient?.deactivate();
    _stompClient = null;
    print('🛑 [LiveTrackingService] Disconnected');
  }

  // ── STOMP handlers ─────────────────────────────────────────────────────────

  void _onStompConnected(StompFrame frame) {
    _isConnected = true;
    print('✅ [LiveTrackingService] STOMP connected');

    // Subscribe to the fanout exchange — RabbitMQ STOMP plugin will create a
    // temporary exclusive queue bound to the exchange automatically.
    _stompClient!.subscribe(
      destination: '/exchange/${_config!.exchange}',
      callback   : _onMessage,
      headers    : {
        'id' : 'live-tracking-${DateTime.now().millisecondsSinceEpoch}',
        'ack': 'auto',
      },
    );

    print('📡 [LiveTrackingService] Subscribed to /exchange/${_config!.exchange}');
  }

  void _onMessage(StompFrame frame) {
    if (frame.body == null || frame.body!.isEmpty) return;
    try {
      final json = jsonDecode(frame.body!) as Map<String, dynamic>;

      // Only process location-type messages
      final tc = (json['typeCode'] ?? '').toString().toUpperCase();
      if (tc != 'LOCATION' && tc != 'L' && tc != '12') return;

      final point = TrackerPoint.fromAnyJson(json);
      if (point == null) return;

      _trackers[point.deviceId] = point;
      _emit();

      print('📍 [LiveTrackingService] Tracker update: ${point.deviceId} '
          '@ ${point.position.latitude.toStringAsFixed(5)}, '
          '${point.position.longitude.toStringAsFixed(5)} '
          '${point.speed.toStringAsFixed(0)} km/h');
    } catch (e) {
      print('⚠️ [LiveTrackingService] Parse error: $e  body=${frame.body}');
    }
  }

  // ── Phone GPS handler ──────────────────────────────────────────────────────

  void _onPhonePosition(LocationSnapshot snap) {
    final point = TrackerPoint(
      deviceId : 'phone',
      position : LatLng(snap.latitude, snap.longitude),
      speed    : snap.speedKmh,
      bearing  : snap.bearing,
      accuracy : snap.accuracy,
      timestamp: snap.timestamp,
      protocol : 'phone',
    );
    _phonePosition = point;

    // Append to trail
    _phonePath.add(point.position);
    if (_phonePath.length > _maxTrailPoints) _phonePath.removeAt(0);

    _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(currentState);
  }
}

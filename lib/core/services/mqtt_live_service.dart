import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'device_data_service.dart';
import '../models/geofence_models.dart';

/// MQTT-based live tracking service that connects to the TrakNova
/// RabbitMQ broker (web-mqtt plugin on port 15676) and subscribes
/// to `AION/geo/device/#` for all device location updates.
///
/// This mirrors exactly what the web dashboard does.
class MqttLiveService {
  static final MqttLiveService _instance = MqttLiveService._internal();
  factory MqttLiveService() => _instance;
  MqttLiveService._internal();

  // ── Config (matching the web dashboard) ─────────────────────────────────
  static const String _broker   = 'app.traknova.co.uk';
  static const int    _port     = 15676;
  static const String _username = 'guest';
  static const String _password = 'guest';

  /// Subscribe to all device location updates.
  static const String _topicDevices = 'AION/geo/device/#';

  // ── State ───────────────────────────────────────────────────────────────
  MqttServerClient? _client;
  bool _isConnected = false;
  bool _isRunning   = false;

  final DeviceDataService _deviceDataService = DeviceDataService();

  // ── Public streams ──────────────────────────────────────────────────────
  final StreamController<void> _updateController =
      StreamController<void>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  // 🆕 GeoFence alert stream
  final StreamController<GeoFenceAlert> _geoFenceAlertController =
      StreamController<GeoFenceAlert>.broadcast();

  /// The username for subscribing to user-specific geofence topic
  String? _geoFenceUsername;

  /// Fires whenever any device position is updated via MQTT.
  Stream<void> get onDeviceUpdate => _updateController.stream;

  /// Fires on MQTT errors.
  Stream<String> get errorStream => _errorController.stream;

  /// Fires when connection state changes.
  Stream<bool> get connectionStream => _connectionController.stream;

  /// 🆕 Fires when a GeoFence alert is received via MQTT.
  Stream<GeoFenceAlert> get onGeoFenceAlert => _geoFenceAlertController.stream;

  bool get isConnected => _isConnected;
  bool get isRunning => _isRunning;

  DeviceDataService get deviceDataService => _deviceDataService;

  /// 🆕 Set the username for geofence alert subscription.
  /// Call this before connect() or call subscribeGeoFenceAlerts() after.
  void setGeoFenceUsername(String username) {
    _geoFenceUsername = username;
    // If already connected, subscribe immediately
    if (_isConnected && _client != null) {
      _subscribeGeoFence();
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Connect to the MQTT broker.
  /// Call this after DeviceDataService has loaded the device list.
  Future<void> connect() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      print('🔌 [MqttLiveService] Connecting to $_broker:$_port ...');

      final clientId = 'traknova_flutter_${Random().nextInt(99999)}';

      // IMPORTANT: Port MUST be in the wss:// URL itself.
      // MqttServerClient.withPort doesn't reliably inject it into
      // the WebSocket handshake URI — the library uses the URL as-is.
      _client = MqttServerClient.withPort(
        'wss://$_broker:$_port/ws', clientId, _port,
      );
      _client!.useWebSocket = true;
      _client!.useAlternateWebSocketImplementation = false;
      _client!.setProtocolV311();
      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      // NOTE: Do NOT set secure=true — the wss:// scheme handles TLS
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 30;
      _client!.connectTimeoutPeriod = 15000; // 15 s (ms)
      _client!.autoReconnect = true;
      _client!.resubscribeOnAutoReconnect = true;
      _client!.onAutoReconnect = _onAutoReconnect;
      _client!.onAutoReconnected = _onAutoReconnected;
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(_username, _password)
          .startClean();
          // Do NOT set withWillQos unless a will topic/message is also set.
          // MQTT spec: if WillFlag=false, WillQos MUST be 0.

      _client!.connectionMessage = connMessage;

      print('🔗 [MqttLiveService] Calling client.connect() ...');
      final result = await _client!.connect(_username, _password).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('⏱️ [MqttLiveService] Connection timeout after 20s');
          return null;
        },
      );

      if (result?.state == MqttConnectionState.connected) {
        print('✅ [MqttLiveService] Connected to MQTT broker');
        _isConnected = true;
        _connectionController.add(true);
        _subscribe();
      } else {
        print('❌ [MqttLiveService] Connection failed: ${result?.state}');
        _isConnected = false;
        _isRunning = false;
        _connectionController.add(false);
        _errorController.add('MQTT connection failed');
      }
    } catch (e, stack) {
      print('❌ [MqttLiveService] Connection error: $e');
      print('📋 [MqttLiveService] Stack: ${stack.toString().split('\n').take(5).join('\n')}');
      _isConnected = false;
      _isRunning = false;
      _connectionController.add(false);
      _errorController.add('MQTT error: $e');
    }
  }

  /// Disconnect from the MQTT broker.
  Future<void> disconnect() async {
    _isRunning = false;
    _isConnected = false;
    _client?.disconnect();
    _client = null;
    _connectionController.add(false);
    print('🛑 [MqttLiveService] Disconnected');
  }

  // ── Private ─────────────────────────────────────────────────────────────

  void _subscribe() {
    if (_client == null) return;

    // Subscribe to all device locations
    _client!.subscribe(_topicDevices, MqttQos.atMostOnce);
    print('📡 [MqttLiveService] Subscribed to $_topicDevices');

    // 🆕 Subscribe to geofence alerts if username is set
    _subscribeGeoFence();

    // Listen for incoming messages
    _client!.updates!.listen(_onMessage);
  }

  /// 🆕 Subscribe to geofence user topic
  void _subscribeGeoFence() {
    if (_client == null || _geoFenceUsername == null) return;
    final topic = 'AION/geo/user/$_geoFenceUsername';
    _client!.subscribe(topic, MqttQos.atLeastOnce);
    print('📡 [MqttLiveService] 🆕 Subscribed to GeoFence topic: $topic');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      try {
        final pubMsg = msg.payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          pubMsg.payload.message,
        );
        final topic = msg.topic;

        // Parse the JSON payload
        final data = jsonDecode(payload) as Map<String, dynamic>;

        // ─── 🆕 GeoFence Alert ───
        if (topic.startsWith('AION/geo/user/')) {
          try {
            final alert = GeoFenceAlert.fromMqttPayload(data);
            print('🚨 [MqttLiveService] GeoFence alert: '
                '${alert.vehicleNo} ${alert.mode} ${alert.fenceName}');
            if (!_geoFenceAlertController.isClosed) {
              _geoFenceAlertController.add(alert);
            }
          } catch (e) {
            print('⚠️ [MqttLiveService] GeoFence parse error: $e');
          }
          continue;
        }

        // ─── Device Location (existing) ───
        if (topic.startsWith('AION/geo/device/')) {
          final parts = topic.split('/');
          if (parts.length < 4) continue;
          final imei = parts.last;

          // Update the device in DeviceDataService (auto-creates if unknown)
          _deviceDataService.autoDiscoverFromMqtt(imei, data);

          // Notify listeners
          if (!_updateController.isClosed) {
            _updateController.add(null);
          }
        }
      } catch (e) {
        // Silently skip malformed messages
      }
    }
  }

  void _onConnected() {
    print('✅ [MqttLiveService] MQTT onConnected callback');
    _isConnected = true;
    _connectionController.add(true);
  }

  void _onDisconnected() {
    print('🔌 [MqttLiveService] MQTT onDisconnected callback');
    _isConnected = false;
    _connectionController.add(false);
  }

  void _onAutoReconnect() {
    print('🔄 [MqttLiveService] Auto-reconnecting...');
  }

  void _onAutoReconnected() {
    print('✅ [MqttLiveService] Auto-reconnected');
    _isConnected = true;
    _connectionController.add(true);
  }
}

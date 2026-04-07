import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'base_view_model.dart';
import '../models/traknova_device.dart';
import '../models/tracker_point.dart';
import '../services/mqtt_live_service.dart';
import '../services/live_location_service.dart';
import '../services/auth_service.dart';

/// ViewModel for the Live Tracking screen.
///
/// Orchestrates:
/// 1. MQTT connection — devices are auto-discovered from incoming messages
/// 2. Phone GPS position (LiveLocationService)
class LiveTrackingViewModel extends BaseViewModel {
  final MqttLiveService _mqttService = MqttLiveService();
  // AuthService kept for future use (e.g. logout button)
  // ignore: unused_field
  final AuthService _authService;

  StreamSubscription<void>? _mqttUpdateSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<LocationSnapshot>? _gpsSub;

  // Phone GPS state
  TrackerPoint? _phonePosition;
  final List<LatLng> _phonePath = [];
  static const int _maxTrailPoints = 500;

  // Selected device
  TraknovaDevice? _selectedDevice;

  // Filter
  String _filter = 'all'; // 'all', 'online', 'offline'
  String _searchQuery = '';

  // Loading/error state
  bool _devicesLoading = true;
  String? _connectionError;

  LiveTrackingViewModel(this._authService);

  // ── Getters ─────────────────────────────────────────────────────────────

  List<TraknovaDevice> get allDevices => _mqttService.deviceDataService.devices;

  List<TraknovaDevice> get filteredDevices {
    var list = allDevices;
    if (_filter == 'online') {
      list = list.where((d) => d.isOnline).toList();
    } else if (_filter == 'offline') {
      list = list.where((d) => !d.isOnline).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((d) =>
        d.vehicleNo.toLowerCase().contains(q) ||
        d.deviceCode.toLowerCase().contains(q) ||
        d.deviceName.toLowerCase().contains(q) ||
        d.imei.contains(q)
      ).toList();
    }
    return list;
  }

  int get onlineCount => allDevices.where((d) => d.isOnline).length;
  int get offlineCount => allDevices.where((d) => !d.isOnline).length;
  int get totalCount => allDevices.length;

  bool get isConnected => _mqttService.isConnected;
  bool get devicesLoading => _devicesLoading;
  String? get connectionError => _connectionError;

  TrackerPoint? get phonePosition => _phonePosition;
  List<LatLng> get phonePath => List.unmodifiable(_phonePath);

  TraknovaDevice? get selectedDevice => _selectedDevice;

  String get filter => _filter;
  String get searchQuery => _searchQuery;

  /// Forwards MQTT errors.
  Stream<String> get mqttErrorStream => _mqttService.errorStream;

  // ── Actions ─────────────────────────────────────────────────────────────

  void setFilter(String f) {
    _filter = f;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void selectDevice(TraknovaDevice? device) {
    _selectedDevice = device;
    notifyListeners();
  }

  LatLng? get focusPosition {
    if (_selectedDevice != null && _selectedDevice!.hasPosition) {
      return LatLng(_selectedDevice!.currentLatitude!, _selectedDevice!.currentLongitude!);
    }
    return _phonePosition?.position;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialize: connect MQTT (devices are auto-discovered from MQTT messages).
  Future<void> initialize() async {
    setLoading(true);
    _devicesLoading = false; // no blocking load — devices come in via MQTT
    _connectionError = null;
    notifyListeners();

    try {
      // Connect MQTT — devices are auto-discovered as messages arrive
      print('🔌 [LiveTrackingVM] Connecting to MQTT...');
      await _mqttService.connect();

      // Listen to MQTT updates
      _mqttUpdateSub = _mqttService.onDeviceUpdate.listen((_) {
        notifyListeners();
      });

      // Listen to connection changes
      _connectionSub = _mqttService.connectionStream.listen((connected) {
        notifyListeners();
      });

      // Listen to errors
      _errorSub = _mqttService.errorStream.listen((error) {
        _connectionError = error;
        notifyListeners();
      });

      // Start phone GPS
      _gpsSub = LiveLocationService().locationStream.listen(_onPhonePosition);

    } catch (e) {
      _connectionError = 'Failed to initialize: $e';
      print('❌ [LiveTrackingVM] Error: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> disconnect() async {
    await _mqttUpdateSub?.cancel();
    _mqttUpdateSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _errorSub?.cancel();
    _errorSub = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
    await _mqttService.disconnect();
    notifyListeners();
  }

  // ── Phone GPS handler ──────────────────────────────────────────────────

  void _onPhonePosition(LocationSnapshot snap) {
    _phonePosition = TrackerPoint(
      deviceId: 'phone',
      position: LatLng(snap.latitude, snap.longitude),
      speed: snap.speedKmh,
      bearing: snap.bearing,
      accuracy: snap.accuracy,
      timestamp: snap.timestamp,
      protocol: 'phone',
    );
    _phonePath.add(_phonePosition!.position);
    if (_phonePath.length > _maxTrailPoints) _phonePath.removeAt(0);
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

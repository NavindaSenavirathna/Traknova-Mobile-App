import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'base_view_model.dart';
import '../models/geofence_models.dart';
import '../models/traknova_device.dart';
import '../services/geofence_api_service.dart';
import '../services/geofence_detector.dart';
import '../services/geofence_notification_service.dart';
import '../services/auth_service.dart';
import '../services/device_data_service.dart';

/// ViewModel for all GeoFence screens.
///
/// Manages:
/// - Loading geofence configs from API
/// - Device-specific fences
/// - Violation history
/// - Alert history
/// - Report generation
/// - Client-side detection state
/// - Filter/search state
class GeoFenceViewModel extends BaseViewModel {
  final AuthService _authService;
  final GeoFenceApiService _api = GeoFenceApiService();
  final GeoFenceDetector _detector = GeoFenceDetector();
  final GeoFenceNotificationService _notifService =
      GeoFenceNotificationService();
  final DeviceDataService _deviceDataService = DeviceDataService();

  StreamSubscription<void>? _notifSub;

  // ── State ──────────────────────────────────────────────────────────────

  // All geofence designs
  List<GeoFenceConfig> _allFences = [];
  bool _fencesLoading = false;
  String? _fencesError;

  // Device-specific configs
  List<DeviceGeoFence> _deviceFences = [];
  bool _deviceFencesLoading = false;

  // Selected fence for detail view
  GeoFenceConfig? _selectedFence;

  // Violation history
  List<GeoFenceViolation> _violations = [];
  bool _violationsLoading = false;

  // Alert history
  List<GeoFenceAlert> _alertHistory = [];
  bool _alertsLoading = false;

  // Report
  List<GeoFenceReportEntry> _reportEntries = [];
  bool _reportLoading = false;

  // Filters
  String _filterType = 'all'; // 'all', 'AREA', 'ROUTE'
  String _filterMode = 'all'; // 'all', 'DEVICE', 'REGION'
  String _searchQuery = '';

  // Tab state
  int _currentTab = 0; // 0=Map, 1=Alerts, 2=Report

  // Map display
  bool _showPolygonsOnMap = true;

  // Prevent double initialization
  bool _initialized = false;
  bool _isDisposed = false;

  GeoFenceViewModel(this._authService);

  // ── Getters ────────────────────────────────────────────────────────────

  List<GeoFenceConfig> get allFences => _allFences;
  bool get fencesLoading => _fencesLoading;
  String? get fencesError => _fencesError;

  List<GeoFenceConfig> get filteredFences {
    var list = _allFences;
    if (_filterType != 'all') {
      list = list.where((f) => f.modal == _filterType).toList();
    }
    if (_filterMode != 'all') {
      list = list.where((f) => f.mode == _filterMode).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((f) =>
              f.name.toLowerCase().contains(q) ||
              f.code.toLowerCase().contains(q) ||
              f.desc?.toLowerCase().contains(q) == true)
          .toList();
    }
    return list;
  }

  List<GeoFenceConfig> get activeFences =>
      _allFences.where((f) => f.isActive).toList();

  int get totalFences => _allFences.length;
  int get activeFenceCount => activeFences.length;
  int get areaFenceCount =>
      _allFences.where((f) => f.modal == 'AREA').length;
  int get routeFenceCount =>
      _allFences.where((f) => f.modal == 'ROUTE').length;

  List<DeviceGeoFence> get deviceFences => _deviceFences;
  bool get deviceFencesLoading => _deviceFencesLoading;

  GeoFenceConfig? get selectedFence => _selectedFence;

  List<GeoFenceViolation> get violations => _violations;
  bool get violationsLoading => _violationsLoading;

  List<GeoFenceAlert> get alertHistory => _alertHistory;
  bool get alertsLoading => _alertsLoading;

  List<GeoFenceAlert> get liveAlerts => _notifService.liveAlerts;
  int get unreadAlertCount => _notifService.unreadCount;

  List<GeoFenceReportEntry> get reportEntries => _reportEntries;
  bool get reportLoading => _reportLoading;

  String get filterType => _filterType;
  String get filterMode => _filterMode;
  String get searchQuery => _searchQuery;
  int get currentTab => _currentTab;
  bool get showPolygonsOnMap => _showPolygonsOnMap;

  GeoFenceDetector get detector => _detector;
  GeoFenceNotificationService get notifService => _notifService;

  List<TraknovaDevice> get devices => _deviceDataService.devices;

  // ── Actions ────────────────────────────────────────────────────────────

  void setFilterType(String type) {
    _filterType = type;
    notifyListeners();
  }

  void setFilterMode(String mode) {
    _filterMode = mode;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setCurrentTab(int tab) {
    _currentTab = tab;
    notifyListeners();
  }

  void selectFence(GeoFenceConfig? fence) {
    _selectedFence = fence;
    notifyListeners();
  }

  void togglePolygonsOnMap(bool show) {
    _showPolygonsOnMap = show;
    notifyListeners();
  }

  void clearUnreadAlerts() {
    _notifService.clearUnreadCount();
    notifyListeners();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Initialize: ensure API session and load fences
  Future<void> initialize() async {
    if (_initialized || _isDisposed) return;
    _initialized = true;
    _fencesLoading = true;
    _fencesError = null;
    notifyListeners();

    try {
      // Ensure we have a web session for API calls
      final sessionOk = await _api.ensureSession(_authService);
      if (!sessionOk) {
        _fencesError = 'Failed to establish session';
        _fencesLoading = false;
        _initialized = false; // Allow retry
        notifyListeners();
        return;
      }

      // Load all geofence designs
      _allFences = await _api.getAllDesigns();
      print('✅ [GeoFenceVM] Loaded ${_allFences.length} geofence designs');

      // Listen for notification updates
      _notifSub = _notifService.onUpdate.listen((_) {
        notifyListeners();
      });
    } catch (e) {
      _fencesError = 'Error: $e';
      print('❌ [GeoFenceVM] Initialize error: $e');
    } finally {
      _fencesLoading = false;
      notifyListeners();
    }
  }

  /// Load device-specific geofence configs
  Future<void> loadDeviceFences(List<String> deviceCodes) async {
    _deviceFencesLoading = true;
    notifyListeners();

    try {
      _deviceFences = await _api.getDeviceGeoConfigs(
        deviceCodes: deviceCodes,
      );
    } catch (e) {
      print('❌ [GeoFenceVM] loadDeviceFences error: $e');
    } finally {
      _deviceFencesLoading = false;
      notifyListeners();
    }
  }

  /// Load violation history for a device + fence config
  Future<void> loadViolationHistory({
    required String deviceCode,
    required String configCode,
    String? date,
  }) async {
    _violationsLoading = true;
    notifyListeners();

    try {
      _violations = await _api.getViolationHistory(
        deviceCode: deviceCode,
        configCode: configCode,
        date: date,
      );
    } catch (e) {
      print('❌ [GeoFenceVM] loadViolationHistory error: $e');
    } finally {
      _violationsLoading = false;
      notifyListeners();
    }
  }

  /// Load alert history for date range
  Future<void> loadAlertHistory({
    required String from,
    required String to,
    int limit = 100,
  }) async {
    _alertsLoading = true;
    notifyListeners();

    try {
      _alertHistory = await _api.getAlertHistory(
        from: from,
        to: to,
        limit: limit,
      );
    } catch (e) {
      print('❌ [GeoFenceVM] loadAlertHistory error: $e');
    } finally {
      _alertsLoading = false;
      notifyListeners();
    }
  }

  /// Load today's alert history
  Future<void> loadTodayAlerts() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await loadAlertHistory(
      from: '$dateStr 00:00:00',
      to: '$dateStr 23:59:59',
    );
  }

  /// Generate report
  Future<void> generateReport({
    required String fromDate,
    required String fromTime,
    required String toDate,
    required String toTime,
    String? code,
    List<String>? modes,
    List<String>? vehicleCodes,
  }) async {
    _reportLoading = true;
    notifyListeners();

    try {
      _reportEntries = await _api.getReport(
        fromDate: fromDate,
        fromTime: fromTime,
        toDate: toDate,
        toTime: toTime,
        code: code,
        modes: modes,
        vehicleCodes: vehicleCodes,
      );
    } catch (e) {
      print('❌ [GeoFenceVM] generateReport error: $e');
    } finally {
      _reportLoading = false;
      notifyListeners();
    }
  }

  /// Client-side: check a device against all loaded fences
  void checkDevicePosition({
    required String deviceCode,
    required String vehicleNo,
    required double lat,
    required double lng,
  }) {
    final alerts = _detector.checkDevice(
      deviceCode: deviceCode,
      vehicleNo: vehicleNo,
      lat: lat,
      lng: lng,
      activeFences: activeFences,
    );

    for (final alert in alerts) {
      _notifService.showAlert(alert);
    }
  }

  /// Get center point for a fence boundary (for map focus)
  LatLng? getFenceCenter(GeoFenceConfig fence) {
    if (fence.boundary.isEmpty) return null;
    double sumLat = 0, sumLng = 0;
    for (final p in fence.boundary) {
      sumLat += p[0];
      sumLng += p[1];
    }
    return LatLng(
        sumLat / fence.boundary.length, sumLng / fence.boundary.length);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _notifSub?.cancel();
    _detector.reset();
    super.dispose();
  }
}

import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'base_view_model.dart';
import '../models/tracker_point.dart';
import '../services/live_tracking_service.dart';

class LiveTrackingViewModel extends BaseViewModel {
  final LiveTrackingService _service = LiveTrackingService();

  TrackingState _state = const TrackingState(
    trackers: {},
    phonePath: [],
  );

  StreamSubscription<TrackingState>? _stateSub;

  /// Flat list of all remote trackers (for the map markers).
  List<TrackerPoint> get trackers => _state.trackers.values.toList();

  /// Phone's own position, if GPS is active.
  TrackerPoint? get phonePosition => _state.phonePosition;

  /// Breadcrumb trail for the phone.
  List<LatLng> get phonePath => _state.phonePath;

  /// True when STOMP is connected to RabbitMQ.
  bool get isConnected => _service.isConnected;

  /// Selected tracker to focus on — null means follow phone.
  TrackerPoint? _selectedTracker;
  TrackerPoint? get selectedTracker => _selectedTracker;

  void selectTracker(TrackerPoint? t) {
    _selectedTracker = t;
    notifyListeners();
  }

  /// The position the map should centre on.
  LatLng? get focusPosition =>
      _selectedTracker?.position ?? _state.phonePosition?.position;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> connect(TrackerServerConfig config) async {
    setLoading(true);
    try {
      await _service.connect(config);
      _stateSub = _service.stateStream.listen((s) {
        _state = s;
        notifyListeners();
      });
    } catch (e) {
      setError('Could not connect to tracking server: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> disconnect() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _service.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _service.disconnect();
    super.dispose();
  }
}

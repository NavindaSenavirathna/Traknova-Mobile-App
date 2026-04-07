import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'live_location_service.dart';

/// Connects the phone to the rr_new_git TCP tracking server using the
/// H02 ASCII protocol — the same protocol used by TK100 hardware trackers.
///
/// The phone acts as a software GPS tracker: it opens a persistent raw TCP
/// socket to port 4445, subscribes to [LiveLocationService.locationStream],
/// and sends each qualifying fix as an H02 packet.
///
/// H02 packet format:
///   *HQ,{IMEI},V1,{HHMMSS},A,{LATDDMM.MMMM},{N|S},{LONDDMM.MMMM},{E|W},{SPEED_KN},{DIR},{DDMMYY},FFFFFFFF#
///
/// Because phones don't expose a real IMEI, a persistent 15-digit virtual ID
/// is generated once and stored in SharedPreferences under [_deviceIdKey].
///
/// Usage:
///   final tracker = locator<TcpTrackerService>();
///   await tracker.start();          // connect & begin sending
///   await tracker.stop();           // disconnect
///   tracker.deviceId                // the virtual IMEI for this device
///   tracker.isConnected             // live connection status
class TcpTrackerService {
  static final TcpTrackerService _instance = TcpTrackerService._internal();
  factory TcpTrackerService() => _instance;
  TcpTrackerService._internal();

  // ── Server config ─────────────────────────────────────────────────────────

  /// Traknova production server hostname.
  static const String _defaultHost = 'app.traknova.co.uk';
  static const int _defaultPort = 4445;

  /// SharedPreferences key for the persistent virtual IMEI.
  static const String _deviceIdKey = 'tcp_tracker_device_id';

  /// Maximum back-off ceiling for reconnect delays (seconds).
  static const int _maxReconnectDelaySeconds = 60;

  // ── State ─────────────────────────────────────────────────────────────────
  Socket? _socket;
  StreamSubscription<LocationSnapshot>? _locationSub;
  bool _isRunning = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  String? _deviceId;
  String? _host;
  int? _port;
  int _packetsSent = 0;

  bool get isRunning => _isRunning;
  bool get isConnected => _isConnected;
  String? get deviceId => _deviceId;
  int get packetsSent => _packetsSent;

  // ── Virtual IMEI ──────────────────────────────────────────────────────────

  /// Returns (or lazily generates) the 15-digit virtual IMEI for this install.
  ///
  /// This ID is stable across app restarts. Reinstalling the app creates a
  /// new one. The ID must be in the [devices.json] whitelist on the server
  /// side to be tracked.
  Future<String> getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? stored = prefs.getString(_deviceIdKey);
    if (stored == null) {
      final rng = Random.secure();
      stored = List.generate(15, (_) => rng.nextInt(10)).join();
      await prefs.setString(_deviceIdKey, stored);
      print('📱 TcpTrackerService: Generated virtual IMEI: $stored');
    }
    _deviceId = stored;
    return _deviceId!;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start the TCP tracker.
  ///
  /// [host] and [port] default to [_defaultHost] / [_defaultPort].
  /// Safe to call multiple times — subsequent calls are ignored if already
  /// running.
  Future<void> start({String? host, int? port}) async {
    if (_isRunning) {
      print('⚠️ TcpTrackerService: Already running');
      return;
    }
    _host = host ?? _defaultHost;
    _port = port ?? _defaultPort;
    _isRunning = true;
    _reconnectAttempts = 0;
    _packetsSent = 0;

    _deviceId = await getOrCreateDeviceId();
    print('🔌 TcpTrackerService: Starting — virtual IMEI: $_deviceId → $_host:$_port');

    await _connect();
  }

  /// Stop the tracker and close the TCP connection.
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _isConnected = false;

    await _locationSub?.cancel();
    _locationSub = null;

    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;

    print('🛑 TcpTrackerService: Stopped. Packets sent this session: $_packetsSent');
  }

  // ── Connection management ─────────────────────────────────────────────────

  Future<void> _connect() async {
    if (!_isRunning) return;

    try {
      print(
        '🔄 TcpTrackerService: Connecting to $_host:$_port '
        '(attempt ${_reconnectAttempts + 1})…',
      );

      _socket = await Socket.connect(
        _host!,
        _port!,
        timeout: const Duration(seconds: 10),
      );

      _isConnected = true;
      _reconnectAttempts = 0;

      _socket!.listen(
        _onServerData,
        onError: (Object e) {
          print('❌ TcpTrackerService: Socket error – $e');
          _handleDisconnect();
        },
        onDone: () {
          print('🔌 TcpTrackerService: Server closed the connection');
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      print('✅ TcpTrackerService: Connected to $_host:$_port');

      // Subscribe to the existing LiveLocationService stream.
      // LiveLocationService is a singleton, so we share its GPS fixes
      // without starting a second GPS subscription.
      await _locationSub?.cancel();
      _locationSub = LiveLocationService().locationStream.listen(
        _onLocation,
        onError: (Object e) => print('❌ TcpTrackerService: Location stream error – $e'),
        cancelOnError: false,
      );
    } catch (e) {
      print('❌ TcpTrackerService: Connection failed – $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _socket = null;
    _locationSub?.cancel();
    _locationSub = null;
    if (_isRunning) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_isRunning) return;
    _reconnectAttempts++;
    // Exponential back-off: 2 → 4 → 8 → … → 60 seconds
    final delay = min(
      pow(2, _reconnectAttempts).toInt(),
      _maxReconnectDelaySeconds,
    );
    print('⏳ TcpTrackerService: Reconnecting in ${delay}s…');
    Future.delayed(Duration(seconds: delay), _connect);
  }

  // ── Server response ───────────────────────────────────────────────────────

  /// The H02 server sends no meaningful ACK, but log it for visibility.
  void _onServerData(List<int> data) {
    print('📥 TcpTrackerService: Server data: ${String.fromCharCodes(data)}');
  }

  // ── Location → H02 packet → TCP ───────────────────────────────────────────

  void _onLocation(LocationSnapshot snap) {
    if (!_isConnected || _socket == null) {
      print('⚠️ TcpTrackerService: Skipping send – not connected');
      return;
    }
    final packet = _buildH02Packet(snap);
    _sendPacket(packet);
  }

  void _sendPacket(String packet) {
    try {
      _socket!.write(packet);
      _packetsSent++;
      print('📤 TcpTrackerService [#$_packetsSent] → $packet');
    } catch (e) {
      print('❌ TcpTrackerService: Write error – $e');
      _handleDisconnect();
    }
  }

  // ── H02 packet builder ────────────────────────────────────────────────────

  /// Convert decimal degrees to H02 coordinate notation (DDMM.MMMM).
  ///
  /// [degreeDigits] is 2 for latitude (max 90°) and 3 for longitude (max 180°).
  ///
  ///   6.9275°  →  0655.6500   (lat)
  ///   79.8612° →  07951.6720  (lon)
  String _toH02Coord(double decimalDegrees, int degreeDigits) {
    final abs = decimalDegrees.abs();
    final degrees = abs.floor();
    final minutes = (abs - degrees) * 60.0; // fractional minutes
    final degStr = degrees.toString().padLeft(degreeDigits, '0');
    // Pad minutes so the integer part is always 2 digits (e.g. 09.1234)
    final minInt = minutes.floor().toString().padLeft(2, '0');
    final minFrac = ((minutes - minutes.floor()) * 10000)
        .round()
        .toString()
        .padLeft(4, '0');
    return '$degStr$minInt.$minFrac';
  }

  /// Build a complete H02 ASCII packet that the rr_new_git TCP server
  /// will accept and decode identically to a TK100 hardware tracker.
  ///
  /// Field mapping (matches [tk_validator_h02.js]):
  ///   [0]  *HQ
  ///   [1]  IMEI (virtual)
  ///   [2]  V1 (protocol version)
  ///   [3]  HHMMSS  (UTC)
  ///   [4]  A (valid fix)
  ///   [5]  LATDDMM.MMMM
  ///   [6]  N | S
  ///   [7]  LONDDMM.MMMM
  ///   [8]  E | W
  ///   [9]  speed in knots
  ///   [10] bearing (degrees)
  ///   [11] DDMMYY  (UTC)
  ///   [12] FFFFFFFF (status flags – all on)
  String _buildH02Packet(LocationSnapshot snap) {
    final utc = snap.timestamp.toUtc();

    final hh = utc.hour.toString().padLeft(2, '0');
    final mn = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    final time = '$hh$mn$ss'; // HHMMSS

    final dd = utc.day.toString().padLeft(2, '0');
    final mo = utc.month.toString().padLeft(2, '0');
    final yy = (utc.year % 100).toString().padLeft(2, '0');
    final date = '$dd$mo$yy'; // DDMMYY

    final lat = _toH02Coord(snap.latitude, 2);
    final ns = snap.latitude >= 0 ? 'N' : 'S';

    final lon = _toH02Coord(snap.longitude, 3);
    final ew = snap.longitude >= 0 ? 'E' : 'W';

    // Geolocator gives speed in m/s; H02/server expects knots
    final speedKnots = (snap.speed / 1.852).toStringAsFixed(2);

    final bearing = snap.bearing.round().toString();

    return '*HQ,$_deviceId,V1,$time,A,$lat,$ns,$lon,$ew,$speedKnots,$bearing,$date,FFFFFFFF#';
  }
}

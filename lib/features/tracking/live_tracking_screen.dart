import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/tracker_point.dart';
import '../../core/services/live_tracking_service.dart';
import '../../core/services/live_location_service.dart';
import '../../core/viewmodels/live_tracking_viewmodel.dart';
import '../../core/services/locator.dart';
import '../../core/services/api_service.dart';

// ─── Entry point ─────────────────────────────────────────────────────────────

class LiveTrackingScreen extends StatefulWidget {
  /// Optional: pre-supply server config (e.g. from the trip API's liveAmq).
  final TrackerServerConfig? initialConfig;

  const LiveTrackingScreen({super.key, this.initialConfig});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with TickerProviderStateMixin {

  // ── Map ──────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  bool _followPhone = true;
  double _currentZoom = 15.0;
  LatLng? _lastCentered;

  // ── ViewModel ─────────────────────────────────────────────────────────────
  final LiveTrackingViewModel _vm = LiveTrackingViewModel();

  // ── Pulsing animation for phone marker ───────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── Selected tracker info sheet ──────────────────────────────────────────
  TrackerPoint? _infoTracker;

  // ── Config ────────────────────────────────────────────────────────────────
  final TextEditingController _hostCtrl   = TextEditingController(text: '68.183.35.63');
  final TextEditingController _portCtrl   = TextEditingController(text: '15674');
  final TextEditingController _userCtrl   = TextEditingController(text: 'guest');
  final TextEditingController _passCtrl   = TextEditingController(text: 'guest');
  bool _configSaved = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _vm.addListener(_onVmUpdate);

    // Wire phone GPS into the LiveLocationService
    LiveLocationService().setApiService(locator<ApiService>());

    if (widget.initialConfig != null) {
      _applyConfig(widget.initialConfig!);
    } else {
      _loadSavedConfig();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _vm.removeListener(_onVmUpdate);
    _vm.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Config helpers ────────────────────────────────────────────────────────

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final host  = prefs.getString('lt_host');
    if (host != null) {
      final cfg = TrackerServerConfig(
        host    : host,
        port    : prefs.getInt('lt_port')     ?? 15674,
        username: prefs.getString('lt_user')  ?? 'guest',
        password: prefs.getString('lt_pass')  ?? 'guest',
      );
      _hostCtrl.text = cfg.host;
      _portCtrl.text = cfg.port.toString();
      _userCtrl.text = cfg.username;
      _passCtrl.text = cfg.password;
      _applyConfig(cfg);
    } else {
      // Show config dialog on first open
      WidgetsBinding.instance.addPostFrameCallback((_) => _showConfigDialog());
    }
  }

  Future<void> _saveConfig(TrackerServerConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lt_host', cfg.host);
    await prefs.setInt   ('lt_port', cfg.port);
    await prefs.setString('lt_user', cfg.username);
    await prefs.setString('lt_pass', cfg.password);
  }

  void _applyConfig(TrackerServerConfig cfg) {
    _configSaved = true;
    // Start phone GPS
    LiveLocationService().start();
    // Connect to the tracker exchange
    _vm.connect(cfg);
  }

  // ── ViewModel listener ────────────────────────────────────────────────────

  void _onVmUpdate() {
    if (!mounted) return;
    setState(() {});

    // Auto-follow phone
    if (_followPhone && _vm.phonePosition != null) {
      final pos = _vm.phonePosition!.position;
      if (_lastCentered == null ||
          const Distance().as(LengthUnit.Meter, _lastCentered!, pos) > 10) {
        _lastCentered = pos;
        try {
          _mapController.move(pos, _currentZoom);
          _lastCentered = pos;
        } catch (_) {}
      }
    }
  }

  // ── Map interaction ───────────────────────────────────────────────────────

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMove && event.source != MapEventSource.mapController) {
      // User dragged — stop following
      setState(() => _followPhone = false);
    }
    if (event is MapEventScrollWheelZoom || event is MapEventDoubleTapZoom) {
      _currentZoom = _mapController.camera.zoom;
    }
  }

  void _recenter() {
    final pos = _vm.focusPosition;
    if (pos != null) {
      _mapController.move(pos, _currentZoom);
      _lastCentered = _mapController.camera.center;
    }
    setState(() => _followPhone = true);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          if (_vm.trackers.isNotEmpty) _buildTrackerList(),
          _buildBottomHud(),
          if (_infoTracker != null) _buildInfoSheet(_infoTracker!),
          _buildFabs(),
        ],
      ),
    );
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final phone    = _vm.phonePosition;
    final trackers = _vm.trackers;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: phone?.position ?? const LatLng(51.5074, -0.1278),
        initialZoom  : _currentZoom,
        maxZoom: 19,
        minZoom: 3,
        onMapEvent: _onMapEvent,
      ),
      children: [
        // OSM tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.traknova.drivemaster',
          maxZoom: 19,
        ),

        // Phone breadcrumb trail
        if (_vm.phonePath.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points      : _vm.phonePath,
                strokeWidth : 3.0,
                color       : const Color(0xFF00C896).withOpacity(0.7),
              ),
            ],
          ),

        // Tracker position markers
        MarkerLayer(
          markers: trackers.map((t) => _trackerMarker(t)).toList(),
        ),

        // Phone accuracy circle
        if (phone != null && (phone.accuracy ?? 0) > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point  : phone.position,
                radius : phone.accuracy!,
                useRadiusInMeter: true,
                color  : Colors.blue.withOpacity(0.15),
                borderColor: Colors.blue.withOpacity(0.4),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),

        // Phone position marker
        if (phone != null)
          MarkerLayer(
            markers: [_phoneMarker(phone)],
          ),
      ],
    );
  }

  Marker _phoneMarker(TrackerPoint p) => Marker(
    point : p.position,
    width : 48,
    height: 48,
    child : AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing ring
          Container(
            width : 40 * _pulseAnim.value,
            height: 40 * _pulseAnim.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withOpacity(0.2 * (1 - _pulseAnim.value + 0.4)),
            ),
          ),
          // Arrow (rotates with bearing)
          Transform.rotate(
            angle: p.bearing * math.pi / 180,
            child: const Icon(
              Icons.navigation,
              color: Colors.blue,
              size: 28,
            ),
          ),
        ],
      ),
    ),
  );

  Marker _trackerMarker(TrackerPoint t) => Marker(
    point : t.position,
    width : 56,
    height: 56,
    child : GestureDetector(
      onTap: () => setState(() {
        _infoTracker = (_infoTracker?.deviceId == t.deviceId) ? null : t;
        if (_infoTracker != null) {
          _followPhone = false;
          _mapController.move(t.position, math.max(_currentZoom, 15.0));
        }
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _trackerColor(t.protocol),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: _trackerColor(t.protocol).withOpacity(0.5),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(
              t.protocol == 'mobile' ? Icons.smartphone : Icons.directions_car,
              color: Colors.white,
              size: 18,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${t.speed.toStringAsFixed(0)} km/h',
              style: const TextStyle(color: Colors.white, fontSize: 9),
            ),
          ),
        ],
      ),
    ),
  );

  Color _trackerColor(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'mobile': return Colors.orange;
      case 'h02':    return Colors.green;
      default:       return const Color(0xFF2979FF);
    }
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() => Positioned(
    top: 0, left: 0, right: 0,
    child: SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xEE0F1923),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
            const Text(
              'Live Tracking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            // Connection status
            _StatusBadge(connected: _vm.isConnected),
            const SizedBox(width: 8),
            // Tracker count
            if (_vm.trackers.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.withOpacity(0.5)),
                ),
                child: Text(
                  '${_vm.trackers.length} tracker${_vm.trackers.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.lightBlue, fontSize: 11),
                ),
              ),
            const SizedBox(width: 8),
            // Settings
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _showConfigDialog,
            ),
          ],
        ),
      ),
    ),
  );

  // ── Tracker list (slide from right) ──────────────────────────────────────

  Widget _buildTrackerList() => Positioned(
    top: 100,
    right: 12,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: _vm.trackers.map((t) {
        final isSelected = _infoTracker?.deviceId == t.deviceId;
        return GestureDetector(
          onTap: () {
            setState(() {
              _infoTracker = isSelected ? null : t;
              _followPhone = false;
            });
            if (!isSelected) {
              _mapController.move(t.position, math.max(_currentZoom, 15.0));
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? _trackerColor(t.protocol).withOpacity(0.25)
                  : const Color(0xCC0F1923),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? _trackerColor(t.protocol)
                    : Colors.white12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  t.protocol == 'mobile' ? Icons.smartphone : Icons.gps_fixed,
                  color: _trackerColor(t.protocol),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  t.deviceId.length > 10
                      ? '…${t.deviceId.substring(t.deviceId.length - 8)}'
                      : t.deviceId,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 6),
                Text(
                  '${t.speed.toStringAsFixed(0)} km/h',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );

  // ── Bottom HUD ────────────────────────────────────────────────────────────

  Widget _buildBottomHud() {
    final phone = _vm.phonePosition;
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        decoration: const BoxDecoration(
          color: Color(0xEE0F1923),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: phone == null
            ? const _AcquiringGpsRow()
            : _PhoneHudRow(phone: phone),
      ),
    );
  }

  // ── Tracker info sheet ────────────────────────────────────────────────────

  Widget _buildInfoSheet(TrackerPoint t) => Positioned(
    bottom: 110,
    left: 12,
    right: 12,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xF00F1923),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _trackerColor(t.protocol).withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                t.protocol == 'mobile' ? Icons.smartphone : Icons.directions_car,
                color: _trackerColor(t.protocol),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.deviceId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _infoTracker = null),
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _InfoChip(Icons.speed, '${t.speed.toStringAsFixed(1)} km/h', 'Speed'),
              const SizedBox(width: 12),
              _InfoChip(Icons.explore, '${t.bearing.toStringAsFixed(0)}°', 'Heading'),
              const SizedBox(width: 12),
              _InfoChip(Icons.wifi_tethering, t.protocol, 'Protocol'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white38, size: 12),
              const SizedBox(width: 4),
              Text(
                '${t.position.latitude.toStringAsFixed(6)}, '
                '${t.position.longitude.toStringAsFixed(6)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
              Text(
                _relativeTime(t.timestamp),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60)  return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  // ── FABs ───────────────────────────────────────────────────────────────────

  Widget _buildFabs() => Positioned(
    right: 12,
    bottom: 120,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Centre on phone
        FloatingActionButton.small(
          heroTag: 'center',
          backgroundColor: _followPhone
              ? const Color(0xFF00C896)
              : const Color(0xFF1E2D3D),
          onPressed: _recenter,
          child: Icon(
            Icons.my_location,
            color: _followPhone ? Colors.white : Colors.white70,
            size: 20,
          ),
        ),
        const SizedBox(height: 8),
        // Zoom in
        FloatingActionButton.small(
          heroTag: 'zoomin',
          backgroundColor: const Color(0xFF1E2D3D),
          onPressed: () {
            _currentZoom = (_currentZoom + 1).clamp(3.0, 19.0);
            _mapController.move(_mapController.camera.center, _currentZoom);
          },
          child: const Icon(Icons.add, color: Colors.white70, size: 20),
        ),
        const SizedBox(height: 8),
        // Zoom out
        FloatingActionButton.small(
          heroTag: 'zoomout',
          backgroundColor: const Color(0xFF1E2D3D),
          onPressed: () {
            _currentZoom = (_currentZoom - 1).clamp(3.0, 19.0);
            _mapController.move(_mapController.camera.center, _currentZoom);
          },
          child: const Icon(Icons.remove, color: Colors.white70, size: 20),
        ),
      ],
    ),
  );

  // ── Config dialog ─────────────────────────────────────────────────────────

  void _showConfigDialog() {
    showDialog(
      context: context,
      barrierDismissible: _configSaved,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2733),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Tracker Server',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the RabbitMQ server details for live tracking.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _ConfigField(controller: _hostCtrl, label: 'Host / IP', hint: '192.168.1.100'),
              const SizedBox(height: 10),
              _ConfigField(controller: _portCtrl, label: 'WebSocket Port', hint: '15674', keyboard: TextInputType.number),
              const SizedBox(height: 10),
              _ConfigField(controller: _userCtrl, label: 'Username', hint: 'guest'),
              const SizedBox(height: 10),
              _ConfigField(controller: _passCtrl, label: 'Password', hint: 'guest', obscure: true),
            ],
          ),
        ),
        actions: [
          if (_configSaved)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final cfg = TrackerServerConfig(
                host    : _hostCtrl.text.trim(),
                port    : int.tryParse(_portCtrl.text.trim()) ?? 15674,
                username: _userCtrl.text.trim(),
                password: _passCtrl.text.trim(),
              );
              await _saveConfig(cfg);
              // Dismiss dialog before async operations
              if (ctx.mounted) Navigator.pop(ctx);
              // Disconnect then reconnect with new config
              await _vm.disconnect();
              _applyConfig(cfg);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable small widgets ───────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool connected;
  const _StatusBadge({required this.connected});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? Colors.greenAccent : Colors.red,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        connected ? 'LIVE' : 'OFFLINE',
        style: TextStyle(
          color: connected ? Colors.greenAccent : Colors.red,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

class _AcquiringGpsRow extends StatelessWidget {
  const _AcquiringGpsRow();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white38,
        ),
      ),
      SizedBox(width: 10),
      Text('Acquiring GPS…', style: TextStyle(color: Colors.white54, fontSize: 13)),
    ],
  );
}

class _PhoneHudRow extends StatelessWidget {
  final TrackerPoint phone;
  const _PhoneHudRow({required this.phone});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // Speed (large)
      Text(
        phone.speed.toStringAsFixed(0),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 42,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
      const SizedBox(width: 4),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 16),
          Text('km/h', style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
      const SizedBox(width: 24),
      // Metrics
      Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _HudMetric(
              icon: Icons.explore,
              value: '${phone.bearing.toStringAsFixed(0)}°',
              label: 'Heading',
            ),
            _HudMetric(
              icon: Icons.gps_fixed,
              value: phone.accuracy != null
                  ? '±${phone.accuracy!.toStringAsFixed(0)}m'
                  : '—',
              label: 'Accuracy',
              color: (phone.accuracy ?? 100) <= 20
                  ? Colors.greenAccent
                  : (phone.accuracy ?? 100) <= 50
                      ? Colors.orangeAccent
                      : Colors.redAccent,
            ),
            _HudMetric(
              icon: Icons.location_on,
              value: '${phone.position.latitude.toStringAsFixed(4)}',
              label: 'Latitude',
            ),
            _HudMetric(
              icon: Icons.location_on_outlined,
              value: '${phone.position.longitude.toStringAsFixed(4)}',
              label: 'Longitude',
            ),
          ],
        ),
      ),
    ],
  );
}

class _HudMetric extends StatelessWidget {
  final IconData icon;
  final String  value;
  final String  label;
  final Color   color;

  const _HudMetric({
    required this.icon,
    required this.value,
    required this.label,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color.withOpacity(0.7), size: 14),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      Text(label,  style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ],
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   value;
  final String   label;
  const _InfoChip(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, color: Colors.white54, size: 12),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
    ],
  );
}

class _ConfigField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final TextInputType? keyboard;
  final bool obscure;
  const _ConfigField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboard,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller    : controller,
    keyboardType  : keyboard,
    obscureText   : obscure,
    style         : const TextStyle(color: Colors.white),
    decoration    : InputDecoration(
      labelText : label,
      hintText  : hint,
      labelStyle: const TextStyle(color: Colors.white54),
      hintStyle : const TextStyle(color: Colors.white24),
      filled    : true,
      fillColor : Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide  : const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide  : const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide  : const BorderSide(color: Color(0xFF00C896)),
      ),
    ),
  );
}

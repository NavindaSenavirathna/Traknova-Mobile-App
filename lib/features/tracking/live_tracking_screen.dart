import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/traknova_device.dart';
import '../../core/models/tracker_point.dart';
import '../../core/viewmodels/live_tracking_viewmodel.dart';
import '../../core/services/live_location_service.dart';
import '../../core/services/locator.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Live Tracking Screen — Mobile-First Design
// ═══════════════════════════════════════════════════════════════════════════════

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});
  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with TickerProviderStateMixin {
  // ── Constants ───────────────────────────────────────────────────────────
  static const _dark       = Color(0xFF0F1923);
  static const _darkCard   = Color(0xFF162636);
  static const _accent     = Color(0xFF00C896);
  static const _accentDark = Color(0xFF00A87A);

  // ── Map ─────────────────────────────────────────────────────────────────
  final MapController _mapCtrl = MapController();
  double _zoom = 6.0;
  bool _followPhone = true;
  LatLng? _lastCentered;

  // ── ViewModel ───────────────────────────────────────────────────────────
  late final LiveTrackingViewModel _vm;

  // ── Animations ──────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  late AnimationController _dotCtrl;
  late Animation<double>   _dot;

  // ── Bottom sheet ────────────────────────────────────────────────────────
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();
  bool _sheetExpanded = false;

  // ═══════════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _vm = LiveTrackingViewModel(locator<AuthService>());

    // Pulse animation for phone marker
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Pulsing dot for connection status
    _dotCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _dot = Tween(begin: 0.3, end: 1.0).animate(_dotCtrl);

    _vm.addListener(_onVmChange);

    // Wire GPS service
    LiveLocationService().setApiService(locator<ApiService>());

    // Auto-connect: load devices + connect MQTT — no popup needed
    _vm.initialize();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _dotCtrl.dispose();
    _vm.removeListener(_onVmChange);
    _vm.dispose();
    super.dispose();
  }

  void _onVmChange() {
    if (!mounted) return;
    setState(() {});

    // Auto-center on phone while _followPhone is true
    if (_followPhone && _vm.phonePosition != null) {
      final pos = _vm.phonePosition!.position;
      if (_lastCentered == null ||
          const Distance().as(LengthUnit.Meter, _lastCentered!, pos) > 10) {
        _lastCentered = pos;
        try { _mapCtrl.move(pos, _zoom); } catch (_) {}
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Map interaction
  // ═══════════════════════════════════════════════════════════════════════

  void _onMapEvent(MapEvent ev) {
    if (ev is MapEventMove && ev.source != MapEventSource.mapController) {
      _followPhone = false;
    }
    if (ev is MapEventMoveEnd) _zoom = _mapCtrl.camera.zoom;
  }

  void _recenter() {
    final pos = _vm.focusPosition;
    if (pos != null) {
      _mapCtrl.move(pos, _zoom);
      _lastCentered = _mapCtrl.camera.center;
    }
    setState(() => _followPhone = true);
  }

  void _focusDevice(TraknovaDevice d) {
    if (!d.hasPosition) return;
    _vm.selectDevice(d);
    setState(() => _followPhone = false);
    _mapCtrl.move(
      LatLng(d.currentLatitude!, d.currentLongitude!),
      math.max(_zoom, 15.0),
    );
    // Collapse sheet so map is visible
    _sheetCtrl.animateTo(0.08,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      body: Stack(
        children: [
          // ── Map (full screen) ─────────────────────────────────────────
          _buildMap(),

          // ── Floating top bar ──────────────────────────────────────────
          _buildTopBar(context),

          // ── FABs ──────────────────────────────────────────────────────
          _buildFabs(),

          // ── Selected device card ──────────────────────────────────────
          if (_vm.selectedDevice != null)
            _buildSelectedCard(_vm.selectedDevice!),

          // ── Draggable bottom sheet ────────────────────────────────────
          _buildBottomSheet(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Map
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMap() {
    final phone   = _vm.phonePosition;
    final devices = _vm.filteredDevices.where((d) => d.hasPosition).toList();

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: phone?.position ?? const LatLng(53.0, -2.0),
        initialZoom: _zoom,
        maxZoom: 19, minZoom: 3,
        onMapEvent: _onMapEvent,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.traknova.drivemaster',
          maxZoom: 19,
        ),

        // Phone trail
        if (_vm.phonePath.length > 1)
          PolylineLayer(polylines: [
            Polyline(
              points: _vm.phonePath,
              strokeWidth: 3.5,
              color: _accent.withOpacity(0.55),
            ),
          ]),

        // Device markers
        MarkerLayer(markers: devices.map(_deviceMarker).toList()),

        // Phone accuracy circle
        if (phone != null && (phone.accuracy ?? 0) > 0)
          CircleLayer(circles: [
            CircleMarker(
              point: phone.position,
              radius: phone.accuracy!,
              useRadiusInMeter: true,
              color: Colors.blue.withOpacity(0.10),
              borderColor: Colors.blue.withOpacity(0.25),
              borderStrokeWidth: 1,
            ),
          ]),

        // Phone marker
        if (phone != null) MarkerLayer(markers: [_phoneMarker(phone)]),
      ],
    );
  }

  // ── Phone marker ────────────────────────────────────────────────────────

  Marker _phoneMarker(TrackerPoint p) => Marker(
    point: p.position,
    width: 52, height: 52,
    child: AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 44 * _pulse.value,
            height: 44 * _pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withOpacity(0.15 * (1.2 - _pulse.value)),
            ),
          ),
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8)],
            ),
          ),
        ],
      ),
    ),
  );

  // ── Device marker ───────────────────────────────────────────────────────

  Marker _deviceMarker(TraknovaDevice d) {
    final selected = _vm.selectedDevice?.imei == d.imei;
    final clr = _statusColor(d);

    return Marker(
      point: LatLng(d.currentLatitude!, d.currentLongitude!),
      width: 56, height: 56,
      child: GestureDetector(
        onTap: () => selected ? _vm.selectDevice(null) : _focusDevice(d),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: selected ? 38 : 32,
              height: selected ? 38 : 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: clr,
                border: Border.all(color: Colors.white, width: selected ? 3 : 2),
                boxShadow: [BoxShadow(color: clr.withOpacity(0.5), blurRadius: 10)],
              ),
              child: Transform.rotate(
                angle: d.currentDirection * math.pi / 180,
                child: Icon(
                  d.currentSpeed > 0 ? Icons.navigation_rounded : Icons.local_shipping_rounded,
                  color: Colors.white,
                  size: selected ? 18 : 15,
                ),
              ),
            ),
            // Speed tag
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _dark.withOpacity(0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: clr.withOpacity(0.4), width: 0.5),
              ),
              child: Text(
                '${d.currentSpeed.toStringAsFixed(0)} km/h',
                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(TraknovaDevice d) {
    if (!d.isOnline) return Colors.grey;
    if (d.currentSpeed >= d.speedLimit) return Colors.red;
    if (d.currentSpeed > 0) return const Color(0xFF4CAF50);
    if (d.ignitionOn == false) return const Color(0xFF2196F3);
    return Colors.orange;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Top bar (floating, glass-like)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTopBar(BuildContext ctx) => Positioned(
    top: 0, left: 0, right: 0,
    child: SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: _dark.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            // Back
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              onPressed: () => Navigator.of(ctx).maybePop(),
              splashRadius: 20,
            ),
            // Title + status
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Live Tracking',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _dot,
                      builder: (_, __) => Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _vm.isConnected
                              ? _accent.withOpacity(_dot.value)
                              : Colors.red.withOpacity(_dot.value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _vm.isConnected ? 'Connected' : _vm.devicesLoading ? 'Connecting…' : 'Offline',
                      style: TextStyle(
                        color: _vm.isConnected ? _accent : Colors.red.shade300,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            // Phone HUD mini
            if (_vm.phonePosition != null) ...[
              _MiniHud(label: '${_vm.phonePosition!.speed.toStringAsFixed(0)}', unit: 'km/h', color: _accent),
              const SizedBox(width: 8),
            ],
            // Device count badge
            if (_vm.totalCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_accent.withOpacity(0.2), _accentDark.withOpacity(0.1)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_shipping_rounded, color: Colors.white70, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      '${_vm.onlineCount}/${_vm.totalCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════
  //  FABs
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFabs() => Positioned(
    right: 14,
    bottom: MediaQuery.of(context).size.height * 0.18 + 16,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _fab(Icons.my_location_rounded, _followPhone ? _accent : _darkCard, _recenter),
        const SizedBox(height: 10),
        _fab(Icons.add_rounded, _darkCard, () {
          _zoom = (_zoom + 1).clamp(3.0, 19.0);
          _mapCtrl.move(_mapCtrl.camera.center, _zoom);
        }),
        const SizedBox(height: 10),
        _fab(Icons.remove_rounded, _darkCard, () {
          _zoom = (_zoom - 1).clamp(3.0, 19.0);
          _mapCtrl.move(_mapCtrl.camera.center, _zoom);
        }),
      ],
    ),
  );

  Widget _fab(IconData icon, Color bg, VoidCallback onTap) => Material(
    color: bg,
    shape: const CircleBorder(),
    elevation: 4,
    shadowColor: Colors.black38,
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════
  //  Selected device card
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSelectedCard(TraknovaDevice d) {
    final clr = _statusColor(d);
    return Positioned(
      left: 14, right: 14,
      bottom: MediaQuery.of(context).size.height * 0.15 + 60,
      child: Material(
        color: _darkCard,
        borderRadius: BorderRadius.circular(18),
        elevation: 8,
        shadowColor: Colors.black45,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: clr.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: clr.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.local_shipping_rounded, color: clr, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.deviceName.isNotEmpty ? d.deviceName : (d.vehicleNo.isNotEmpty ? d.vehicleNo : d.imei),
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(d.imei,
                        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
                      ),
                    ],
                  )),
                  _statusPill(d),
                  const SizedBox(width: 6),
                  // WhatsApp share
                  if (d.hasPosition)
                    GestureDetector(
                      onTap: () async {
                        final lat = d.currentLatitude!;
                        final lon = d.currentLongitude!;
                        final name = d.deviceName.isNotEmpty ? d.deviceName : d.imei;
                        final speed = d.currentSpeed.toStringAsFixed(0);
                        final msg = '📍 *$name* - Live Location\n'
                            'Speed: $speed km/h\n'
                            'https://www.google.com/maps?q=$lat,$lon';
                        final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.share_rounded, color: Colors.white.withOpacity(0.45), size: 16),
                      ),
                    ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _vm.selectDevice(null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stats row
              Row(
                children: [
                  _StatChip(Icons.speed_rounded, '${d.currentSpeed.toStringAsFixed(0)} km/h', 'Speed'),
                  _StatChip(Icons.explore_rounded, '${d.currentDirection}°', 'Heading'),
                  _StatChip(
                    d.ignitionOn == true ? Icons.bolt_rounded : Icons.power_off_rounded,
                    d.ignitionOn == true ? 'ON' : 'OFF',
                    'Ignition',
                  ),
                  if (d.currentTimestamp != null)
                    _StatChip(Icons.schedule_rounded, _relTime(d.currentTimestamp!), 'Updated'),
                ],
              ),
              if (d.hasPosition) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.pin_drop_rounded, color: Colors.white.withOpacity(0.3), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${d.currentLatitude!.toStringAsFixed(5)}, ${d.currentLongitude!.toStringAsFixed(5)}',
                      style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(TraknovaDevice d) {
    final on = d.isOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (on ? Colors.green : Colors.red).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (on ? Colors.green : Colors.red).withOpacity(0.4), width: 0.5),
      ),
      child: Text(
        on ? 'ONLINE' : 'OFFLINE',
        style: TextStyle(
          color: on ? Colors.greenAccent : Colors.redAccent,
          fontSize: 10, fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _relTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24)   return '${d.inHours}h';
    return '${d.inDays}d';
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Draggable bottom sheet
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      initialChildSize: 0.15,
      minChildSize: 0.08,
      maxChildSize: 0.70,
      snap: true,
      snapSizes: const [0.08, 0.15, 0.45, 0.70],
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: _dark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, -6))],
            border: Border(top: BorderSide(color: _accent.withOpacity(0.2))),
          ),
          child: NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              setState(() => _sheetExpanded = n.extent > 0.25);
              return false;
            },
            child: CustomScrollView(
              controller: scrollCtrl,
              slivers: [
                // Drag handle + quick info
                SliverToBoxAdapter(child: _sheetHeader()),

                // Search + filter (shown when expanded)
                if (_sheetExpanded) ...[
                  SliverToBoxAdapter(child: _searchBar()),
                  SliverToBoxAdapter(child: _filterTabs()),
                ],

                // Loading / empty / device list
                if (_vm.devicesLoading)
                  const SliverFillRemaining(child: _LoadingState())
                else if (_vm.filteredDevices.isEmpty)
                  SliverFillRemaining(child: _EmptyState(hasDevices: _vm.totalCount > 0))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    sliver: SliverList.builder(
                      itemCount: _vm.filteredDevices.length,
                      itemBuilder: (_, i) => _DeviceCard(
                        device: _vm.filteredDevices[i],
                        selected: _vm.selectedDevice?.imei == _vm.filteredDevices[i].imei,
                        statusColor: _statusColor(_vm.filteredDevices[i]),
                        onTap: () => _focusDevice(_vm.filteredDevices[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Sheet header (drag handle + counts) ─────────────────────────────────

  Widget _sheetHeader() => GestureDetector(
    onTap: () {
      final target = _sheetExpanded ? 0.15 : 0.45;
      _sheetCtrl.animateTo(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    },
    child: Container(
      color: Colors.transparent, // hit-test area
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Column(
        children: [
          // Drag pill
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          // Counts row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Text(
                  'Vehicles',
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _CountBadge(label: 'All', count: _vm.totalCount, color: Colors.white54),
                const SizedBox(width: 10),
                _CountBadge(label: 'Online', count: _vm.onlineCount, color: Colors.greenAccent),
                const SizedBox(width: 10),
                _CountBadge(label: 'Offline', count: _vm.offlineCount, color: Colors.redAccent),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // ── Search bar ──────────────────────────────────────────────────────────

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
    child: TextField(
      onChanged: _vm.setSearchQuery,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search vehicle…',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
        prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.3), size: 20),
        filled: true,
        fillColor: _darkCard,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  // ── Filter tabs ─────────────────────────────────────────────────────────

  Widget _filterTabs() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    child: Row(
      children: [
        _FilterChip('All', _vm.totalCount, _vm.filter == 'all', () => _vm.setFilter('all')),
        const SizedBox(width: 8),
        _FilterChip('Online', _vm.onlineCount, _vm.filter == 'online', () => _vm.setFilter('online')),
        const SizedBox(width: 8),
        _FilterChip('Offline', _vm.offlineCount, _vm.filter == 'offline', () => _vm.setFilter('offline')),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Reusable Widgets
// ═══════════════════════════════════════════════════════════════════════════════

// ── Device Card ───────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final TraknovaDevice device;
  final bool selected;
  final Color statusColor;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.device,
    required this.selected,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final online = device.isOnline;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? statusColor.withOpacity(0.08)
              : const Color(0xFF162636),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? statusColor.withOpacity(0.35) : Colors.white.withOpacity(0.04),
          ),
        ),
        child: Row(
          children: [
            // Status dot + icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                device.currentSpeed > 0
                    ? Icons.local_shipping_rounded
                    : Icons.local_shipping_outlined,
                color: statusColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.deviceName.isNotEmpty ? device.deviceName : (device.vehicleNo.isNotEmpty ? device.vehicleNo : device.imei),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: online ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      online ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: online ? Colors.green.shade300 : Colors.red.shade300,
                        fontSize: 11,
                      ),
                    ),
                    if (device.hasPosition && device.currentSpeed > 0) ...[
                      Text('  •  ', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11)),
                      Text(
                        '${device.currentSpeed.toStringAsFixed(0)} km/h',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                      ),
                    ],
                    if (device.currentDirection > 0) ...[
                      Text('  •  ', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11)),
                      Text(
                        '${_compassDir(device.currentDirection)} ${device.currentDirection}°',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Ignition
                    Icon(
                      device.ignitionOn == true ? Icons.vpn_key_rounded : Icons.vpn_key_off_rounded,
                      color: device.ignitionOn == true ? Colors.orangeAccent : Colors.white.withOpacity(0.2),
                      size: 11,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      device.ignitionOn == true ? 'IGN ON' : 'IGN OFF',
                      style: TextStyle(
                        color: device.ignitionOn == true ? Colors.orangeAccent : Colors.white.withOpacity(0.3),
                        fontSize: 10, fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (device.currentTimestamp != null) ...[
                      Text('  •  ', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
                      Icon(Icons.schedule_rounded, color: Colors.white.withOpacity(0.25), size: 10),
                      const SizedBox(width: 2),
                      Text(
                        _relTime(device.currentTimestamp!),
                        style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            )),
            // WhatsApp share
            if (device.hasPosition)
              GestureDetector(
                onTap: () => _shareWhatsApp(device),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.share_rounded, color: Colors.white.withOpacity(0.25), size: 17),
                ),
              ),
            const SizedBox(width: 2),
            // Chevron
            Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.15), size: 20),
          ],
        ),
      ),
    );
  }

  String _relTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String _compassDir(int deg) {
    const dirs = ['N','NE','E','SE','S','SW','W','NW'];
    return dirs[((deg % 360) / 45).round() % 8];
  }

  Future<void> _shareWhatsApp(TraknovaDevice d) async {
    if (!d.hasPosition) return;
    final lat = d.currentLatitude!;
    final lon = d.currentLongitude!;
    final name = d.deviceName.isNotEmpty ? d.deviceName : d.imei;
    final speed = d.currentSpeed.toStringAsFixed(0);
    final msg = '📍 *$name* - Live Location\n'
        'Speed: $speed km/h\n'
        'https://www.google.com/maps?q=$lat,$lon';
    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.count, this.active, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00C896).withOpacity(0.15)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? const Color(0xFF00C896).withOpacity(0.4)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: active ? const Color(0xFF00C896) : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF00C896).withOpacity(0.8) : Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Count badge ───────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 5, height: 5,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: 3),
      Text(
        '$count',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

// ── Mini HUD ──────────────────────────────────────────────────────────────────

class _MiniHud extends StatelessWidget {
  final String label;
  final String unit;
  final Color color;
  const _MiniHud({required this.label, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800, height: 1)),
      Text(unit, style: TextStyle(color: color.withOpacity(0.6), fontSize: 9)),
    ],
  );
}

// ── Stat chip (for selected device card) ──────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatChip(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(label, style: const TextStyle(color: Colors.white30, fontSize: 9)),
      ],
    ),
  );
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: const Color(0xFF00C896).withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 14),
        Text('Loading vehicles…',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
      ],
    ),
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasDevices; // true = filter hides them, false = no devices at all
  const _EmptyState({required this.hasDevices});

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDevices ? Icons.filter_list_off_rounded : Icons.local_shipping_outlined,
            color: Colors.white.withOpacity(0.15),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            hasDevices ? 'No vehicles match filter' : 'No vehicles found',
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
          ),
          if (!hasDevices) ...[
            const SizedBox(height: 6),
            Text(
              'Devices will appear when connected',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/models/geofence_models.dart';
import '../../core/viewmodels/geofence_viewmodel.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/locator.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  GeoFence Detail Screen — Full detail view for a single fence
// ═══════════════════════════════════════════════════════════════════════════════

class GeoFenceDetailScreen extends StatefulWidget {
  final GeoFenceConfig fence;
  const GeoFenceDetailScreen({super.key, required this.fence});

  @override
  State<GeoFenceDetailScreen> createState() => _GeoFenceDetailScreenState();
}

class _GeoFenceDetailScreenState extends State<GeoFenceDetailScreen> {
  static const _dark     = Color(0xFF0F1923);
  static const _darkCard = Color(0xFF162636);
  static const _accent   = Color(0xFF00C896);

  late final GeoFenceViewModel _vm;
  final MapController _mapCtrl = MapController();
  String _selectedDate = '';

  @override
  void initState() {
    super.initState();
    _vm = GeoFenceViewModel(locator<AuthService>());
    _vm.addListener(_onChange);

    final now = DateTime.now();
    _selectedDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    _vm.initialize().then((_) {
      // Load device fences for this config
      if (widget.fence.devices.isNotEmpty) {
        _vm.loadDeviceFences(widget.fence.devices);
      }
    });
  }

  @override
  void dispose() {
    _vm.removeListener(_onChange);
    _vm.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  LatLng _fenceCenter() {
    if (widget.fence.boundary.isEmpty) return const LatLng(53.0, -2.0);
    double lat = 0, lng = 0;
    for (final p in widget.fence.boundary) {
      lat += p[0];
      lng += p[1];
    }
    return LatLng(lat / widget.fence.boundary.length,
        lng / widget.fence.boundary.length);
  }

  @override
  Widget build(BuildContext context) {
    final fence = widget.fence;
    final clr = fence.flutterColor;

    return Scaffold(
      backgroundColor: _dark,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ───────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: _dark,
            foregroundColor: Colors.white,
            pinned: true,
            expandedHeight: 280,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildMap(fence, clr),
            ),
            title: Text(
              fence.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),

          // ── Fence Info Card ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: clr.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: clr.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          fence.modal == 'ROUTE'
                              ? Icons.route_rounded
                              : Icons.fence_rounded,
                          color: clr,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fence.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            if (fence.desc?.isNotEmpty == true)
                              Text(fence.desc!,
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 12)),
                          ],
                        ),
                      ),
                      _statusPill(fence),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),

                  // Info grid
                  _infoRow(Icons.category_rounded, 'Type',
                      '${fence.modal} (${fence.mode})'),
                  _infoRow(Icons.code_rounded, 'Code', fence.code),
                  _infoRow(Icons.calendar_today_rounded, 'Active Period',
                      '${fence.startTime} → ${fence.expireTime}'),
                  _infoRow(Icons.notifications_rounded, 'Alarm Modes',
                      fence.alarmMode.join(', ')),
                  _infoRow(Icons.volume_up_rounded, 'Notifications',
                      fence.alarmOptions.join(', ')),
                  _infoRow(Icons.devices_rounded, 'Devices',
                      fence.devices.isEmpty
                          ? 'All (Region)'
                          : fence.devices.join(', ')),
                  if (fence.alertEmails.isNotEmpty)
                    _infoRow(Icons.email_rounded, 'Email Alerts',
                        fence.alertEmails.join(', ')),
                  if (fence.alertContacts.isNotEmpty)
                    _infoRow(Icons.sms_rounded, 'SMS Alerts',
                        fence.alertContacts.join(', ')),
                  if (fence.offset != null)
                    _infoRow(Icons.straighten_rounded, 'Buffer',
                        '${fence.offset} meters'),
                ],
              ),
            ),
          ),

          // ── Assigned Devices ───────────────────────────────────────────
          if (_vm.deviceFences.isNotEmpty)
            SliverToBoxAdapter(
              child: _sectionHeader('Assigned Devices', Icons.local_shipping_rounded),
            ),
          if (_vm.deviceFencesLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF00C896)))),
              ),
            )
          else if (_vm.deviceFences.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverList.builder(
                itemCount: _vm.deviceFences.length,
                itemBuilder: (_, i) =>
                    _deviceFenceCard(_vm.deviceFences[i]),
              ),
            ),

          // ── Violation History Header ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.history_rounded,
                      color: Colors.white.withOpacity(0.5), size: 18),
                  const SizedBox(width: 8),
                  Text('Violation History',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  // Date picker
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _darkCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _accent.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              color: _accent, size: 12),
                          const SizedBox(width: 4),
                          Text(_selectedDate,
                              style: TextStyle(
                                  color: _accent, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Violations List ────────────────────────────────────────────
          if (_vm.violationsLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00C896))),
              ),
            )
          else if (_vm.violations.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    'No violations for this date',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
              sliver: SliverList.builder(
                itemCount: _vm.violations.length,
                itemBuilder: (_, i) =>
                    _violationCard(_vm.violations[i]),
              ),
            ),
        ],
      ),
    );
  }

  // ── Map ─────────────────────────────────────────────────────────────────

  Widget _buildMap(GeoFenceConfig fence, Color clr) {
    final center = _fenceCenter();

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
        maxZoom: 19,
        minZoom: 3,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.traknova.drivemaster',
        ),
        if (fence.boundary.length >= 3)
          PolygonLayer(
            polygons: [
              Polygon(
                points: fence.boundary
                    .map((c) => LatLng(c[0], c[1]))
                    .toList(),
                color: clr.withOpacity(0.25),
                borderColor: clr,
                borderStrokeWidth: 3,
                isFilled: true,
              ),
            ],
          ),
        // Violation markers
        if (_vm.violations.isNotEmpty)
          MarkerLayer(
            markers: _vm.violations
                .where((v) => v.latitude != 0 && v.longitude != 0)
                .map((v) => Marker(
                      point: LatLng(v.latitude, v.longitude),
                      width: 32,
                      height: 32,
                      child: Icon(
                        v.isEntry
                            ? Icons.login_rounded
                            : Icons.logout_rounded,
                        color: v.isEntry
                            ? GeoFenceColors.entry
                            : GeoFenceColors.exit,
                        size: 22,
                      ),
                    ))
                .toList(),
          ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Widget _statusPill(GeoFenceConfig f) {
    final active = f.isActive;
    final expiring = f.isExpiringSoon;
    final color = active
        ? (expiring ? Colors.orange : Colors.green)
        : Colors.red;
    final label = active
        ? (expiring ? 'EXPIRING' : 'ACTIVE')
        : 'EXPIRED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.3), size: 14),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.5), size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _deviceFenceCard(DeviceGeoFence df) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_rounded,
              color: _accent.withOpacity(0.6), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(df.vehicleNo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                Text(
                  '${df.detectionMode.join(", ")} • ${df.isActive ? "Active" : "Inactive"}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 10),
                ),
              ],
            ),
          ),
          // Load history button
          GestureDetector(
            onTap: () {
              _vm.loadViolationHistory(
                deviceCode: df.deviceCode,
                configCode: df.configCode,
                date: _selectedDate,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('History',
                  style: TextStyle(color: _accent, fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _violationCard(GeoFenceViolation v) {
    final isEntry = v.isEntry;
    final clr = isEntry ? GeoFenceColors.entry : GeoFenceColors.exit;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: clr.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: clr.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: clr.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isEntry ? Icons.login_rounded : Icons.logout_rounded,
              color: clr,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: clr.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        v.detectionMode,
                        style: TextStyle(
                            color: clr,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      v.time,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.speed_rounded,
                        color: Colors.white.withOpacity(0.3), size: 11),
                    const SizedBox(width: 3),
                    Text('${v.speed.toStringAsFixed(0)} mph',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 10)),
                    const SizedBox(width: 8),
                    Icon(Icons.explore_rounded,
                        color: Colors.white.withOpacity(0.3), size: 11),
                    const SizedBox(width: 3),
                    Text('${v.direction}°',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 10)),
                    const SizedBox(width: 8),
                    Icon(Icons.pin_drop_rounded,
                        color: Colors.white.withOpacity(0.3), size: 11),
                    const SizedBox(width: 3),
                    Text(
                      '${v.latitude.toStringAsFixed(4)}, ${v.longitude.toStringAsFixed(4)}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00C896),
              onPrimary: Colors.white,
              surface: Color(0xFF162636),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _selectedDate =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
      // Reload violations if we have a selected device config
      if (_vm.deviceFences.isNotEmpty) {
        _vm.loadViolationHistory(
          deviceCode: _vm.deviceFences.first.deviceCode,
          configCode: _vm.deviceFences.first.configCode,
          date: _selectedDate,
        );
      }
    }
  }
}

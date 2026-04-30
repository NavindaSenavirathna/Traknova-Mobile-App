import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/models/geofence_models.dart';
import '../../core/viewmodels/geofence_viewmodel.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/locator.dart';
import 'geofence_detail_screen.dart';
import 'geofence_alerts_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  GeoFence Screen — Main entry point for geofence feature
// ═══════════════════════════════════════════════════════════════════════════════

class GeoFenceScreen extends StatefulWidget {
  const GeoFenceScreen({super.key});
  @override
  State<GeoFenceScreen> createState() => _GeoFenceScreenState();
}

class _GeoFenceScreenState extends State<GeoFenceScreen>
    with TickerProviderStateMixin {
  // ── Constants ───────────────────────────────────────────────────────────
  static const _dark       = Color(0xFF0F1923);
  static const _darkCard   = Color(0xFF162636);
  static const _accent     = Color(0xFF00C896);

  // ── ViewModel ───────────────────────────────────────────────────────────
  late final GeoFenceViewModel _vm;

  // ── Map ─────────────────────────────────────────────────────────────────
  final MapController _mapCtrl = MapController();
  double _zoom = 6.0;

  // ── Tab controller ──────────────────────────────────────────────────────
  late TabController _tabCtrl;

  // ── Bottom sheet ────────────────────────────────────────────────────────
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();
  bool _sheetExpanded = false;

  // ── Animations ──────────────────────────────────────────────────────────
  late AnimationController _dotCtrl;
  late Animation<double> _dot;

  // ═══════════════════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _vm = GeoFenceViewModel(locator<AuthService>());
    _vm.addListener(_onVmChange);

    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() {});
      }
    });

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _dot = Tween(begin: 0.3, end: 1.0).animate(_dotCtrl);

    _vm.initialize();
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    _tabCtrl.dispose();
    _vm.removeListener(_onVmChange);
    _vm.dispose();
    super.dispose();
  }

  void _onVmChange() {
    if (!mounted) return;
    setState(() {});
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
          // Map (full screen background)
          _buildMap(),

          // Top bar
          _buildTopBar(),

          // FABs
          _buildFabs(),

          // Bottom sheet
          _buildBottomSheet(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Map
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMap() {
    final fences = _vm.showPolygonsOnMap ? _vm.filteredFences : <GeoFenceConfig>[];

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: const LatLng(53.0, -2.0),
        initialZoom: _zoom,
        maxZoom: 19,
        minZoom: 3,
        onMapEvent: (ev) {
          if (ev is MapEventMoveEnd) _zoom = _mapCtrl.camera.zoom;
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.traknova.drivemaster',
          maxZoom: 19,
        ),

        // GeoFence polygon boundaries
        if (fences.isNotEmpty)
          PolygonLayer(
            polygons: fences
                .where((f) => f.boundary.length >= 3)
                .map((f) => Polygon(
                      points: f.boundary
                          .map((c) => LatLng(c[0], c[1]))
                          .toList(),
                      color: f.flutterColor.withOpacity(0.20),
                      borderColor: f.flutterColor,
                      borderStrokeWidth: 2.5,
                      isFilled: true,
                      label: f.name,
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      labelPlacement: PolygonLabelPlacement.centroid,
                    ))
                .toList(),
          ),

        // Route lines (for ROUTE type fences)
        if (fences.isNotEmpty)
          PolylineLayer(
            polylines: fences
                .where((f) => f.modal == 'ROUTE' && f.routeLine != null && f.routeLine!.isNotEmpty)
                .map((f) => Polyline(
                      points: f.routeLine!
                          .map((c) => LatLng(c[0], c[1]))
                          .toList(),
                      strokeWidth: 3,
                      color: f.flutterColor.withOpacity(0.7),
                      isDotted: true,
                    ))
                .toList(),
          ),

        // Fence center markers
        if (fences.isNotEmpty)
          MarkerLayer(
            markers: fences
                .where((f) => f.boundary.length >= 3)
                .map((f) {
              final center = _vm.getFenceCenter(f);
              if (center == null) return null;
              return Marker(
                point: center,
                width: 36,
                height: 36,
                child: GestureDetector(
                  onTap: () => _onFenceTap(f),
                  child: Container(
                    decoration: BoxDecoration(
                      color: f.flutterColor.withOpacity(0.85),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: f.flutterColor.withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      f.modal == 'ROUTE'
                          ? Icons.route_rounded
                          : Icons.fence_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              );
            })
                .whereType<Marker>()
                .toList(),
          ),
      ],
    );
  }

  void _onFenceTap(GeoFenceConfig fence) {
    _vm.selectFence(fence);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeoFenceDetailScreen(fence: fence),
      ),
    );
  }

  void _focusFence(GeoFenceConfig fence) {
    final center = _vm.getFenceCenter(fence);
    if (center != null) {
      _mapCtrl.move(center, math.max(_zoom, 14.0));
    }
    _sheetCtrl.animateTo(0.08,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Top bar
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTopBar() => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: _dark.withOpacity(0.92),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18),
                  onPressed: () => Navigator.of(context).maybePop(),
                  splashRadius: 20,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('GeoFences',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _dot,
                          builder: (_, __) => Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _vm.fencesLoading
                                  ? Colors.amber.withOpacity(_dot.value)
                                  : _accent.withOpacity(_dot.value),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _vm.fencesLoading
                              ? 'Loading…'
                              : '${_vm.totalFences} fences',
                          style: TextStyle(
                            color: _vm.fencesLoading
                                ? Colors.amber
                                : _accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                // Toggle polygons
                IconButton(
                  icon: Icon(
                    _vm.showPolygonsOnMap
                        ? Icons.layers_rounded
                        : Icons.layers_clear_rounded,
                    color:
                        _vm.showPolygonsOnMap ? _accent : Colors.white38,
                    size: 20,
                  ),
                  onPressed: () =>
                      _vm.togglePolygonsOnMap(!_vm.showPolygonsOnMap),
                  splashRadius: 20,
                  tooltip: 'Toggle fence polygons',
                ),
                // Alert badge
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_rounded,
                          color: Colors.white70, size: 20),
                      onPressed: () {
                        _vm.clearUnreadAlerts();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GeoFenceAlertsScreen(),
                          ),
                        );
                      },
                      splashRadius: 20,
                    ),
                    if (_vm.unreadAlertCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_vm.unreadAlertCount > 9 ? "9+" : _vm.unreadAlertCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
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
            _fab(Icons.center_focus_strong_rounded, _darkCard, () {
              // Fit all fences in view
              if (_vm.filteredFences.isNotEmpty) {
                final allPoints = <LatLng>[];
                for (final f in _vm.filteredFences) {
                  for (final c in f.boundary) {
                    allPoints.add(LatLng(c[0], c[1]));
                  }
                }
                if (allPoints.isNotEmpty) {
                  final bounds = LatLngBounds.fromPoints(allPoints);
                  _mapCtrl.fitCamera(
                    CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(60),
                    ),
                  );
                }
              }
            }),
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
  //  Bottom Sheet
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, -6))
            ],
            border: Border(
                top: BorderSide(color: _accent.withOpacity(0.2))),
          ),
          child: NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              setState(() => _sheetExpanded = n.extent > 0.25);
              return false;
            },
            child: CustomScrollView(
              controller: scrollCtrl,
              slivers: [
                // Drag handle + summary
                SliverToBoxAdapter(child: _sheetHeader()),

                // Search + filters (when expanded)
                if (_sheetExpanded) ...[
                  SliverToBoxAdapter(child: _searchBar()),
                  SliverToBoxAdapter(child: _filterTabs()),
                ],

                // Content
                if (_vm.fencesLoading)
                  const SliverFillRemaining(child: _LoadingState())
                else if (_vm.fencesError != null)
                  SliverFillRemaining(
                      child: _ErrorState(error: _vm.fencesError!))
                else if (_vm.filteredFences.isEmpty)
                  SliverFillRemaining(
                      child: _EmptyState(
                          hasFences: _vm.totalFences > 0))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    sliver: SliverList.builder(
                      itemCount: _vm.filteredFences.length,
                      itemBuilder: (_, i) => _GeoFenceCard(
                        fence: _vm.filteredFences[i],
                        onTap: () => _onFenceTap(_vm.filteredFences[i]),
                        onMapFocus: () =>
                            _focusFence(_vm.filteredFences[i]),
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

  // ── Sheet header ────────────────────────────────────────────────────────

  Widget _sheetHeader() => GestureDetector(
        onTap: () {
          final target = _sheetExpanded ? 0.15 : 0.45;
          _sheetCtrl.animateTo(target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut);
        },
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Text(
                      'GeoFences',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    _CountBadge(
                        label: 'All',
                        count: _vm.totalFences,
                        color: Colors.white54),
                    const SizedBox(width: 10),
                    _CountBadge(
                        label: 'Area',
                        count: _vm.areaFenceCount,
                        color: _accent),
                    const SizedBox(width: 10),
                    _CountBadge(
                        label: 'Route',
                        count: _vm.routeFenceCount,
                        color: Colors.amber),
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
            hintText: 'Search geofence…',
            hintStyle:
                TextStyle(color: Colors.white.withOpacity(0.25)),
            prefixIcon: Icon(Icons.search_rounded,
                color: Colors.white.withOpacity(0.3), size: 20),
            filled: true,
            fillColor: _darkCard,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10),
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
            _FilterChip('All', _vm.totalFences,
                _vm.filterType == 'all', () => _vm.setFilterType('all')),
            const SizedBox(width: 8),
            _FilterChip('Area', _vm.areaFenceCount,
                _vm.filterType == 'AREA', () => _vm.setFilterType('AREA')),
            const SizedBox(width: 8),
            _FilterChip('Route', _vm.routeFenceCount,
                _vm.filterType == 'ROUTE', () => _vm.setFilterType('ROUTE')),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Reusable Widgets
// ═══════════════════════════════════════════════════════════════════════════════

// ── GeoFence Card ─────────────────────────────────────────────────────────────

class _GeoFenceCard extends StatelessWidget {
  final GeoFenceConfig fence;
  final VoidCallback onTap;
  final VoidCallback onMapFocus;

  const _GeoFenceCard({
    required this.fence,
    required this.onTap,
    required this.onMapFocus,
  });

  @override
  Widget build(BuildContext context) {
    final clr = fence.flutterColor;
    final isRoute = fence.modal == 'ROUTE';
    final active = fence.isActive;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF162636),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: clr.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: clr.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isRoute ? Icons.route_rounded : Icons.fence_rounded,
                color: clr,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fence.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isRoute ? Colors.amber : const Color(0xFF00C896))
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          fence.modal,
                          style: TextStyle(
                            color:
                                isRoute ? Colors.amber : const Color(0xFF00C896),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${fence.devices.length} devices',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11),
                      ),
                      Text('  •  ',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.2),
                              fontSize: 11)),
                      ...fence.alarmMode.map((m) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              m == 'ENTRY'
                                  ? Icons.login_rounded
                                  : Icons.logout_rounded,
                              color: m == 'ENTRY'
                                  ? GeoFenceColors.entry
                                  : GeoFenceColors.exit,
                              size: 12,
                            ),
                          )),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? (fence.isExpiringSoon
                                  ? Colors.orange
                                  : Colors.green)
                              : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        active
                            ? (fence.isExpiringSoon ? 'Expiring soon' : 'Active')
                            : 'Expired',
                        style: TextStyle(
                          color: active
                              ? (fence.isExpiringSoon
                                  ? Colors.orange.shade300
                                  : Colors.green.shade300)
                              : Colors.red.shade300,
                          fontSize: 10,
                        ),
                      ),
                      if (fence.mode == 'REGION') ...[
                        Text('  •  ',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                                fontSize: 10)),
                        Text('REGION',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Focus on map button
            GestureDetector(
              onTap: onMapFocus,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.my_location_rounded,
                    color: Colors.white.withOpacity(0.25), size: 17),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.15), size: 20),
          ],
        ),
      ),
    );
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
                    color: active
                        ? const Color(0xFF00C896).withOpacity(0.8)
                        : Colors.white54,
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
  const _CountBadge(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
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
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: const Color(0xFF00C896).withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text('Loading geofences…',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 12)),
          ],
        ),
      );
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                color: Colors.red.withOpacity(0.5), size: 44),
            const SizedBox(height: 8),
            Flexible(
              child: Text(error,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.35), fontSize: 13)),
            ),
          ],
        ),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFences;
  const _EmptyState({required this.hasFences});

  @override
  Widget build(BuildContext context) => Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasFences
                    ? Icons.filter_list_off_rounded
                    : Icons.fence_rounded,
                color: Colors.white.withOpacity(0.15),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                hasFences
                    ? 'No fences match filter'
                    : 'No geofences found',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 14),
              ),
            ],
          ),
        ),
      );
}

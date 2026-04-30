import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/geofence_models.dart';
import '../../core/viewmodels/geofence_viewmodel.dart';
import '../../core/services/geofence_notification_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/locator.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  GeoFence Alerts Screen — Live alerts + historical alerts
// ═══════════════════════════════════════════════════════════════════════════════

class GeoFenceAlertsScreen extends StatefulWidget {
  const GeoFenceAlertsScreen({super.key});

  @override
  State<GeoFenceAlertsScreen> createState() => _GeoFenceAlertsScreenState();
}

class _GeoFenceAlertsScreenState extends State<GeoFenceAlertsScreen>
    with SingleTickerProviderStateMixin {
  static const _dark = Color(0xFF0F1923);
  static const _darkCard = Color(0xFF162636);
  static const _accent = Color(0xFF00C896);

  late final TabController _tabCtrl;
  late final GeoFenceViewModel _vm;
  late final GeoFenceNotificationService _notifService;
  StreamSubscription<GeoFenceAlert>? _liveSub;

  final List<GeoFenceAlert> _liveAlerts = [];
  String _historyFromDate = '';
  String _historyToDate = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _vm = GeoFenceViewModel(locator<AuthService>());
    _notifService = GeoFenceNotificationService();
    _vm.addListener(_onChange);

    final now = DateTime.now();
    final fmt = (DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
    _historyToDate = fmt(now);
    _historyFromDate = fmt(now.subtract(const Duration(days: 7)));

    _vm.initialize().then((_) {
      _vm.loadAlertHistory(from: _historyFromDate, to: _historyToDate);
    });

    // Subscribe to live alerts
    _liveSub = _notifService.alertStream.listen((alert) {
      if (mounted) {
        setState(() => _liveAlerts.insert(0, alert));
      }
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _vm.removeListener(_onChange);
    _vm.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _dark,
        foregroundColor: Colors.white,
        title: const Text(
          'GeoFence Alerts',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt_rounded, size: 16),
                  const SizedBox(width: 4),
                  const Text('Live', style: TextStyle(fontSize: 13)),
                  if (_liveAlerts.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_liveAlerts.length}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 16),
                  SizedBox(width: 4),
                  Text('History', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildLiveTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  // ── Live Alerts Tab ────────────────────────────────────────────────────

  Widget _buildLiveTab() {
    if (_liveAlerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_rounded,
                color: Colors.white.withOpacity(0.15), size: 64),
            const SizedBox(height: 12),
            Text(
              'Listening for GeoFence alerts...',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Alerts will appear here in real-time via MQTT',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 11),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: _accent.withOpacity(0.3),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Clear all button
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => setState(() => _liveAlerts.clear()),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.clear_all_rounded,
                          color: Colors.red, size: 14),
                      SizedBox(width: 4),
                      Text('Clear',
                          style: TextStyle(color: Colors.red, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Alerts list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: _liveAlerts.length,
            itemBuilder: (_, i) => _alertCard(_liveAlerts[i], live: true),
          ),
        ),
      ],
    );
  }

  // ── History Tab ────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Date range picker
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(child: _datePicker('From', _historyFromDate, true)),
              const SizedBox(width: 10),
              Expanded(child: _datePicker('To', _historyToDate, false)),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _vm.loadAlertHistory(
                    from: _historyFromDate, to: _historyToDate),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.search_rounded, color: _accent, size: 18),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Alerts list
        Expanded(
          child: _vm.alertsLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF00C896)))
              : _vm.alertHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded,
                              color: Colors.white.withOpacity(0.1), size: 48),
                          const SizedBox(height: 10),
                          Text(
                            'No alerts in this date range',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _vm.alertHistory.length,
                      itemBuilder: (_, i) => _alertCard(_vm.alertHistory[i]),
                    ),
        ),
      ],
    );
  }

  // ── Alert Card ──────────────────────────────────────────────────────

  Widget _alertCard(GeoFenceAlert alert, {bool live = false}) {
    final isEntry = alert.isEntry;
    final clr = isEntry ? GeoFenceColors.entry : GeoFenceColors.exit;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: clr.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: clr.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Entry/Exit icon
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: clr.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isEntry ? Icons.login_rounded : Icons.logout_rounded,
                  color: clr,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (live) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: clr.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isEntry ? 'ENTRY' : 'EXIT',
                            style: TextStyle(
                                color: clr,
                                fontSize: 9,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            alert.vehicleNo,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.configName,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    alert.time,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  if (alert.date.isNotEmpty)
                    Text(
                      alert.date,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3), fontSize: 9),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Location & Speed row
          Row(
            children: [
              Icon(Icons.speed_rounded,
                  color: Colors.white.withOpacity(0.3), size: 12),
              const SizedBox(width: 3),
              Text(
                '${alert.speed.toStringAsFixed(0)} mph',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 10),
              ),
              const SizedBox(width: 10),
              Icon(Icons.pin_drop_rounded,
                  color: Colors.white.withOpacity(0.3), size: 12),
              const SizedBox(width: 3),
              Text(
                '${alert.latitude.toStringAsFixed(4)}, ${alert.longitude.toStringAsFixed(4)}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 10),
              ),
              const Spacer(),
              Text(
                alert.detectionMode,
                style: TextStyle(
                    color: _accent.withOpacity(0.5),
                    fontSize: 9,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Date Picker ────────────────────────────────────────────────────────

  Widget _datePicker(String label, String value, bool isFrom) {
    return GestureDetector(
      onTap: () async {
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
          final fmt =
              '${picked.year}-${picked.month.toString().padLeft(2, "0")}-${picked.day.toString().padLeft(2, "0")}';
          setState(() {
            if (isFrom) {
              _historyFromDate = fmt;
            } else {
              _historyToDate = fmt;
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _darkCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                color: _accent.withOpacity(0.6), size: 12),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 9)),
                Text(value,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

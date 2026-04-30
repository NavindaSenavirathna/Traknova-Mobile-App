import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/geofence_models.dart';

/// Service for showing in-app geofence alert notifications.
///
/// Handles:
/// - Animated overlay banners (slide in from top)
/// - Vibration / haptic feedback based on alarm options
/// - Alert history tracking
/// - Notification toggles
class GeoFenceNotificationService {
  static final GeoFenceNotificationService _instance =
      GeoFenceNotificationService._internal();
  factory GeoFenceNotificationService() => _instance;
  GeoFenceNotificationService._internal();

  // Navigator key from main.dart
  GlobalKey<NavigatorState>? _navigatorKey;

  // Settings
  bool _isNotificationEnabled = true;
  bool _isAlertSoundEnabled = true;

  // Live alerts list (in-memory, most recent first)
  final List<GeoFenceAlert> _liveAlerts = [];
  static const int _maxLiveAlerts = 200;

  // Alert count for badge
  int _unreadCount = 0;

  // Stream for UI updates
  final StreamController<void> _updateController =
      StreamController<void>.broadcast();
  Stream<void> get onUpdate => _updateController.stream;

  // Stream for live alerts (so screens can subscribe)
  final StreamController<GeoFenceAlert> _alertStreamController =
      StreamController<GeoFenceAlert>.broadcast();
  Stream<GeoFenceAlert> get alertStream => _alertStreamController.stream;

  // Currently displayed overlay
  OverlayEntry? _currentOverlay;
  Timer? _dismissTimer;

  // ── Setup ──────────────────────────────────────────────────────────────

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  // ── Getters ────────────────────────────────────────────────────────────

  List<GeoFenceAlert> get liveAlerts => List.unmodifiable(_liveAlerts);
  int get unreadCount => _unreadCount;
  bool get isNotificationEnabled => _isNotificationEnabled;
  bool get isAlertSoundEnabled => _isAlertSoundEnabled;

  // ── Toggles ────────────────────────────────────────────────────────────

  void toggleNotifications(bool enabled) {
    _isNotificationEnabled = enabled;
    _notify();
  }

  void toggleAlertSound(bool enabled) {
    _isAlertSoundEnabled = enabled;
    _notify();
  }

  void clearUnreadCount() {
    _unreadCount = 0;
    _notify();
  }

  // ── Alert Handling ─────────────────────────────────────────────────────

  /// Show a geofence alert notification.
  /// Called when MQTT alert or client-side detection fires.
  void showAlert(GeoFenceAlert alert) {
    // De-duplicate: check if same alert received in last 30 seconds
    final isDuplicate = _liveAlerts.any((a) =>
        a.dedupeKey == alert.dedupeKey &&
        DateTime.now().difference(a.receivedAt).inSeconds < 30);
    if (isDuplicate) return;

    // Add to live list
    _liveAlerts.insert(0, alert);
    if (_liveAlerts.length > _maxLiveAlerts) {
      _liveAlerts.removeLast();
    }
    _unreadCount++;

    // Emit on alertStream for listening screens
    if (!_alertStreamController.isClosed) {
      _alertStreamController.add(alert);
    }

    if (!_isNotificationEnabled) {
      _notify();
      return;
    }

    // Vibration / haptic
    if (alert.isAlarm && _isAlertSoundEnabled) {
      HapticFeedback.heavyImpact();
      // Double vibration for alarm
      Future.delayed(const Duration(milliseconds: 300), () {
        HapticFeedback.heavyImpact();
      });
    } else {
      HapticFeedback.mediumImpact();
    }

    // Show overlay banner
    _showBanner(alert);
    _notify();
  }

  /// Add alert to list without showing banner (for history loading)
  void addToHistory(GeoFenceAlert alert) {
    if (!_liveAlerts.any((a) => a.dedupeKey == alert.dedupeKey)) {
      _liveAlerts.add(alert);
      if (_liveAlerts.length > _maxLiveAlerts) {
        _liveAlerts.removeLast();
      }
    }
    _notify();
  }

  void clearAlerts() {
    _liveAlerts.clear();
    _unreadCount = 0;
    _notify();
  }

  // ── Banner Display ─────────────────────────────────────────────────────

  void _showBanner(GeoFenceAlert alert) {
    // Remove existing banner
    _dismissBanner();

    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;

    _currentOverlay = OverlayEntry(
      builder: (context) => _GeoFenceAlertBannerWidget(
        alert: alert,
        onDismiss: _dismissBanner,
      ),
    );

    overlay.insert(_currentOverlay!);

    // Auto-dismiss after 8 seconds
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 8), _dismissBanner);
  }

  void _dismissBanner() {
    _dismissTimer?.cancel();
    if (_currentOverlay?.mounted ?? false) {
      _currentOverlay?.remove();
    }
    _currentOverlay = null;
  }

  void _notify() {
    if (!_updateController.isClosed) {
      _updateController.add(null);
    }
  }

  void dispose() {
    _dismissBanner();
    _updateController.close();
    _alertStreamController.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Alert Banner Widget — Animated overlay
// ═══════════════════════════════════════════════════════════════════════════════

class _GeoFenceAlertBannerWidget extends StatefulWidget {
  final GeoFenceAlert alert;
  final VoidCallback onDismiss;

  const _GeoFenceAlertBannerWidget({
    required this.alert,
    required this.onDismiss,
  });

  @override
  State<_GeoFenceAlertBannerWidget> createState() =>
      _GeoFenceAlertBannerWidgetState();
}

class _GeoFenceAlertBannerWidgetState extends State<_GeoFenceAlertBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final isEntry = widget.alert.isEntry;
    final accentColor = isEntry ? const Color(0xFF4CAF50) : const Color(0xFFE53935);
    final bgColor = isEntry ? const Color(0xFF1B3A2D) : const Color(0xFF3A1B1B);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onHorizontalDragEnd: (_) => _dismiss(),
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(16),
              color: bgColor,
              shadowColor: accentColor.withOpacity(0.3),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withOpacity(0.5), width: 1.5),
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEntry ? Icons.login_rounded : Icons.logout_rounded,
                        color: accentColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'GEOFENCE ${widget.alert.mode}',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (widget.alert.isAlarm) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.notifications_active_rounded,
                                    color: Colors.amber, size: 14),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.alert.vehicleNo}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${isEntry ? "entered" : "exited"} ${widget.alert.fenceName}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.alert.time.isNotEmpty)
                            Text(
                              widget.alert.time,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Close button
                    GestureDetector(
                      onTap: _dismiss,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

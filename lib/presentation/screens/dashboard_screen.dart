// screens/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/auth/auth_view_model.dart';
import '../../core/services/api_service.dart';
import '../../core/services/locator.dart';
import '../../core/services/live_location_service.dart';
import 'login_screen.dart';
import 'notification_screen.dart';
import '../../features/tracking/live_tracking_screen.dart';
import '../../features/geofence/geofence_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  // Login success notification
  bool _showLoginSuccess = true;
  Timer? _loginMessageTimer;

  // Live location
  final LiveLocationService _locationService = LiveLocationService();
  StreamSubscription<LocationSnapshot>? _locationSub;
  LocationSnapshot? _currentLocation;
  bool _isTracking = false;
  bool _isStarting = false;
  String _statusMessage = 'Tap the button to start sending your location.';

  @override
  void initState() {
    super.initState();

    _loginMessageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showLoginSuccess = false);
    });

    // Wire up the API service into the location service
    _locationService.setApiService(locator<ApiService>());

    _locationSub = _locationService.locationStream.listen((snap) {
      if (mounted) {
        setState(() {
          _currentLocation = snap;
          _isTracking = _locationService.isTracking;
        });
      }
    });
  }

  @override
  void dispose() {
    _loginMessageTimer?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleTracking() async {
    if (_isStarting) return;

    if (_isTracking) {
      await _locationService.stop();
      if (mounted) {
        setState(() {
          _isTracking = false;
          _statusMessage = 'Location sharing stopped.';
        });
      }
    } else {
      setState(() {
        _isStarting = true;
        _statusMessage = 'Requesting permissions...';
      });

      final started = await _locationService.start();

      if (mounted) {
        setState(() {
          _isStarting = false;
          _isTracking = started;
          _statusMessage = started
              ? 'Sending your location every 5 seconds.'
              : 'Failed to start. Check GPS permissions.';
        });
      }
    }
  }

  void _showLogoutDialog() {
    final authViewModel = locator<AuthViewModel>();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.logout, color: Colors.grey[600], size: 24),
            ),
            const SizedBox(height: 15),
            const Text('Logout', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Please confirm to session logout!', style: TextStyle(fontSize: 16, color: Colors.black87)),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 45,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[500], foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: SizedBox(
                    height: 45,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(dialogCtx).pop();
                        final nav = Navigator.of(context);
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const AlertDialog(
                            content: Row(children: [
                              CircularProgressIndicator(), SizedBox(width: 20), Text('Logging out...'),
                            ]),
                          ),
                        );
                        try {
                          await _locationService.stop();
                          await authViewModel.logout();
                          nav.pop();
                          nav.pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false,
                          );
                        } catch (e) {
                          nav.pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logout error: $e')));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600], foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      child: const Text('Confirm'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Share the current location on WhatsApp as a Google Maps link.
  Future<void> _shareOnWhatsApp() async {
    if (_currentLocation == null) return;

    final lat = _currentLocation!.latitude;
    final lng = _currentLocation!.longitude;
    final mapsLink = 'https://www.google.com/maps?q=$lat,$lng';
    final message = Uri.encodeComponent(
      'My current live location:\n$mapsLink',
    );
    final whatsappUrl = Uri.parse('https://wa.me/?text=$message');

    try {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open WhatsApp: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _fmt(double v, {int decimals = 6}) => v.toStringAsFixed(decimals);

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C2C2C),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/leather_texture.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Image.asset(
                              'assets/logo.png',
                              width: 140,
                              height: 34,
                              fit: BoxFit.contain,
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => WebSocketScreen()),
                                  ),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: _showLogoutDialog,
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.35),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.logout,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isTracking ? Colors.green.withOpacity(0.85) : Colors.grey.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _isTracking ? Colors.white : Colors.white54,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isTracking ? 'LIVE  SENDING' : 'PAUSED',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isTracking ? Colors.green.withOpacity(0.6) : Colors.white.withOpacity(0.15),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: _isTracking ? Colors.greenAccent : Colors.white38,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Live Location',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white24, height: 24),
                            if (_currentLocation == null)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  'No location data yet.\nStart tracking to see your position.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white54, fontSize: 14),
                                ),
                              )
                            else ...[
                              _locationRow(Icons.explore, 'Latitude', '${_fmt(_currentLocation!.latitude)}'),
                              _locationRow(Icons.explore_outlined, 'Longitude', '${_fmt(_currentLocation!.longitude)}'),
                              _locationRow(Icons.adjust, 'Accuracy', '${_fmt(_currentLocation!.accuracy, decimals: 1)} m'),
                              _locationRow(Icons.speed, 'Speed', '${_fmt(_currentLocation!.speedKmh, decimals: 1)} km/h'),
                              _locationRow(Icons.terrain, 'Altitude', '${_fmt(_currentLocation!.altitude, decimals: 1)} m'),
                              _locationRow(Icons.access_time, 'Last Update', _fmtTime(_currentLocation!.timestamp)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_locationService.updatesSent > 0)
                        Text(
                          'Updates sent: ${_locationService.updatesSent}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isTracking ? Colors.greenAccent : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        child: ElevatedButton(
                          onPressed: _isStarting ? null : _toggleTracking,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isTracking ? Colors.red[600] : Colors.green[600],
                            disabledBackgroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 6,
                          ),
                          child: _isStarting
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Starting...',
                                      style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isTracking ? Icons.stop_circle_outlined : Icons.send_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _isTracking ? 'Stop Sending Location' : 'Start Sending Location',
                                      style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LiveTrackingScreen()),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: const BorderSide(color: Color(0xFF00C896), width: 1.5),
                            ),
                            elevation: 4,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.map_outlined, color: Color(0xFF00C896), size: 22),
                              SizedBox(width: 10),
                              Text(
                                'Live Tracking Map',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF00C896),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // GeoFence button
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GeoFenceScreen(),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: const BorderSide(color: Color(0xFFFF9800), width: 1.5),
                            ),
                            elevation: 4,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.fence_rounded, color: Color(0xFFFF9800), size: 22),
                              SizedBox(width: 10),
                              Text(
                                'GeoFence Zones',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFFFF9800),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Share on WhatsApp button
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        child: ElevatedButton(
                          onPressed: _currentLocation == null ? null : _shareOnWhatsApp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            disabledBackgroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 6,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/whatsapp_icon.png',
                                width: 22,
                                height: 22,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.share,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Share Location on WhatsApp',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
            if (_showLoginSuccess)
              Positioned(
                top: 10,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B46C1),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Color(0xFF6B46C1), size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Login Successful',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Welcome back ${locator<AuthViewModel>().username ?? 'User'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showLoginSuccess = false),
                        child: const Icon(Icons.close, color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

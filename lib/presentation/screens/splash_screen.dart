import 'package:flutter/material.dart';
import 'dart:async';
import '../../../main.dart'; // Import for AuthWrapper

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );

    _fadeController.forward();
    _scaleController.forward();

    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const AuthWrapper(),
            transitionDuration: const Duration(milliseconds: 1000),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3347), Color(0xFF0A2233)],
          ),
        ),
        child: Stack(
          children: [
            // Decorative radar circles
            Positioned(
              top: -80,
              left: -80,
              child: SizedBox(
                width: 320,
                height: 320,
                child: CustomPaint(painter: _RadarPainter()),
              ),
            ),

            // Bottom-right orange pin
            const Positioned(
              bottom: 28,
              right: 28,
              child: Icon(Icons.location_pin,
                  color: Color(0xFFFF6B2B), size: 44),
            ),

            // Centred branding
            Center(
              child: AnimatedBuilder(
                animation: _fadeController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: AnimatedBuilder(
                      animation: _scaleController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Location pin icon
                              const Icon(Icons.location_pin,
                                  color: Color(0xFFFF6B2B), size: 64),
                              const SizedBox(height: 12),

                              // TRAKNOVA wordmark
                              const Text(
                                'TRAKNOVA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Tagline
                              const Text(
                                'Your Location Tracking Partner.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),

                              const SizedBox(height: 48),

                              // Spinner
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF26C6DA)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            // Footer label
            const Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on_outlined,
                      color: Colors.white24, size: 14),
                  SizedBox(width: 5),
                  Text(
                    'TRAKNOVA',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 12,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final center = Offset(size.width * 0.3, size.height * 0.3);
    for (final r in [60.0, 110.0, 160.0, 210.0, 260.0]) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
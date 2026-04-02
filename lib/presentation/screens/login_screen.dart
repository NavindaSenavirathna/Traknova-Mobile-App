import 'package:flutter/material.dart';
import '../../features/auth/auth_view_model.dart';
import '../../core/services/locator.dart';

// ─── Brand colours ────────────────────────────────────────────────────────────
const _kBgDark = Color(0xFF0A2233);
const _kBgMid = Color(0xFF0D3347);
const _kOrange = Color(0xFFFF6B2B);
const _kCyan = Color(0xFF26C6DA);
const _kGreen = Color(0xFF4CD964);
const _kCard = Color(0xFF0F2E42);
const _kInputBg = Color(0xFFFFFFFF);
const _kHint = Color(0xFFAAAAAA);
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthViewModel _authViewModel;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _authViewModel = locator<AuthViewModel>();
    _authViewModel.addListener(_onAuthStateChanged);
  }

  @override
  void dispose() {
    _authViewModel.removeListener(_onAuthStateChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onAuthStateChanged() => setState(() {});

  Future<void> _handleLogin() async {
    _authViewModel.updateEmail(_usernameController.text);
    _authViewModel.updatePassword(_passwordController.text);
    final success = await _authViewModel.login();
    if (success && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background ──────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_kBgMid, _kBgDark],
              ),
            ),
          ),

          // ── Decorative radar circles (top-left) ─────────────────────────
          Positioned(
            top: -80,
            left: -80,
            child: _RadarCircles(),
          ),

          // ── Bottom-right orange pin ──────────────────────────────────────
          const Positioned(
            bottom: 24,
            right: 24,
            child: Icon(Icons.location_pin, color: _kOrange, size: 48),
          ),

          // ── Scrollable content ──────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 64),

                  // ── Logo row ──────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_pin,
                          color: _kOrange, size: 32),
                      const SizedBox(width: 8),
                      const Text(
                        'TRAKNOVA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your Location Tracking Partner.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 0.4,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── Hero text ────────────────────────────────────────
                  const Text(
                    'LOCATE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                  const Text(
                    'your vehicles & employees',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'WHEREVER THEY ARE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'EXPERIENCE TRAKNOVA',
                    style: TextStyle(
                      color: _kCyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ── Login card ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        // Error message
                        if (_authViewModel.errorMessage != null)
                          _buildErrorMessage(_authViewModel.errorMessage!),

                        // Username
                        _PillTextField(
                          controller: _usernameController,
                          hint: 'Username',
                          obscure: false,
                        ),

                        const SizedBox(height: 16),

                        // Password
                        _PillTextField(
                          controller: _passwordController,
                          hint: 'Password',
                          obscure: !_authViewModel.isPasswordVisible,
                        ),

                        const SizedBox(height: 28),

                        // SIGN IN button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed:
                                _authViewModel.isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: _authViewModel.isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'SIGN IN',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Forgot / Create account
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 13),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('•',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13)),
                            ),
                            TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              child: const Text(
                                'Create Account',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // ── Footer ───────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.location_on_outlined,
                          color: Colors.white38, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'TRAKNOVA',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 110),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error widgets ──────────────────────────────────────────────────────────
  Widget _buildErrorMessage(String errorMessage) {
    if (errorMessage == 'USER_ALREADY_LOGGED_IN') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: const Color(0xFFE53E3E), width: 2),
              ),
              child: const Center(
                child: Text('!',
                    style: TextStyle(
                        color: Color(0xFFE53E3E),
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'User already logged in another device. Please sign out from the other device to continue.',
                style: TextStyle(
                    color: Color(0xFFB0B0B0), fontSize: 13, height: 1.3),
              ),
            ),
            GestureDetector(
              onTap: _authViewModel.clearError,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: Color(0xFFB0B0B0), size: 18),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red[900]!.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[400]!),
      ),
      child: Text(errorMessage,
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
    );
  }
}

// ── Reusable pill text field ────────────────────────────────────────────────
class _PillTextField extends StatelessWidget {
  const _PillTextField({
    required this.controller,
    required this.hint,
    required this.obscure,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: _kHint, fontSize: 15),
        filled: true,
        fillColor: _kInputBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide:
              const BorderSide(color: _kCyan, width: 1.5),
        ),
      ),
    );
  }
}

// ── Decorative radar / sonar circles ───────────────────────────────────────
class _RadarCircles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 320,
      child: CustomPaint(painter: _RadarPainter()),
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


import 'package:flutter/material.dart';
import '../../features/auth/auth_view_model.dart';
import '../../core/services/locator.dart';

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

  void _onAuthStateChanged() {
    setState(() {}); // Rebuild UI when auth state changes
  }

  Future<void> _handleLogin() async {
    // Update view model with current input values
    _authViewModel.updateEmail(_usernameController.text);
    _authViewModel.updatePassword(_passwordController.text);
    
    final success = await _authViewModel.login();
    
    if (success && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
    // Error handling is done by the view model and displayed in the UI
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  
                  // Logo with error handling
                  SizedBox(
                    height: 80,
                    width: 200,
                    child: Image.asset(
                      "assets/logo.png",
                      height: 80,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback when logo is not found
                        return Container(
                          height: 80,
                          width: 200,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'DRIVEMASTER',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 40),

                  // Error message display
                  if (_authViewModel.errorMessage != null)
                    _buildErrorMessage(_authViewModel.errorMessage!),

                  RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: "DRIVE",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.normal, // Not bold
                            color: Color(0xFF333333),
                          ),
                        ),
                        TextSpan(
                          text: "MASTER",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold, // Bold
                            color: Color(0xFF333333),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Title
                  const Text(
                    "Login to your account",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF333333),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Username field
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0, bottom: 8.0),
                        child: Text(
                          "Username",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(25.0),
                          border: Border.all(
                            color: const Color(0xFFE5E5E5),
                            width: 1.0,
                          ),
                        ),
                        child: TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            hintText: "Enter your username",
                            hintStyle: TextStyle(
                              color: Color(0xFF999999),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Password field
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0, bottom: 8.0),
                        child: Text(
                          "Password",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(25.0),
                          border: Border.all(
                            color: const Color(0xFFE5E5E5),
                            width: 1.0,
                          ),
                        ),
                        child: TextField(
                          controller: _passwordController,
                          obscureText: !_authViewModel.isPasswordVisible,
                          decoration: const InputDecoration(
                            hintText: "Enter your password",
                            hintStyle: TextStyle(
                              color: Color(0xFF999999),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 16.0,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _authViewModel.isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90E2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                      ),
                      child: _authViewModel.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              "Login",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(String errorMessage) {
    // Check if this is the "user already logged in" error
    if (errorMessage == 'USER_ALREADY_LOGGED_IN') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C), // Dark background
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Red exclamation icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE53E3E), width: 2),
              ),
              child: const Center(
                child: Text(
                  '!',
                  style: TextStyle(
                    color: Color(0xFFE53E3E),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Error text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Error',
                    style: TextStyle(
                      color: Color(0xFFE53E3E),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'User already logged in another device, please sign out from other device to continue',
                    style: TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            
            // Close button
            GestureDetector(
              onTap: () {
                _authViewModel.clearError();
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  color: Color(0xFFB0B0B0),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // Default error message style for other errors
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[300]!),
      ),
      child: Text(
        errorMessage,
        style: TextStyle(
          color: Colors.red[700],
          fontSize: 14,
        ),
      ),
    );
  }
}


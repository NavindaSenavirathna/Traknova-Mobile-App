import 'package:flutter/material.dart';
import '../../features/auth/auth_view_model.dart';
import '../../core/services/locator.dart';
import '../../main.dart';
import 'login_screen.dart';

// Logout Session Popup Component
class LogoutSessionPopup extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const LogoutSessionPopup({
    Key? key,
    required this.onCancel,
    required this.onConfirm,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logout Icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.logout,
              color: Colors.grey[600],
              size: 24,
            ),
          ),
          
          const SizedBox(height: 15),
          
          // Title
          const Text(
            'Logout',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          
          const SizedBox(height: 10),
          
          // Message
          const Text(
            'Please confirm to session logout!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 25),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 45,
                  child: ElevatedButton(
                    onPressed: onCancel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[500],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: SizedBox(
                  height: 45,
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Example usage in a screen
class ExampleScreenWithLogout extends StatefulWidget {
  const ExampleScreenWithLogout({super.key});

  @override
  _ExampleScreenWithLogoutState createState() => _ExampleScreenWithLogoutState();
}

class _ExampleScreenWithLogoutState extends State<ExampleScreenWithLogout> {
  bool showLogoutPopup = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Your main screen content here
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Your App Content',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              showLogoutPopup = true;
                            });
                          },
                          child: const Text('Show Logout Popup'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Logout Popup Overlay
          if (showLogoutPopup)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: LogoutSessionPopup(
                  onCancel: () {
                    setState(() {
                      showLogoutPopup = false;
                    });
                  },
                  onConfirm: () {
                    setState(() {
                      showLogoutPopup = false;
                    });
                    // Handle logout confirmation
                    _handleLogout();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleLogout() {
    // Use the real logout dialog helper
    LogoutDialogHelper.showLogoutDialog(context);
  }
}

// If you want to use it as a dialog instead of overlay
class LogoutDialogHelper {
  static void showLogoutDialog(BuildContext context, {
    VoidCallback? onConfirm,
  }) {
    final authViewModel = locator<AuthViewModel>();
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: LogoutSessionPopup(
            onCancel: () {
              Navigator.of(context).pop();
            },
            onConfirm: () async {
              // Save navigator references BEFORE any async operations
              final rootNavigator = Navigator.of(context, rootNavigator: true);
              final localNavigator = Navigator.of(context);
              
              // Close the confirmation dialog first
              localNavigator.pop();
              
              // Show loading dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Text('Logging out...'),
                    ],
                  ),
                ),
              );

              try {
                print('🔄 Starting logout process...');
                
                // Perform logout
                await authViewModel.logout();
                
                print('✅ Logout API call completed successfully');
                
                // Dismiss loading dialog safely using saved navigator
                try {
                  rootNavigator.pop();
                  print('✅ Loading dialog dismissed successfully');
                } catch (e) {
                  print('Warning: Could not dismiss loading dialog: $e');
                }
                
                print('🔄 Navigating to login screen...');
                
                // Navigate using multiple methods for robustness
                try {
                  // Method 1: Use named route with root navigator
                  rootNavigator.pushNamedAndRemoveUntil('/login', (route) => false);
                  print('✅ Navigation to login completed using named route!');
                } catch (navError) {
                  print('❌ Named route navigation failed: $navError');
                  
                  try {
                    // Method 2: Use MaterialPageRoute with root navigator
                    rootNavigator.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                    print('✅ Navigation to login completed using MaterialPageRoute!');
                  } catch (navError2) {
                    print('❌ MaterialPageRoute navigation failed: $navError2');
                    
                    try {
                      // Method 3: Use global navigator key
                      navigatorKey.currentState?.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                      print('✅ Navigation completed using global navigator key!');
                    } catch (navError3) {
                      print('❌ Global navigator key failed: $navError3');
                      
                      try {
                        // Method 4: Use local navigator as last resort
                        localNavigator.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                        print('✅ Navigation completed using local navigator!');
                      } catch (navError4) {
                        print('❌ All navigation methods failed: $navError4');
                        print('🔄 User will need to manually restart app');
                      }
                    }
                  }
                }
                
                // Call custom callback if provided
                onConfirm?.call();
                
              } catch (e) {
                print('❌ Logout API error: $e');
                
                // Dismiss loading dialog safely using saved navigator
                try {
                  rootNavigator.pop();
                } catch (navError) {
                  print('Warning: Could not dismiss loading dialog: $navError');
                }
                
                // Show info dialog instead of error - logout still works locally
                try {
                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Logout Notice'),
                      content: const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('You have been logged out successfully.'),
                          SizedBox(height: 8),
                          Text(
                            'Note: Server session may already be expired.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            
                            // Navigate using multiple methods
                            try {
                              rootNavigator.pushNamedAndRemoveUntil('/login', (route) => false);
                            } catch (navError) {
                              try {
                                rootNavigator.pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (route) => false,
                                );
                              } catch (navError2) {
                                try {
                                  navigatorKey.currentState?.pushAndRemoveUntil(
                                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                                    (route) => false,
                                  );
                                } catch (navError3) {
                                  print('❌ All navigation methods failed: $navError3');
                                }
                              }
                            }
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                } catch (dialogError) {
                  print('❌ Cannot show dialog, forcing navigation: $dialogError');
                  // Force navigation using multiple methods
                  try {
                    rootNavigator.pushNamedAndRemoveUntil('/login', (route) => false);
                  } catch (navError) {
                    try {
                      rootNavigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    } catch (navError2) {
                      try {
                        navigatorKey.currentState?.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      } catch (navError3) {
                        print('❌ All forced navigation methods failed: $navError3');
                      }
                    }
                  }
                }
              }
            },
          ),
        );
      },
    );
  }
}
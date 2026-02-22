// screens/trip_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'endtrip_screen.dart';
import 'dashboard_screen.dart';
import 'userprofile_screen.dart';
import 'filinginfo_screen.dart';
import 'markdrop_screen.dart';
import 'login_screen.dart';
import '../../core/services/locator.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/database/trip_database.dart';
import '../../features/auth/auth_view_model.dart';
import '../../main.dart';

class TripScreen extends StatefulWidget {
  final String vehicleNumber;
  final String odometerReading;

  const TripScreen({
    super.key,
    required this.vehicleNumber,
    required this.odometerReading,
  });

  @override
  State<TripScreen> createState() => _TripScreenState();
}

// Class for handling odometer reading modal
class OdometerReadingModal extends StatefulWidget {
  final String vehicleNumber;
  final VoidCallback onConfirm;

  const OdometerReadingModal({
    Key? key,
    required this.vehicleNumber,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<OdometerReadingModal> createState() => _OdometerReadingModalState();
}

class _OdometerReadingModalState extends State<OdometerReadingModal> {
  final TextEditingController _odometerController = TextEditingController();

  @override
  void dispose() {
    _odometerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'End Trip',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            // Speedometer image placeholder
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/speedometer.png', // Add your speedometer image
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: Icon(
                          Icons.speed,
                          size: 80,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Odometer Reading input
            TextField(
              controller: _odometerController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Odometer Reading',
                hintText: 'Enter current odometer reading',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 30),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey[400],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_odometerController.text.trim().isNotEmpty) {
                        Navigator.pop(context);
                        widget.onConfirm();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter odometer reading'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
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
}



class _TripScreenState extends State<TripScreen> {
  Timer? _tripTimer;
  Timer? _pauseTimer;
  int _tripSeconds = 0;
  int _pauseSeconds = 0;
  bool _isPaused = false;
  bool _showStatusMessage = false;
  
  late final VehicleService _vehicleService;
  ActiveTrip? _currentTrip;

  @override
  void initState() {
    super.initState();
    _vehicleService = locator<VehicleService>();
    _loadTripData();
    _showTripStatusMessage();
  }

  @override
  void dispose() {
    _tripTimer?.cancel();
    _pauseTimer?.cancel();
    super.dispose();
  }

  // Load trip data from local database and calculate elapsed time
  Future<void> _loadTripData() async {
    try {
      print('📱 Loading trip data from local database...');
      _currentTrip = await _vehicleService.getLocalActiveTrip();
      
      if (_currentTrip != null) {
        // Calculate elapsed time from engagement (this keeps counting even when app is closed)
        final elapsed = _currentTrip!.elapsedTimeFromEngagement;
        _tripSeconds = elapsed.inSeconds;
        
        print('⏱️ Trip loaded: ${_currentTrip!.vehicleNumber}, elapsed: ${elapsed.inSeconds}s');
        
        // Start the timer from current position
        _startTripTimer();
        
        setState(() {});
      } else {
        print('⚠️ No active trip found in database');
        // Start timer from 0 if no trip found (fallback)
        _startTripTimer();
      }
    } catch (e) {
      print('❌ Error loading trip data: $e');
      // Fallback to start timer from 0
      _startTripTimer();
    }
  }

  void _startTripTimer() {
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          _tripSeconds++;
        });
      }
    });
  }

  void _startPauseTimer() {
    _pauseTimer?.cancel(); // Cancel any existing pause timer
    print('⏸️ Starting pause timer, current _isPaused: $_isPaused');
    _pauseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) { // Only increment if still paused
        setState(() {
          _pauseSeconds++;
        });
        print('⏱️ Pause timer tick: ${_pauseSeconds}s');
      } else {
        print('⏸️ Stopping pause timer - not paused anymore');
        timer.cancel(); // Stop timer if no longer paused
      }
    });
  }

  void _stopPauseTimer() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }

  // Get total pause time for the entire trip
  String getTotalPauseTime() {
    final hours = _pauseSeconds ~/ 3600;
    final minutes = (_pauseSeconds % 3600) ~/ 60;
    final secs = _pauseSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _showTripStatusMessage() {
    setState(() {
      _showStatusMessage = true;
    });
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showStatusMessage = false;
        });
      }
    });
  }

  void _pauseTrip() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pause Trip',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Are you sure you need to pause this trip',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'No',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        
                        if (_currentTrip != null) {
                          // Store context references before async operation
                          final navigator = Navigator.of(context);
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          
                          // Show loading - using try-catch for safety
                          try {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          } catch (e) {
                            print('⚠️ Could not show loading dialog: $e');
                          }
                          
                          try {
                            // Call API to pause trip
                            final success = await _vehicleService.pauseTrip(_currentTrip!);
                            
                            // Close loading dialog safely
                            if (mounted) {
                              try {
                                navigator.pop();
                              } catch (e) {
                                print('⚠️ Could not close pause loading dialog: $e');
                              }
                            }
                            
        if (success) {
          // Update UI state
          if (mounted) {
            setState(() {
              _isPaused = true;
              // Don't reset _pauseSeconds - keep accumulating pause time
              print('🟡 Trip paused in UI: _isPaused = $_isPaused, _pauseSeconds = $_pauseSeconds');
            });
            _startPauseTimer();
            print('⏸️ Pause timer started - current state: _isPaused = $_isPaused');
            _showTripStatusMessage();                                // Show success message
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Trip paused successfully and updated in database'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            } else {
                              // Show detailed error message
                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to pause trip in database. Trip may not be properly synced with server. Please try restarting the trip.'),
                                    backgroundColor: Colors.red,
                                    duration: Duration(seconds: 6),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            // Close loading dialog if error
                            if (mounted) {
                              try {
                                navigator.pop();
                              } catch (e) {
                                print('⚠️ Could not close pause loading dialog on error: $e');
                              }
                            }
                            
                            // Show error message
                            if (mounted) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text('Error pausing trip: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Yes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resumeTrip() async {
    if (_currentTrip != null) {
      // Store context references before async operation
      final navigator = Navigator.of(context);
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      
      // Show loading - using try-catch for safety
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      } catch (e) {
        print('⚠️ Could not show resume loading dialog: $e');
      }
      
      try {
        // Call API to resume trip
        final success = await _vehicleService.resumeTrip(_currentTrip!);
        
        // Close loading dialog safely
        if (mounted) {
          try {
            navigator.pop();
          } catch (e) {
            print('⚠️ Could not close resume loading dialog: $e');
          }
        }
        
        if (success) {
          // Update UI state
          if (mounted) {
            setState(() {
              _isPaused = false;
              // Don't reset _pauseSeconds - keep accumulating pause time
              print('🟢 Trip resumed in UI: _isPaused = $_isPaused, _pauseSeconds = $_pauseSeconds');
            });
            _stopPauseTimer();
            print('▶️ Pause timer stopped - current state: _isPaused = $_isPaused');
            _showTripStatusMessage();
            
            // Show success message
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Trip resumed successfully and updated in database'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // Show detailed error message
          if (mounted) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Failed to resume trip in database. Trip may not be properly synced with server. Please try restarting the trip.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 6),
              ),
            );
          }
        }
      } catch (e) {
        // Close loading dialog if error
        if (mounted) {
          try {
            navigator.pop();
          } catch (e) {
            print('⚠️ Could not close resume loading dialog on error: $e');
          }
        }
        
        // Show error message
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Error resuming trip: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _endTrip() async {
    try {
      print('🏁 Showing End Trip modal...');
      
      // Show End Trip Modal with speedometer and odometer input
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => EndTripModal(
            onConfirm: (double endOdometerReading) async {
              try {
                print('🏁 Ending trip after odometer confirmation with reading: $endOdometerReading');
                
                // Store context references before async operation
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                
                // Show loading - using try-catch for safety
                try {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                } catch (e) {
                  print('⚠️ Could not show end trip loading dialog: $e');
                }
                
                // End trip using vehicle service with user's odometer reading
                await _vehicleService.endTrip(endOdometerReading: endOdometerReading);
                
                // Close loading dialog safely
                if (mounted) {
                  try {
                    navigator.pop();
                  } catch (navError) {
                    print('⚠️ Could not close end trip loading dialog: $navError');
                  }
                }
                
                // Show success and navigate back safely
                if (mounted) {
                  try {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Trip ended successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  
                    // Navigate back to dashboard and force refresh
                    print('🏠 Navigating back to dashboard after trip completion...');
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const DashboardScreen()),
                      (route) => false,
                    );
                    print('🏠 Navigation completed - dashboard should show Release Vehicle button');
                  } catch (navError) {
                    print('⚠️ Navigation error after successful trip end: $navError');
                  }
                }
              } catch (e) {
                print('❌ Error ending trip: $e');
                
                // Store context references for error handling
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                
                // Close loading dialog if it's open
                if (mounted) {
                  try {
                    navigator.pop();
                  } catch (navError) {
                    print('⚠️ Could not close end trip loading dialog on error: $navError');
                  }
                }
                
                // Show error
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to end trip: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ),
      );
    } catch (e) {
      print('❌ Error showing end trip modal: $e');
      
      // Show error with context safety
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to show end trip dialog: $e'),
              backgroundColor: Colors.red,
            ),
          );
        } catch (navError) {
          print('⚠️ Could not show end trip error message: $navError');
        }
      }
    }
  }



  Widget _buildTimeUnit(int value) {
    return Container(
      width: 50,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  void _handleSwipeUp() {
    _showBottomSheetModal();
  }



  void _showBottomSheetModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavigationButton(
                  imagePath: 'assets/add_filling_icon.png',
                  label: 'Add Filling\nDetails',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FillingInformationScreen(),
                      ),
                    );
                  },
                ),
                _buildNavigationButton(
                  imagePath: 'assets/mark_drop_icon.png',
                  label: 'Mark Drop\nPoint',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MarkDropScreen(),
                      ),
                    );
                  },
                ),
                _buildNavigationButton(
                  imagePath: 'assets/user_profile_icon.png',
                  label: 'User\nProfile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UserProfileScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildNavigationButton(
              imagePath: 'assets/logout_icon.png',
              label: 'Logout\nSession',
              onTap: () {
                Navigator.pop(context);
                
                // For now, let's test direct navigation without logout dialog
                // Comment this line and uncomment the next line to test direct navigation
                _showLogoutDialog();
                
                // Uncomment this line to test direct navigation without logout process:
                // _testDirectNavigation();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required String imagePath,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _performSimpleLogout() async {
    try {
      print('🔄 Starting simple logout process...');
      
      // Try minimal logout approach - skip AuthViewModel entirely for now
      print('🔄 Clearing local storage directly...');
      
      // Clear local storage directly using AuthService
      final authService = locator<AuthService>();
      await authService.logout();
      
      print('✅ Direct logout completed, navigating to login...');
      
      // Use the most direct navigation approach possible
      _navigateToLogin();
      
    } catch (e) {
      print('❌ Direct logout error: $e');
      
      // If even direct logout fails, just navigate anyway
      print('🔄 Skipping logout, just navigating to login...');
      _navigateToLogin();
    }
  }

  void _performMinimalLogout() {
    print('�🚀🚀 PERFORMING MINIMAL LOGOUT - START 🚀🚀🚀');
    print('🔍 Method called at: ${DateTime.now()}');
    
    // Skip all logout operations and just navigate
    // This is for testing if the issue is with logout or navigation
    try {
      print('🔄 About to call _navigateToLogin()...');
      _navigateToLogin();
      print('🔄 _navigateToLogin() call completed');
    } catch (e) {
      print('❌ Error in _performMinimalLogout: $e');
      print('❌ Stack trace: ${e.toString()}');
    }
    
    print('🚀🚀🚀 PERFORMING MINIMAL LOGOUT - END 🚀🚀🚀');
  }

  void _navigateToLogin() {
    print('🔄 _navigateToLogin() called - START');
    print('🔍 navigatorKey: $navigatorKey');
    print('🔍 navigatorKey.currentState: ${navigatorKey.currentState}');
    print('🔍 mounted: $mounted');
    print('🔍 context: $context');
    
    // Try the most basic approach first
    try {
      print('🔄 Attempting basic navigation...');
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      print('✅ Basic navigation completed!');
      return;
    } catch (e) {
      print('❌ Basic navigation failed: $e');
      print('❌ Error details: ${e.toString()}');
    }
    
    try {
      print('🔄 Attempting global navigator method...');
      final navState = navigatorKey.currentState;
      print('🔍 navState available: ${navState != null}');
      
      if (navState != null) {
        print('� Executing pushAndRemoveUntil...');
        navState.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
            settings: const RouteSettings(name: '/login'),
          ),
          (route) => false,
        );
        print('✅ Global navigator method completed!');
        return;
      } else {
        print('❌ navState is null');
      }
    } catch (e) {
      print('❌ Global navigator method failed: $e');
      print('❌ Stack trace: ${e.toString()}');
    }
    
    try {
      print('🔄 Attempting named route...');
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
      print('✅ Named route completed!');
      return;
    } catch (e) {
      print('❌ Named route failed: $e');
    }
    
    try {
      print('🔄 Attempting context navigator...');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        print('✅ Context navigator completed!');
        return;
      } else {
        print('❌ Widget not mounted');
      }
    } catch (e) {
      print('❌ Context navigator failed: $e');
    }
    
    print('❌❌❌ ALL NAVIGATION METHODS FAILED ❌❌❌');
    print('🔍 Final state check:');
    print('  - navigatorKey: $navigatorKey');
    print('  - currentState: ${navigatorKey.currentState}');
    print('  - mounted: $mounted');
    print('  - context: $context');
  }

  // Test method for debugging - can be called directly
  void _testDirectNavigation() {
    print('🧪 Testing direct navigation to login...');
    _navigateToLogin();
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          contentPadding: const EdgeInsets.all(20),
          content: Column(
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
              const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please confirm to session logout!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[500],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
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
                        onPressed: () {
                          print('🎯🎯🎯 CONFIRM BUTTON PRESSED 🎯🎯🎯');
                          print('🔍 Button press time: ${DateTime.now()}');
                          print('� dialogContext: $dialogContext');
                          
                          try {
                            print('🔄 Attempting to close dialog...');
                            Navigator.of(dialogContext).pop();
                            print('✅ Dialog closed successfully');
                          } catch (e) {
                            print('❌ Error closing dialog: $e');
                          }
                          
                          print('🔄 About to call _performMinimalLogout...');
                          
                          // For testing: try minimal logout first (just navigation)
                          // If this works, then the issue is with the logout process
                          // If this doesn't work, then the issue is with navigation
                          
                          // SUPER SIMPLE TEST: Just try to navigate directly
                          print('🧪 TESTING SUPER SIMPLE NAVIGATION...');
                          try {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            );
                            print('✅ Super simple navigation worked!');
                          } catch (e) {
                            print('❌ Super simple navigation failed: $e');
                            
                            try {
                              // Test 1: Minimal logout (just navigation)
                              _performMinimalLogout();
                            } catch (e2) {
                              print('❌ Error in minimal logout: $e2');
                            }
                          }
                          
                          print('🎯 CONFIRM BUTTON HANDLER COMPLETE');
                          
                          // Test 2: If you want to test with actual logout, uncomment this:
                          // _performSimpleLogout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C2C2C),
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onPanUpdate: (details) {
                if (details.delta.dy < -5) {
                  _handleSwipeUp();
                }
              },
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/leather_texture.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              child: Column(
                children: [
                  // Header
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Text(
                          'DRIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        Text(
                          'MASTER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Vehicle Number
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text(
                          'Vehicle Number : ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          widget.vehicleNumber,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Control Button
                  GestureDetector(
                    onTap: () {
                      print('🔘 Button tapped - _isPaused: $_isPaused, _pauseSeconds: $_pauseSeconds');
                      print('🔘 Button will show: ${_isPaused ? "resume_button.png" : "pause_button.png"}');
                      if (_isPaused) {
                        print('🔘 Calling _resumeTrip()');
                        _resumeTrip();
                      } else {
                        print('🔘 Calling _pauseTrip()');
                        _pauseTrip();
                      }
                    },
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Builder(
                          builder: (context) {
                            String buttonImage = _isPaused ? 'assets/resume_button.png' : 'assets/pause_button.png';
                            print('🔘 UI Building button - _isPaused: $_isPaused, showing: $buttonImage');
                            return Image.asset(
                              buttonImage,
                              width: 150,
                              height: 150,
                              fit: BoxFit.cover,
                            );
                          }
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                 // Timers
                  if (_isPaused) ...[
                    Builder(
                      builder: (context) {
                        print('🔘 UI Building pause timer - _isPaused: $_isPaused, _pauseSeconds: $_pauseSeconds');
                        return const Text(
                          'Pause Timer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 20),
                    // Pause Timer display with background image
                    Container(
                      height: 80,
                      width: 280,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Background image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.asset(
                              'assets/timer.png',
                              height: 80,
                              width: 280,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 80,
                                  width: 280,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: Colors.grey.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Overlay for better text visibility
                          Container(
                            height: 80,
                            width: 280,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          // Pause timer text with proper formatting
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildTimeUnit(_pauseSeconds ~/ 3600), // Hours
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  ':',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _buildTimeUnit((_pauseSeconds % 3600) ~/ 60), // Minutes
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  ':',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _buildTimeUnit(_pauseSeconds % 60), // Seconds
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const Text(
                    'Trip Timer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Timer display with background image
                  Container(
                    height: 80,
                    width: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.asset(
                            'assets/timer.png',
                            height: 80,
                            width: 280,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 80,
                                width: 280,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.grey.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Overlay for better text visibility
                        Container(
                          height: 80,
                          width: 280,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        // Timer text with proper formatting
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildTimeUnit(_tripSeconds ~/ 3600), // Hours
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _buildTimeUnit((_tripSeconds % 3600) ~/ 60), // Minutes
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                ':',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _buildTimeUnit(_tripSeconds % 60), // Seconds
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Status indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Image.asset(
                            'assets/doors_open.png',
                            width: 32,
                            height: 32,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.door_front_door,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Doors open',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Image.asset(
                            'assets/cabin_temp.png',
                            width: 32,
                            height: 32,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Center(
                                  child: Text(
                                    '30°',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Cabin Temp',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Image.asset(
                            'assets/seat_belts.png',
                            width: 32,
                            height: 32,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.airline_seat_legroom_normal,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Seat Belts',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // End Trip Button
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: ElevatedButton(
                      onPressed: _endTrip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        'End Trip',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            ),
            // Status message
            if (_showStatusMessage)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Text(
                      'vehicle trip status updated',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
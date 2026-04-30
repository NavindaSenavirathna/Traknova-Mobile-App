// main.dart
import 'package:drive_master_app/presentation/screens/login_screen.dart';
import 'package:drive_master_app/presentation/screens/dashboard_screen.dart';
import 'package:drive_master_app/presentation/screens/splash_screen.dart';
import 'package:drive_master_app/presentation/screens/trip_screen.dart';
import 'package:drive_master_app/core/database/database_factory_initializer.dart';
import 'package:drive_master_app/core/services/locator.dart';
import 'package:drive_master_app/core/services/vehicle_service.dart';
import 'package:drive_master_app/core/services/geofence_notification_service.dart';
import 'package:drive_master_app/features/auth/auth_view_model.dart';
import 'package:flutter/material.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeDatabaseFactory();
  setupLocator(); // Initialize dependency injection
  runApp(const DriveMasterApp());
}

// Global navigation key to avoid context issues
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class DriveMasterApp extends StatefulWidget {
  const DriveMasterApp({super.key});

  @override
  State<DriveMasterApp> createState() => _DriveMasterAppState();
}

class _DriveMasterAppState extends State<DriveMasterApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Wire navigator key to geofence notification service for overlay banners
    GeoFenceNotificationService().setNavigatorKey(navigatorKey);
    print('📱 App lifecycle observer initialized');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Get the vehicle service and update foreground state
    try {
      final vehicleService = locator<VehicleService>();
      
      switch (state) {
        case AppLifecycleState.resumed:
          print('📱 App is in FOREGROUND - enabling drop point calls');
          vehicleService.setAppForegroundState(true);
          break;
        case AppLifecycleState.paused:
        case AppLifecycleState.inactive:
        case AppLifecycleState.detached:
          print('📱 App is in BACKGROUND - disabling drop point calls');
          vehicleService.setAppForegroundState(false);
          break;
        case AppLifecycleState.hidden:
          print('📱 App is HIDDEN - disabling drop point calls');
          vehicleService.setAppForegroundState(false);
          break;
      }
    } catch (e) {
      print('⚠️ Error updating app lifecycle state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'DriveMaster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const DashboardScreen(),
        '/login': (context) => const LoginScreen(),
        '/splash': (context) => const SplashScreen(),
        '/auth': (context) => const AuthWrapper(),
      },
    );
  }
}

// Wrapper to check auth status on app start
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final AuthViewModel _authViewModel;
  late final VehicleService _vehicleService;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _authViewModel = locator<AuthViewModel>();
    _vehicleService = locator<VehicleService>();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(milliseconds: 200)); // Reduced delay since splash screen handles the timing
    
    // Initialize services first
    await _vehicleService.initializeTripServices();
    
    // Try auto-login first using stored SQLite credentials
    print('🔄 Checking for stored credentials...');
    final authService = locator<AuthViewModel>().authService;
    await authService.initialize();
    
    final autoLoginSuccess = await authService.tryAutoLogin();
    
    if (autoLoginSuccess) {
      print('✅ Auto-login successful');
      // Update auth view model state
      await _authViewModel.checkLoginStatus();
    }
    
    final isLoggedIn = await _authViewModel.checkLoginStatus();
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (isLoggedIn) {
        // Check for active trips after login confirmation
        await _checkForActiveTrips();
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<void> _checkForActiveTrips() async {
    try {
      print('🔍 Checking for active trips on app startup...');
      
      // Initialize trip persistence service
      await _vehicleService.initializeTripServices();
      
      final activeTrip = await _vehicleService.getLocalActiveTrip();
      
      if (activeTrip != null) {
        print('✅ Found active trip on startup: ${activeTrip.vehicleNumber}');
        
        // Navigate directly to trip screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => TripScreen(
              vehicleNumber: activeTrip.vehicleNumber,
              odometerReading: activeTrip.startOdometer.toString(),
            ),
          ),
        );
      } else {
        print('📭 No active trip found, going to dashboard');
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      print('❌ Error checking for active trips: $e');
      // Fallback to dashboard on error
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00B4D8)),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink(); // This shouldn't be reached
  }
}
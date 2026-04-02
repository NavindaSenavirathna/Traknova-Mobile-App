import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../../core/services/locator.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/services/auth_service.dart';
import 'trip_screen.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});
  
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  Barcode? result;
  bool _showStartTripDialog = false;
  final TextEditingController _odometerController = TextEditingController();
  bool _hasLocationPermission = false;
  bool _hasCameraPermission = false;
  bool _isFlashOn = false;
  bool _permissionsChecked = false;
  bool _isEngagingVehicle = false;
  bool _isFrontCamera = false; // Track camera facing direction
  VehicleEngagementResponse? _vehicleResponse;
  String? _selectedRoute;
  List<RouteInfo> _availableRoutes = [];
  bool _isLoadingRoutes = false;
  
  late final VehicleService _vehicleService;

  @override
  void initState() {
    super.initState();
    _vehicleService = locator<VehicleService>();
    
    _checkAllPermissions();
    _loadAvailableRoutes();
  }

  // Get unique routes (remove duplicates based on UUID)
  List<RouteInfo> _getUniqueRoutes() {
    final Map<String, RouteInfo> uniqueRoutes = {};
    for (var route in _availableRoutes) {
      uniqueRoutes[route.uuid] = route;
    }
    return uniqueRoutes.values.toList();
  }

  // Load available routes from API
  Future<void> _loadAvailableRoutes() async {
    print('🔍 Loading available routes...');
    setState(() {
      _isLoadingRoutes = true;
    });

    try {
      // Get schedules from API and extract routes
      final schedules = await _vehicleService.getSchedules();
      final routes = schedules.map((schedule) => schedule.route).toList();
      
      print('✅ Loaded ${routes.length} routes successfully');
      for (var route in routes) {
        print('   - ${route.routeName} (${route.routeNo})');
      }
      
      setState(() {
        _availableRoutes = routes;
        // Auto-select first route if available
        if (routes.isNotEmpty) {
          _selectedRoute = routes.first.uuid;
        }
      });
    } catch (e) {
      print('❌ Failed to load routes: $e');
      setState(() {
        _availableRoutes = [];
        _selectedRoute = null;
      });
    } finally {
      setState(() {
        _isLoadingRoutes = false;
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    _odometerController.dispose();
    super.dispose();
  }

  Future<void> _checkAllPermissions() async {
    // Check location permission first (use locationWhenInUse for better Android compatibility)
    final locationStatus = await Permission.locationWhenInUse.status;
    setState(() {
      _hasLocationPermission = locationStatus.isGranted;
    });

    if (!_hasLocationPermission) {
      await _requestLocationPermission();
    }

    // Then check camera permission
    final cameraStatus = await Permission.camera.status;
    setState(() {
      _hasCameraPermission = cameraStatus.isGranted;
    });

    if (!_hasCameraPermission) {
      await _requestCameraPermission();
    }

    setState(() {
      _permissionsChecked = true;
    });
  }

  Future<void> _requestLocationPermission() async {
    print('🗺️ Requesting location permissions...');
    
    // First request basic location permission
    final basicStatus = await Permission.locationWhenInUse.request();
    
    if (basicStatus.isGranted) {
      print('✅ Basic location permission granted');
      
      // Then request background location for continuous tracking
      print('🔄 Requesting background location permission...');
      final backgroundStatus = await Permission.locationAlways.request();
      
      if (backgroundStatus.isGranted) {
        print('✅ Background location permission granted');
        _hasLocationPermission = true;
      } else {
        print('⚠️ Background location permission denied, using foreground only');
        _hasLocationPermission = true; // Still allow with foreground permission
      }
    } else {
      print('❌ Basic location permission denied');
      _hasLocationPermission = false;
    }
    
    setState(() {});
    
    if (!_hasLocationPermission) {
      _showPermissionDialog('Location', 
        'Location access is required for trip tracking. Please enable location permissions in settings.'
      );
    } else if (basicStatus.isGranted && !await Permission.locationAlways.isGranted) {
      _showPermissionDialog('Background Location', 
        'For continuous trip tracking, please enable "Allow all the time" location access in settings.'
      );
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _hasCameraPermission = status.isGranted;
    });
    
    if (!status.isGranted) {
      _showPermissionDialog('Camera', 'Camera access is required to scan QR codes.');
    }
  }

  void _showPermissionDialog(String permissionType, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('$permissionType Permission Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (!_showStartTripDialog && scanData.code != null) {
        setState(() {
          result = scanData;
        });
        _handleQRCodeScanned(scanData.code!);
      }
    });
  }

  void _handleQRCodeScanned(String code) async {
    // Pause the camera while processing
    controller?.pauseCamera();
    
    setState(() {
      _isEngagingVehicle = true;
    });
    
    try {
      // Check authentication status first
      final authService = locator<AuthService>();
      final token = await authService.getStoredToken();
      final username = await authService.getStoredUsername();
      
      print('🔍 Auth Debug - Token length: ${token?.length ?? 0}');
      print('🔍 Auth Debug - Token starts with "{": ${token?.startsWith('{') ?? false}');
      print('🔍 Auth Debug - Token (FULL): $token');
      print('🔍 Auth Debug - Username: $username');
      
      if (token == null || token.isEmpty) {
        throw VehicleEngagementException('User not authenticated. Please login first.');
      }
      
      // Call vehicle engagement API
      print('🔍 QR Code scanned: $code');
      
      // Determine schedule UUID for vehicle engagement
      String? engagementScheduleUuid;
      if (_availableRoutes.isNotEmpty && _selectedRoute != null) {
        // Find matching schedule for the selected route
        try {
          final schedules = await _vehicleService.getSchedules();
          final matchingSchedule = schedules.firstWhere(
            (schedule) => schedule.route.uuid == _selectedRoute,
            orElse: () => schedules.first, // Fallback to first schedule
          );
          engagementScheduleUuid = matchingSchedule.uuid;
          print('🔍 Using schedule UUID for engagement: $engagementScheduleUuid');
        } catch (e) {
          print('⚠️ Could not determine schedule UUID: $e');
          engagementScheduleUuid = null;
        }
      }
      
      // Check login status
      final isLoggedIn = await authService.isLoggedIn();
      
      print('🔑 Authentication check:');
      print('   - Logged in: $isLoggedIn');
      print('   - Username: "$username"');
      print('   - Token: "${token.substring(0, 20)}..."');
      print('   - Token length: ${token.length}');
      
      if (!isLoggedIn || username == null || username.isEmpty) {
        throw Exception('User not logged in or username missing. Please login first.');
      }
      
      // Call vehicle engagement API
      _vehicleResponse = await _vehicleService.engageVehicle(code, scheduleUuid: engagementScheduleUuid);
      
      print('✅ Vehicle engagement successful');
      
      // Save engagement to local database immediately (timer starts from here)
      if (_vehicleResponse != null && _vehicleResponse!.content != null) {
        try {
          print('🔍 Saving engagement with UUID: ${_vehicleResponse!.content!.vehicle.vehicleUuid}');
          print('🔍 Vehicle Number: ${_vehicleResponse!.content!.vehicle.vehicleNo}');
          
          await _vehicleService.saveVehicleEngagementToLocal(
            vehicleNumber: _vehicleResponse!.content!.vehicle.vehicleNo,
            vehicleUuid: _vehicleResponse!.content!.vehicle.vehicleUuid,
            routeUuid: _selectedRoute ?? (_vehicleResponse!.content!.schedules.isNotEmpty 
                ? _vehicleResponse!.content!.schedules.first.route.uuid 
                : ''),
            routeName: _selectedRoute != null 
                ? _availableRoutes.firstWhere((r) => r.uuid == _selectedRoute).routeName 
                : (_vehicleResponse!.content!.schedules.isNotEmpty 
                    ? _vehicleResponse!.content!.schedules.first.route.routeName 
                    : null),
            scheduleUuid: _vehicleResponse!.content!.schedules.isNotEmpty 
                ? _vehicleResponse!.content!.schedules.first.uuid 
                : '',
            odometerReading: '0', // Will be updated when trip starts
          );
          print('✅ Vehicle engagement saved to local database - timer started');
        } catch (e) {
          print('⚠️ Failed to save engagement to local database: $e');
        }
      }
      
      // Debug: Log vehicle engagement response details
      print('🔍 Vehicle Response Debug:');
      print('   - Status: ${_vehicleResponse?.status}');
      print('   - Status Code: ${_vehicleResponse?.statusCode}');
      print('   - Message: ${_vehicleResponse?.message}');
      print('   - Has Content: ${_vehicleResponse?.content != null}');
      if (_vehicleResponse?.content != null) {
        print('   - Vehicle No: ${_vehicleResponse!.content!.vehicle.vehicleNo}');
        print('   - Vehicle UUID: ${_vehicleResponse!.content!.vehicle.vehicleUuid}');
        print('   - Device IMEI: ${_vehicleResponse!.content!.vehicle.activeDeviceImei}');
        print('   - Schedules Count: ${_vehicleResponse!.content!.schedules.length}');
        if (_vehicleResponse!.content!.schedules.isNotEmpty) {
          print('   - First Schedule UUID: ${_vehicleResponse!.content!.schedules.first.uuid}');
          print('   - First Schedule Route UUID: ${_vehicleResponse!.content!.schedules.first.route.uuid}');
        }
      }
      
      // Update available routes with any vehicle-specific routes from the engagement response
      if (_vehicleResponse?.content?.schedules.isNotEmpty == true) {
        final vehicleRoutes = _vehicleResponse!.content!.schedules
            .map((schedule) => schedule.route)
            .toList();
        
        // Merge with existing routes and remove duplicates
        final allRoutes = <RouteInfo>[..._availableRoutes];
        for (var route in vehicleRoutes) {
          if (!allRoutes.any((existing) => existing.uuid == route.uuid)) {
            allRoutes.add(route);
          }
        }
        
        setState(() {
          _availableRoutes = allRoutes;
          // Auto-select the first vehicle-specific route if available
          if (vehicleRoutes.isNotEmpty) {
            _selectedRoute = vehicleRoutes.first.uuid;
          }
        });
      }
      
      setState(() {
        _isEngagingVehicle = false;
        _showStartTripDialog = true;
      });
      
      _showStartTripModal();
      
    } catch (e) {
      setState(() {
        _isEngagingVehicle = false;
      });
      
      print('❌ Vehicle engagement failed: $e');
      
      // Show error dialog
      _showErrorDialog('Vehicle Engagement Failed', 
          e is VehicleEngagementException ? e.message : 'Failed to engage vehicle: $e');
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (message.contains('not authenticated') || message.contains('Username could not be found'))
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Go back to dashboard
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: const Text('Login'),
            )
          else
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Resume camera for next scan
                controller?.resumeCamera();
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleFlash() async {
    try {
      await controller?.toggleFlash();
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      print('Flash toggle error: $e');
    }
  }

  Future<void> _toggleCamera() async {
    try {
      await controller?.flipCamera();
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    } catch (e) {
      print('Camera toggle error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking permissions
    if (!_permissionsChecked) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
              ),
              SizedBox(height: 20),
              Text(
                'Checking Permissions...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show permission required screen
    if (!_hasLocationPermission || !_hasCameraPermission) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                !_hasLocationPermission ? Icons.location_off : Icons.camera_alt_outlined,
                color: Colors.white,
                size: 80,
              ),
              const SizedBox(height: 20),
              Text(
                !_hasLocationPermission 
                    ? 'Location Permission Required'
                    : 'Camera Permission Required',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                !_hasLocationPermission
                    ? 'Location access is required for trip tracking'
                    : 'Camera access is required to scan QR codes',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (!_hasLocationPermission) {
                    await _requestLocationPermission();
                  } else if (!_hasCameraPermission) {
                    await _requestCameraPermission();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  !_hasLocationPermission ? 'Grant Location Access' : 'Grant Camera Access',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Main QR Scanner Interface
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // QR Scanner View
          QRView(
            key: qrKey,
            onQRViewCreated: _onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: Colors.red,
              borderRadius: 10,
              borderLength: 30,
              borderWidth: 10,
              cutOutSize: 250,
            ),
            cameraFacing: _isFrontCamera ? CameraFacing.front : CameraFacing.back,
          ),
          
          // Loading overlay when engaging vehicle
          if (_isEngagingVehicle)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.cyan,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Engaging Vehicle...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Top controls
          SafeArea(
            child: Column(
              children: [
                // Header with close and flash buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleFlash,
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isFlashOn ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Title and subtitle
                const Text(
                  'Scan QR Code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Scan the vehicle QR code to start the trip',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          
          // Camera toggle button at bottom center
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Back Camera Button
                    GestureDetector(
                      onTap: () {
                        if (_isFrontCamera) {
                          _toggleCamera();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isFrontCamera ? Colors.blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'Back Camera',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: !_isFrontCamera ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    // Front Camera Button
                    GestureDetector(
                      onTap: () {
                        if (!_isFrontCamera) {
                          _toggleCamera();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: _isFrontCamera ? Colors.blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'Front Camera',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: _isFrontCamera ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStartTripModal() {
    print('🔍 Showing start trip modal');
    print('   - Available routes: ${_availableRoutes.length}');
    print('   - Selected route: $_selectedRoute');
    print('   - Is loading routes: $_isLoadingRoutes');
    for (var route in _availableRoutes) {
      print('   - Route: ${route.routeName} (${route.uuid})');
    }
    
    // Ensure selected route is valid or reset to first available
    if (_availableRoutes.isNotEmpty) {
      final validRouteUuids = _getUniqueRoutes().map((r) => r.uuid).toList();
      if (_selectedRoute == null || !validRouteUuids.contains(_selectedRoute)) {
        setState(() {
          _selectedRoute = validRouteUuids.first;
        });
        print('🔄 Reset selected route to: $_selectedRoute');
      }
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              const Text(
                'Start Trip',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              // Speedometer image
              Container(
                height: 150, // Reduced from 200 to 150
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/speedometer.png',
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
              const SizedBox(height: 15), // Reduced from 20
              
              // Vehicle Details
              if (_vehicleResponse?.content?.vehicle != null) ...[
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vehicle: ${_vehicleResponse!.content!.vehicle.vehicleNo}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyan,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'UUID: ${_vehicleResponse!.content!.vehicle.vehicleUuid}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        'Device IMEI: ${_vehicleResponse!.content!.vehicle.activeDeviceImei}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      if (_vehicleResponse!.content!.schedules.isNotEmpty) ...[
                        const Text(
                          'Active Schedule:',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Route: ${_vehicleResponse!.content!.schedules.first.route.routeName}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          'From: ${_vehicleResponse!.content!.schedules.first.route.startPoint.name}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          'To: ${_vehicleResponse!.content!.schedules.first.route.endPoint.name}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              
              // Odometer reading
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Odometer Reading',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _odometerController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '100000',
                      hintStyle: TextStyle(
                        color: Colors.grey[400], // Light placeholder text color
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.cyan),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.cyan, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              // Route Selection Dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Route',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      if (_selectedRoute != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Colors.cyan, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Selected',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.cyan.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.cyan),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isLoadingRoutes
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('Loading routes...'),
                              ],
                            ),
                          )
                        : _availableRoutes.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'No routes available. You can continue without selecting a route.',
                                        style: TextStyle(color: Colors.orange, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : DropdownButton<String>(
                            value: _selectedRoute,
                            isExpanded: true,
                            underline: Container(),
                            hint: const Text('Select a route'),
                            items: _getUniqueRoutes().map((RouteInfo route) {
                              final isSelected = route.uuid == _selectedRoute;
                              return DropdownMenuItem<String>(
                                value: route.uuid,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            route.routeName,
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: isSelected ? Colors.cyan : Colors.black,
                                            ),
                                          ),
                                          Text(
                                            '${route.startPoint.name} → ${route.endPoint.name}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSelected ? Colors.cyan.shade300 : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.cyan,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setDialogState(() {
                                _selectedRoute = newValue;
                              });
                              setState(() {
                                _selectedRoute = newValue;
                              });
                              print('🔄 Route changed to: $newValue');
                            },
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _showStartTripDialog = false;
                        });
                        // Resume camera
                        controller?.resumeCamera();
                      },
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
                      onPressed: () async {
                        // Validate inputs
                        if (_odometerController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter odometer reading'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        if (_selectedRoute == null && _availableRoutes.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select a route'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        // Show loading indicator
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Dialog(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 16),
                                  Text('Starting trip...'),
                                ],
                              ),
                            ),
                          ),
                        );

                        try {
                          // Critical Debug: Check what we actually have in _vehicleResponse
                          print('🔍 CRITICAL DEBUG - Vehicle Response State:');
                          print('   - _vehicleResponse == null: ${_vehicleResponse == null}');
                          if (_vehicleResponse != null) {
                            print('   - _vehicleResponse.content == null: ${_vehicleResponse!.content == null}');
                            if (_vehicleResponse!.content != null) {
                              print('   - vehicle object: ${_vehicleResponse!.content!.vehicle}');
                              print('   - schedules list: ${_vehicleResponse!.content!.schedules}');
                              print('   - schedules length: ${_vehicleResponse!.content!.schedules.length}');
                            }
                          }
                          
                          // Debug: Log trip start parameters
                          print('🚀 Starting trip with parameters:');
                          print('   - Vehicle: ${_vehicleResponse?.content?.vehicle.vehicleNo ?? result?.code ?? 'Unknown'}');
                          print('   - Vehicle UUID: ${_vehicleResponse?.content?.vehicle.vehicleUuid ?? 'N/A'}');
                          print('   - Route UUID: ${_selectedRoute ?? 'N/A'}');
                          print('   - Odometer: ${_odometerController.text.trim()}');
                          print('   - Schedule UUID: ${_vehicleResponse?.content?.schedules.first.uuid ?? 'N/A'}');
                          
                          // First check if there's already an active trip locally
                          print('🔍 Checking for existing local active trip...');
                          final existingTrip = await _vehicleService.getLocalActiveTrip();
                          
                          if (existingTrip != null) {
                            print('✅ Found existing local engagement/trip: ${existingTrip.vehicleNumber}');
                            print('🔍 Trip started status: ${existingTrip.isTripStarted}');
                            
                            // If the trip is already started (not just engaged), navigate to trip screen
                            if (existingTrip.isTripStarted) {
                              print('✅ Trip already started, navigating to trip screen');
                              // Close loading dialog
                              Navigator.of(context).pop();
                              
                              // Close start trip dialog
                              Navigator.pop(context);
                              
                              // Navigate directly to trip screen with existing active trip
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TripScreen(
                                    vehicleNumber: existingTrip.vehicleNumber,
                                    odometerReading: existingTrip.startOdometer.toString(),
                                  ),
                                ),
                              );
                              return;
                            } else {
                              print('ℹ️ Vehicle is engaged but trip not started yet, proceeding with trip initiation...');
                              // Continue to the trip initiation code below
                            }
                          }

                          // No active trip found OR vehicle is only engaged, proceed with trip initiation API call
                          final tripResponse = await _vehicleService.startTrip(
                            vehicleNumber: _vehicleResponse?.content?.vehicle.vehicleNo ?? result?.code ?? 'Unknown',
                            vehicleUuid: _vehicleResponse?.content?.vehicle.vehicleUuid ?? '',
                            routeUuid: _selectedRoute ?? '',
                            odometerReading: _odometerController.text.trim(),
                            scheduleUuid: _vehicleResponse?.content?.schedules.first.uuid ?? '',
                          );

                          // Close loading dialog
                          Navigator.of(context).pop();

                          if (tripResponse.isSuccess) {
                            // Close start trip dialog
                            Navigator.pop(context);
                            
                            // Navigate to trip screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TripScreen(
                                  vehicleNumber: _vehicleResponse?.content?.vehicle.vehicleNo ?? result?.code ?? 'Unknown',
                                  odometerReading: _odometerController.text,
                                ),
                              ),
                            );
                          } else {
                            // Show error message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to start trip: ${tripResponse.message}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          // Close loading dialog
                          Navigator.of(context).pop();
                          
                          // Show error message
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error starting trip: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Start Trip',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../../core/services/locator.dart';
import '../../core/services/vehicle_service.dart';

// Main screen that shows the Mark Drop Point confirmation
class MarkDropScreen extends StatefulWidget {
  const MarkDropScreen({super.key});

  @override
  _MarkDropScreenState createState() => _MarkDropScreenState();
}

class _MarkDropScreenState extends State<MarkDropScreen> {
  bool showDropPointPopup = false;
  late final VehicleService _vehicleService;

  @override
  void initState() {
    super.initState();
    _vehicleService = locator<VehicleService>();
    // Automatically show the drop point popup when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        showDropPointPopup = true;
      });
    });
  }

  Future<void> _addDropPoint() async {
    try {
      print('📍 UI: Starting drop point addition from MarkDropScreen...');
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Adding drop point...'),
            ],
          ),
        ),
      );
      
      // Call the vehicle service to add drop point
      await _vehicleService.addDropPoint();
      
      // Close loading dialog
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (navError) {
          print('⚠️ Could not close loading dialog: $navError');
        }
      }
      
      // Show success message and close the screen
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Drop point added successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          // Navigate back to the trip screen after successful drop point addition
          Navigator.of(context).pop();
        } catch (e) {
          print('⚠️ Could not show success message: $e');
        }
      }
      
      print('✅ UI: Drop point added successfully from MarkDropScreen');
      
    } catch (e) {
      print('❌ UI: Error adding drop point from MarkDropScreen: $e');
      
      // Close loading dialog if open
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (navError) {
          print('⚠️ Could not close loading dialog: $navError');
        }
      }
      
      // Show specific error message
      if (mounted) {
        try {
          String errorMessage = 'Failed to add drop point';
          if (e.toString().contains('No active trip found')) {
            errorMessage = 'No active trip found. Please start a trip first.';
          } else if (e.toString().contains('Trip must be started')) {
            errorMessage = 'Please start your trip before adding drop points.';
          } else if (e.toString().contains('location')) {
            errorMessage = 'Unable to get location. Please check GPS permissions.';
          } else if (e.toString().contains('API Error')) {
            errorMessage = 'Server error. Please try again later.';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        } catch (e) {
          print('⚠️ Could not show error message: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // App Title and Home Icon
                      Row(
                        children: [
                          const Text(
                            'DRIVE',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'MASTER',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[400],
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.home,
                            color: Colors.white,
                            size: 24,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Vehicle Number
                      Text(
                        'Vehicle Number : LIE-8514',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.red[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Pause Button
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.grey[600]!, Colors.grey[800]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.orange,
                        width: 3,
                      ),
                      color: const Color(0xFF2A2A2A),
                    ),
                    child: const Center(
                      child: Text(
                        'PAUSE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Status indicators
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatusIndicator('Doors open', true),
                      _buildStatusIndicator('Cabin Temp', false),
                      _buildStatusIndicator('Seat Belts', false),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // End Trip Button
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      // Handle end trip
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'End Trip',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
          
          // Drop Point Popup Overlay
          if (showDropPointPopup)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: MakeDropPointPopup(
                  onCancel: () {
                    setState(() {
                      showDropPointPopup = false;
                    });
                    // Navigate back to previous screen when cancelled
                    Navigator.of(context).pop();
                  },
                  onConfirm: () async {
                    setState(() {
                      showDropPointPopup = false;
                    });
                    // Call the actual drop point API
                    await _addDropPoint();
                  },
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            showDropPointPopup = true;
          });
        },
        backgroundColor: Colors.blue[600],
        child: const Icon(Icons.add_location, color: Colors.white),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.green : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// Make Drop Point Popup Component
class MakeDropPointPopup extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const MakeDropPointPopup({
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
          // Title
          const Text(
            'Make Drop Point',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          
          const SizedBox(height: 15),
          
          // Message
          const Text(
            'Please confirm your drop point!',
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
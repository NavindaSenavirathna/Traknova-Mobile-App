import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/locator.dart';
import '../../core/services/vehicle_service.dart';

class FillingInformationScreen extends StatefulWidget {
  const FillingInformationScreen({super.key});

  @override
  _FillingInformationScreenState createState() => _FillingInformationScreenState();
}

class _FillingInformationScreenState extends State<FillingInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fillingStationController = TextEditingController();
  final _odometerController = TextEditingController();
  final _literCountController = TextEditingController();
  final _literPriceController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();
  String selectedFuelType = 'petrol'; // Default fuel type
  bool _isSubmitting = false;

  late final VehicleService _vehicleService;

  @override
  void initState() {
    super.initState();
    _vehicleService = locator<VehicleService>();
    
    // Auto-calculate total when quantity or unit price changes
    _literCountController.addListener(_calculateTotal);
    _literPriceController.addListener(_calculateTotal);
  }

  @override
  void dispose() {
    _fillingStationController.dispose();
    _odometerController.dispose();
    _literCountController.dispose();
    _literPriceController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _calculateTotal() {
    final quantity = double.tryParse(_literCountController.text) ?? 0.0;
    final unitPrice = double.tryParse(_literPriceController.text) ?? 0.0;
    final total = quantity * unitPrice;
    _amountController.text = total.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.5),
      body: Stack(
        children: [
          // Dark background
          Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFF1A1A1A),
            child: SafeArea(
              child: Column(
                children: [
                  // Header with Vehicle Number
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // App Title
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
                  
                  const Spacer(),
                  
                  // Bottom logout section
                  Container(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.logout,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Session',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Modal popup
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modal content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            const Text(
                              'Filling Details',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            
                            const SizedBox(height: 30),
                            
                            // Form Fields
                            _buildFormField(
                              'Filling Station Name',
                              _fillingStationController,
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              'Odometer Reading',
                              _odometerController,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              'Liter Count',
                              _literCountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                            const SizedBox(height: 16),
                            _buildFuelTypeDropdown(),
                            const SizedBox(height: 16),
                            _buildFormField(
                              'Liter Price (LKR)',
                              _literPriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              'Amount (LKR)',
                              _amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              'Note',
                              _noteController,
                              maxLines: 3,
                            ),
                            
                            const SizedBox(height: 30),
                            
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey[500],
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(25),
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
                                const SizedBox(width: 16),
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _isSubmitting ? null : _submitForm,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSubmitting ? Colors.grey : Colors.blue[600],
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isSubmitting 
                                        ? const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                height: 16,
                                                width: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Submitting...',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            'Submit',
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Container(
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(
            color: Colors.grey[500],
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide(color: Colors.blue[600]!, width: 1),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: maxLines > 1 ? 15 : 15,
          ),
        ),
        validator: (value) {
          if (label.toLowerCase().contains('note')) return null;
          if (value == null || value.isEmpty) {
            return 'Please enter $label';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildFuelTypeDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(25),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DropdownButtonFormField<String>(
        value: selectedFuelType,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Fuel Type',
        ),
        items: const [
          DropdownMenuItem(value: 'petrol', child: Text('Petrol')),
          DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
        ],
        onChanged: (String? value) {
          if (value != null) {
            setState(() {
              selectedFuelType = value;
            });
          }
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select fuel type';
          }
          return null;
        },
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      print('⛽ UI: Starting fuel entry submission...');
      
      // Get active trip to get vehicle UUID
      final activeTrip = await _vehicleService.getLocalActiveTrip();
      if (activeTrip == null) {
        throw Exception('No active vehicle found. Please engage a vehicle first.');
      }

      // Parse form values
      final quantity = double.parse(_literCountController.text);
      final unitPrice = double.parse(_literPriceController.text);
      final totalAmount = double.parse(_amountController.text);
      final odometerReading = double.parse(_odometerController.text);
      final fuelStationName = _fillingStationController.text.trim();
      final remarks = _noteController.text.trim();

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Submitting fuel entry...'),
            ],
          ),
        ),
      );

      // Submit fuel entry
      await _vehicleService.addFuelEntry(
        vehicleUuid: activeTrip.vehicleUuid,
        quantity: quantity,
        fuelType: selectedFuelType,
        unitPrice: unitPrice,
        totalAmount: totalAmount,
        odometerReading: odometerReading,
        fuelStationName: fuelStationName,
        remarks: remarks.isNotEmpty ? remarks : null,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Success'),
              content: const Text('Fuel entry has been submitted successfully!'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close success dialog
                    Navigator.of(context).pop(); // Close fuel entry screen
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }

      print('✅ UI: Fuel entry submitted successfully');

    } catch (e) {
      print('❌ UI: Error submitting fuel entry: $e');
      
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
        String errorMessage = 'Failed to submit fuel entry';
        String actionText = 'OK';
        
        if (e.toString().contains('No active vehicle')) {
          errorMessage = 'No active vehicle found. Please engage a vehicle first.';
        } else if (e.toString().contains('Location services are disabled')) {
          errorMessage = 'GPS is disabled on your device.\n\nPlease enable Location Services in your device settings and try again.';
          actionText = 'Settings';
        } else if (e.toString().contains('Location permission denied')) {
          errorMessage = 'Location permission is required to record fuel entries.\n\nPlease grant location access in app settings and try again.';
          actionText = 'Settings';
        } else if (e.toString().contains('Location permission permanently denied')) {
          errorMessage = 'Location access is permanently denied.\n\nPlease enable location permission in device settings:\nSettings > Apps > Drive Master > Permissions > Location';
          actionText = 'Settings';
        } else if (e.toString().contains('Location request timed out')) {
          errorMessage = 'GPS signal is weak or unavailable.\n\nPlease ensure you are outdoors or near a window and try again.';
          actionText = 'Retry';
        } else if (e.toString().contains('location') || e.toString().contains('GPS')) {
          errorMessage = 'Unable to get your current location.\n\nPlease check that GPS is enabled and location permissions are granted.';
        } else if (e.toString().contains('vehicle not found')) {
          errorMessage = 'Vehicle not found. Please ensure vehicle is properly engaged.';
        } else if (e.toString().contains('API Error')) {
          errorMessage = 'Server error. Please try again later.';
        }
        
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Location Required'),
              content: Text(errorMessage),
              actions: [
                if (actionText == 'Settings') ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      // Open app settings for location permissions
                      await openAppSettings();
                    },
                    child: Text(actionText),
                  ),
                ] else if (actionText == 'Retry') ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Retry the form submission
                      _submitForm();
                    },
                    child: const Text('Retry'),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ],
            );
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}
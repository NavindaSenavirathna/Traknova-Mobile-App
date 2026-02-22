# RabbitMQ/AMQ Integration Guide

## Overview
The AMQ (Advanced Message Queuing) integration provides real-time vehicle sensor data streaming using RabbitMQ and STOMP protocol. This enables live monitoring of vehicle status during trips.

## How It Works

### 1. Automatic Connection
When a trip is initiated via `startTrip()`, the system:
- Extracts `liveAmq` configuration from the trip initiate API response
- Automatically establishes STOMP connection to RabbitMQ
- Subscribes to the vehicle's sensor data topic
- Sends initial "TRIP_STARTED" status

### 2. Real-time Data Streaming
The AMQ service receives structured sensor data including:
- **Location**: GPS coordinates with latitude/longitude
- **Temperature**: Cabin temperature in Celsius  
- **Door Status**: Individual door open/closed states
- **Seat Belt Status**: Individual seat belt fastened states
- **Speed**: Current vehicle speed
- **Engine Status**: Engine on/off and RPM

### 3. Automatic Disconnection
When trip ends via `endTrip()` or `releaseVehicle()`:
- Sends "TRIP_ENDED" status to RabbitMQ
- Closes STOMP connection
- Cleans up resources

## API Response Structure

The trip initiate API response should contain:
```json
{
  "status": 200,
  "result": {
    "status": true,
    "content": {
      "tripUuid": "TRIP_ABC123",
      "liveAmq": {
        "host": "rabbitmq.example.com",
        "port": 15674,
        "username": "vehicle_user", 
        "password": "secure_password",
        "exchange": "vehicle_exchange",
        "topic": "vehicle.sensor.VEHICLE_ABC123"
      }
    }
  }
}
```

## Data Models

### AmqConfig
```dart
class AmqConfig {
  final String host;        // RabbitMQ host
  final int port;           // WebSocket port (usually 15674)
  final String username;    // Authentication username
  final String password;    // Authentication password
  final String exchange;    // Exchange name
  final String topic;       // Topic pattern (e.g., vehicle.sensor.{vehicleId})
}
```

### VehicleSensorData
```dart
class VehicleSensorData {
  final String? vehicleId;
  final DateTime timestamp;
  final LocationData? location;
  final double? temperature;
  final double? speed;
  final DoorStatus? doors;
  final SeatBeltStatus? seatBelts;
  final bool? engineOn;
  final double? rpm;
}
```

## Usage Examples

### 1. Accessing AMQ Service from UI
```dart
// Get the AMQ service instance
final amqService = vehicleService.amqService;

// Check connection status
if (amqService.isConnected) {
  print('AMQ connected to: ${amqService.currentConfig?.host}');
}

// Listen to real-time sensor data
amqService.sensorDataStream.listen((sensorData) {
  // Update UI with real-time data
  if (sensorData.location != null) {
    updateMapPosition(sensorData.location!);
  }
  
  if (sensorData.temperature != null) {
    updateTemperatureDisplay(sensorData.temperature!);
  }
  
  if (sensorData.doors != null && sensorData.doors!.anyOpen) {
    showDoorOpenWarning();
  }
});
```

### 2. Sending Driver Status Updates
```dart
// Send custom driver status
await amqService.sendDriverStatus('BREAK_START', {
  'location': 'Rest Area A1',
  'duration_minutes': 30
});

// Send location data (if bidirectional communication needed)
// Get live location from device
final position = await Geolocator.getCurrentPosition();
await amqService.sendLocationData({
  'latitude': position.latitude,
  'longitude': position.longitude,
  'speed': position.speed, // Actual GPS speed in m/s
  'timestamp': DateTime.now().toUtc().toIso8601String()
});
```

### 3. Dashboard Integration Example
```dart
class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription? _sensorSubscription;
  VehicleSensorData? _latestSensorData;

  @override
  void initState() {
    super.initState();
    _setupAmqListener();
  }

  void _setupAmqListener() {
    final vehicleService = locator<VehicleService>();
    
    _sensorSubscription = vehicleService.amqService.sensorDataStream.listen(
      (sensorData) {
        setState(() {
          _latestSensorData = sensorData;
        });
      },
      onError: (error) {
        print('AMQ stream error: $error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Temperature widget
          if (_latestSensorData?.temperature != null)
            TemperatureWidget(temperature: _latestSensorData!.temperature!),
          
          // Door status widget  
          if (_latestSensorData?.doors != null)
            DoorStatusWidget(doors: _latestSensorData!.doors!),
          
          // Location map widget
          if (_latestSensorData?.location != null)
            MapWidget(location: _latestSensorData!.location!),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    super.dispose();
  }
}
```

## Error Handling

The AMQ integration is designed to be fault-tolerant:

1. **Connection Failures**: If AMQ connection fails, the trip continues normally
2. **Missing Config**: If `liveAmq` is not in the API response, AMQ is skipped  
3. **Network Issues**: Connection drops are logged but don't affect the trip
4. **Data Parsing**: Invalid sensor data is logged and skipped

## Logging

The AMQ service provides comprehensive logging:
- 🐰 Connection status and configuration
- 📡 Topic subscription confirmations
- 📨 Incoming message processing
- 📊 Parsed sensor data details
- ❌ Error conditions and recovery

## Configuration Notes

1. **WebSocket Port**: Usually 15674 for RabbitMQ WebSocket plugin
2. **Topic Pattern**: Should be unique per vehicle (e.g., `vehicle.sensor.{vehicleId}`)
3. **Credentials**: Should be scoped to specific vehicle/driver permissions
4. **Connection Timeout**: Set to 30 seconds with heartbeat every 20 seconds

## Integration Benefits

✅ **Real-time Monitoring**: Live vehicle sensor data  
✅ **Automatic Lifecycle**: Connects/disconnects with trip lifecycle  
✅ **Fault Tolerant**: Continues operation even if AMQ fails  
✅ **Structured Data**: Type-safe models for all sensor data  
✅ **Bidirectional**: Can send driver status back to server  
✅ **Scalable**: RabbitMQ handles multiple concurrent vehicles
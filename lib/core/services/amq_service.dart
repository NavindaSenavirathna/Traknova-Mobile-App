import 'dart:async';
import 'dart:convert';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../models/amq_models.dart';

class AmqService {
  StompClient? _stompClient;
  AmqConfig? _config;
  bool _isConnected = false;
  StreamController<VehicleSensorData>? _sensorDataController;
  StreamController<Map<String, dynamic>>? _rawMessageController;

  /// Stream for processed sensor data
  Stream<VehicleSensorData> get sensorDataStream => 
    _sensorDataController?.stream ?? const Stream.empty();

  /// Stream for raw AMQ messages
  Stream<Map<String, dynamic>> get rawMessageStream => 
    _rawMessageController?.stream ?? const Stream.empty();

  /// Initialize AMQ connection with config from trip initiate response
  Future<bool> initializeConnection(AmqConfig config) async {
    try {
      print('🐰 Initializing RabbitMQ/STOMP connection...');
      print('   - Host: ws://${config.host}:${config.port}');
      print('   - Exchange: ${config.exchange}');
      print('   - Topic: ${config.topic}');
      print('   - Username: ${config.username}');

      _config = config;
      _sensorDataController = StreamController<VehicleSensorData>.broadcast();
      _rawMessageController = StreamController<Map<String, dynamic>>.broadcast();

      // Create STOMP client configuration for RabbitMQ WebSocket
      _stompClient = StompClient(
        config: StompConfig(
          url: 'ws://${config.host}:${config.port}/ws',
          onConnect: _onConnected,
          beforeConnect: () async {
            print('🔄 Connecting to RabbitMQ...');
          },
          onWebSocketError: (dynamic error) {
            print('❌ WebSocket error: $error');
          },
          onStompError: (StompFrame frame) {
            print('❌ STOMP error: ${frame.body}');
          },
          onDisconnect: (StompFrame frame) {
            print('🔌 Disconnected from RabbitMQ');
            _isConnected = false;
          },
          heartbeatIncoming: const Duration(seconds: 20),
          heartbeatOutgoing: const Duration(seconds: 20),
          connectionTimeout: const Duration(seconds: 30),
          stompConnectHeaders: {
            'login': config.username,
            'passcode': config.password,
            // 'host' in STOMP CONNECT = RabbitMQ virtual host, NOT the server IP.
            // Sending the server IP here causes: "Virtual host '<IP>' access denied".
            'host': config.virtualHost,
          },
        ),
      );

      // Activate connection
      _stompClient!.activate();

      // Wait for connection with timeout
      int attempts = 0;
      while (!_isConnected && attempts < 30) {
        await Future.delayed(const Duration(seconds: 1));
        attempts++;
      }

      if (_isConnected) {
        print('✅ RabbitMQ connection established successfully');
        return true;
      } else {
        print('❌ RabbitMQ connection timeout');
        return false;
      }
      
    } catch (e) {
      print('❌ Failed to initialize RabbitMQ connection: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Called when STOMP connection is established
  void _onConnected(StompFrame frame) {
    print('✅ STOMP connected to RabbitMQ');
    _isConnected = true;

    if (_config != null) {
      // Subscribe to the vehicle's topic for receiving real-time data
      final destination = '/topic/${_config!.topic}';
      
      print('📡 Subscribing to topic: $destination');
      
      _stompClient!.subscribe(
        destination: destination,
        callback: _onMessageReceived,
        headers: {
          'id': 'vehicle-data-${DateTime.now().millisecondsSinceEpoch}',
          'ack': 'auto',
        },
      );
      
      print('✅ Subscribed to vehicle data topic');
    }
  }

  /// Handle incoming messages from RabbitMQ
  void _onMessageReceived(StompFrame frame) {
    try {
      if (frame.body == null) {
        print('⚠️ Received empty message body');
        return;
      }

      final messageData = json.decode(frame.body!);
      print('📨 Received AMQ message: $messageData');

      // Emit raw message
      _rawMessageController?.add(messageData);

      // Process and emit structured sensor data
      final sensorData = VehicleSensorData.fromJson(messageData);
      _sensorDataController?.add(sensorData);

      print('📊 Processed sensor data:');
      if (sensorData.location != null) {
        print('   📍 Location: ${sensorData.location!.latitude}, ${sensorData.location!.longitude}');
      }
      if (sensorData.temperature != null) {
        print('   🌡️ Temperature: ${sensorData.temperature}°C');
      }
      if (sensorData.doors != null) {
        print('   🚪 Doors open: ${sensorData.doors!.anyOpen}');
      }
      if (sensorData.seatBelts != null) {
        print('   🔒 Seat belts fastened: ${sensorData.seatBelts!.allFastened}');
      }
      
    } catch (e) {
      print('❌ Error processing AMQ message: $e');
      print('   Raw message: ${frame.body}');
    }
  }

  /// Send location data to AMQ topic (if needed for bidirectional communication)
  Future<bool> sendLocationData(Map<String, dynamic> locationData) async {
    try {
      if (!_isConnected || _stompClient == null || _config == null) {
        print('❌ AMQ not connected - cannot send location data');
        return false;
      }

      final destination = '/topic/${_config!.topic}_response';
      final message = json.encode(locationData);
      
      _stompClient!.send(
        destination: destination,
        body: message,
        headers: {
          'content-type': 'application/json',
          'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      print('📤 Location data sent to AMQ: $locationData');
      return true;
      
    } catch (e) {
      print('❌ Failed to send location data to AMQ: $e');
      return false;
    }
  }

  /// Send driver acknowledgment or status update
  Future<bool> sendDriverStatus(String status, Map<String, dynamic>? data) async {
    try {
      if (!_isConnected || _stompClient == null || _config == null) {
        print('❌ AMQ not connected - cannot send driver status');
        return false;
      }

      final statusData = {
        'status': status,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'deviceId': _config!.topic.split('.').last, // Extract device ID from topic
        'data': data ?? {},
      };

      final destination = '/topic/${_config!.topic}_driver_status';
      final message = json.encode(statusData);
      
      _stompClient!.send(
        destination: destination,
        body: message,
        headers: {
          'content-type': 'application/json',
        },
      );

      print('📤 Driver status sent: $status');
      return true;
      
    } catch (e) {
      print('❌ Failed to send driver status: $e');
      return false;
    }
  }

  /// Close AMQ connection
  Future<void> closeConnection() async {
    try {
      print('🔌 Closing RabbitMQ connection...');
      
      await _sensorDataController?.close();
      await _rawMessageController?.close();
      
      _stompClient?.deactivate();
      
      _isConnected = false;
      _config = null;
      
      print('✅ RabbitMQ connection closed');
    } catch (e) {
      print('❌ Error closing RabbitMQ connection: $e');
    }
  }

  /// Check if AMQ is connected
  bool get isConnected => _isConnected;

  /// Get current AMQ configuration
  AmqConfig? get currentConfig => _config;
}
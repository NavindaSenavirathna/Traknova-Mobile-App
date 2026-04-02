import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';

class ApiService {
  static const String baseUrl = 'https://app.traknova.co.uk';
  final AuthService _authService;

  ApiService(this._authService);

  // Make authenticated GET request
  Future<http.Response> get(String endpoint) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    final response = await http.get(uri, headers: headers)
        .timeout(const Duration(seconds: 60));
    print('🌐 API GET to: $uri');
    print('📤 Headers: ${headers.keys.join(', ')}');
    print('🔐 Has X-FMS-EXT-TOKEN: ${headers.containsKey('X-FMS-EXT-TOKEN')}');
    if (headers.containsKey('X-FMS-EXT-TOKEN')) {
      final token = headers['X-FMS-EXT-TOKEN']!;
      print('🔐 Token (FULL): $token');
    }
    return response;
  }

  // Make authenticated POST request
  Future<http.Response> post(String endpoint, {Map<String, dynamic>? body}) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    print('🌐 API POST to: $uri');
    print('📤 Headers: ${headers.keys.join(', ')}');
    print('🔐 Has X-FMS-EXT-TOKEN: ${headers.containsKey('X-FMS-EXT-TOKEN')}');
    if (headers.containsKey('X-FMS-EXT-TOKEN')) {
      final token = headers['X-FMS-EXT-TOKEN']!;
      print('🔐 Token (FULL): $token');
    }
    
    return await http.post(
      uri, 
      headers: headers,
      body: body != null ? json.encode(body) : null,
    ).timeout(const Duration(seconds: 30));
  }

  // Make authenticated PUT request
  Future<http.Response> put(String endpoint, {Map<String, dynamic>? body}) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    return await http.put(
      uri,
      headers: headers,
      body: body != null ? json.encode(body) : null,
    ).timeout(const Duration(seconds: 30));
  }

  // Make authenticated DELETE request
  Future<http.Response> delete(String endpoint) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    return await http.delete(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
  }
}
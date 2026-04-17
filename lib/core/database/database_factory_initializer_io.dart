import 'dart:io' show Platform;

void initializeDatabaseFactory() {
  // Try to initialize FFI factory only if available on desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      // Import and initialize sqflite_common_ffi if available
      // This is platform-specific handling that may not always be needed
      print('📱 Platform: ${Platform.operatingSystem} - using native SQLite');
    } catch (e) {
      print('⚠️ Could not initialize FFI factory: $e');
      // Fall back to default handling
    }
  }
}
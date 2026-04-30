import 'package:get_it/get_it.dart';
import '../../features/auth/auth_view_model.dart';
import 'auth_service.dart';
import 'api_service.dart';
import 'vehicle_service.dart';
import 'trip_persistence_service.dart';
import 'trip_tracking_service.dart';
import 'auth_persistence_service.dart';
import 'live_location_service.dart';
import 'tcp_tracker_service.dart';
import 'device_data_service.dart';
import 'mqtt_live_service.dart';
import 'geofence_api_service.dart';
import 'geofence_notification_service.dart';

final GetIt locator = GetIt.instance;

void setupLocator() {
  // Register services
  locator.registerLazySingleton(() => AuthPersistenceService());
  locator.registerLazySingleton(() => AuthService());
  locator.registerLazySingleton(() => ApiService(locator<AuthService>()));
  locator.registerLazySingleton(() => TripPersistenceService());
  locator.registerLazySingleton(() => TripTrackingService());
  locator.registerLazySingleton(() => VehicleService(
    locator<ApiService>(),
    locator<TripPersistenceService>(),
    locator<TripTrackingService>(),
  ));
  
  // GPS / TCP tracker services
  locator.registerLazySingleton(() => LiveLocationService());
  locator.registerLazySingleton(() => TcpTrackerService());

  // MQTT live tracking services
  locator.registerLazySingleton(() => DeviceDataService());
  locator.registerLazySingleton(() => MqttLiveService());

  // GeoFence services
  locator.registerLazySingleton(() => GeoFenceApiService());
  locator.registerLazySingleton(() => GeoFenceNotificationService());

  // Register view models as singletons so they maintain state
  locator.registerLazySingleton(() => AuthViewModel(locator<AuthService>()));
}
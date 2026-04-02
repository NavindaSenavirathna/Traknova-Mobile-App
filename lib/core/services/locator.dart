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

  // Register view models as singletons so they maintain state
  locator.registerLazySingleton(() => AuthViewModel(locator<AuthService>()));
}
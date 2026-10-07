import 'package:connectivity_plus/connectivity_plus.dart';

/// Optional cloud backend integration (Firebase / Cloud Firestore).
/// Every method is wrapped so a failure never throws back into the
/// trigger flow — the core SMS alert must work even if this entire
/// class fails or Firebase is never configured.
class BackendService {
  Future<bool> hasInternetConnection() async {
    final result = await Connectivity().checkConnectivity();
    return result.isNotEmpty && !result.contains(ConnectivityResult.none);
  }

  Future<String?> createIncident({
    required String userId,
    required String triggerType,
    required double latitude,
    required double longitude,
  }) async {
    try {
      // Uncomment once Firebase is configured (see backend_service.dart
      // comments in the project README for the flutterfire setup steps).
      // ignore: avoid_print
      print('[BackendService] Stub: would create incident at $latitude,$longitude');
      return 'stub_incident_id';
    } catch (e) {
      // ignore: avoid_print
      print('[BackendService] Failed to create incident (non-fatal): $e');
      return null;
    }
  }

  Future<void> addLocationUpdate({
    required String incidentId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      // ignore: avoid_print
      print('[BackendService] Stub: would log location update for $incidentId');
    } catch (e) {
      // ignore: avoid_print
      print('[BackendService] Failed to log location update (non-fatal): $e');
    }
  }
}

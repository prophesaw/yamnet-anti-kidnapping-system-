import 'dart:async';
import '../models/app_settings.dart';
import '../models/emergency_contact.dart';
import 'audio_trigger_service.dart';
import 'location_service.dart';
import 'sms_service.dart';
import 'backend_service.dart';
import 'storage_service.dart';

enum IncidentPhase { idle, monitoring, cancellationWindow, alertSent }

/// Orchestrates the full incident lifecycle: audio monitoring -> trigger
/// -> cancellation window -> [cancelled: resume] / [expired: alert] ->
/// SMS -> optional backend log -> periodic location loop.
class IncidentController {
  final AudioTriggerService audioService;
  final LocationService locationService;
  final SmsService smsService;
  final BackendService backendService;
  final StorageService storageService;

  IncidentController({
    required this.audioService,
    required this.locationService,
    required this.smsService,
    required this.backendService,
    required this.storageService,
  });

  IncidentPhase phase = IncidentPhase.idle;
  Timer? _locationLoopTimer;
  String? _currentIncidentId;
  void Function()? _onTriggerFired;

  final _phaseController = StreamController<IncidentPhase>.broadcast();
  Stream<IncidentPhase> get phaseStream => _phaseController.stream;

  void _setPhase(IncidentPhase p) {
    phase = p;
    _phaseController.add(p);
  }

  Future<void> startMonitoring({
    required AppSettings settings,
    required void Function() onTriggerFired,
  }) async {
    _onTriggerFired = onTriggerFired;
    _setPhase(IncidentPhase.monitoring);
    await audioService.startMonitoring(
      confidenceThreshold: settings.triggerConfidenceThreshold,
      onTrigger: () {
        if (phase == IncidentPhase.monitoring) {
          _setPhase(IncidentPhase.cancellationWindow);
          _onTriggerFired?.call();
        }
      },
    );
  }

  Future<void> stopMonitoring() async {
    _locationLoopTimer?.cancel();
    await audioService.stopMonitoring();
    _setPhase(IncidentPhase.idle);
  }

  Future<void> cancelTrigger({required AppSettings settings}) async {
    await audioService.stopMonitoring();
    // Restart through the normal path so every later sound trigger also opens
    // the PIN-protected cancellation dialog.
    await startMonitoring(
      settings: settings,
      onTriggerFired: _onTriggerFired ?? () {},
    );
  }

  Future<void> confirmIncidentAndAlert({
    required List<EmergencyContact> contacts,
    required AppSettings settings,
    String? note,
  }) async {
    final evidencePath = await audioService.stopAndGetEvidencePath();

    final position = await locationService.getCurrentPosition();
    final lat = position?.latitude;
    final lng = position?.longitude;

    await smsService.sendAlertToContacts(
      contacts: contacts,
      latitude: lat,
      longitude: lng,
      note: note,
    );

    _setPhase(IncidentPhase.alertSent);

    final online = await backendService.hasInternetConnection();
    if (online && position != null) {
      _currentIncidentId = await backendService.createIncident(
        userId: 'local_user',
        triggerType: 'sound',
        latitude: lat!,
        longitude: lng!,
      );
    } else if (position != null) {
      await storageService.queueLocationUpdate({
        'latitude': lat,
        'longitude': lng,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    // ignore: avoid_print
    print('Evidence captured at: $evidencePath');

    _startLocationLoop(
      contacts: contacts,
      intervalSeconds: settings.locationUpdateIntervalSeconds,
      durationMinutes: settings.locationUpdateDurationMinutes,
    );
  }

  void _startLocationLoop({
    required List<EmergencyContact> contacts,
    required int intervalSeconds,
    required int durationMinutes,
  }) {
    final endTime = DateTime.now().add(Duration(minutes: durationMinutes));
    _locationLoopTimer =
        Timer.periodic(Duration(seconds: intervalSeconds), (timer) async {
      if (DateTime.now().isAfter(endTime)) {
        timer.cancel();
        return;
      }
      final position = await locationService.getCurrentPosition();
      if (position == null) return;

      // Contacts always receive live updates by SMS. The backend is optional
      // and must never replace the user's emergency notification path.
      await smsService.sendLocationUpdate(
        contacts: contacts,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final online = await backendService.hasInternetConnection();
      if (online && _currentIncidentId != null) {
        await backendService.addLocationUpdate(
          incidentId: _currentIncidentId!,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } else {
        await storageService.queueLocationUpdate({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  void dispose() {
    _locationLoopTimer?.cancel();
    _phaseController.close();
    audioService.dispose();
  }
}

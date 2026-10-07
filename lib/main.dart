import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/audio_trigger_service.dart';
import 'services/location_service.dart';
import 'services/sms_service.dart';
import 'services/backend_service.dart';
import 'services/storage_service.dart';
import 'services/incident_controller.dart';
import 'services/foreground_task_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ForegroundTaskService.initialize();
  await _requestCorePermissions();

  runApp(const AntiKidnapApp());
}

Future<void> _requestCorePermissions() async {
  await [
    Permission.microphone,
    Permission.location,
    Permission.locationAlways,
    Permission.sms,
    Permission.notification,
  ].request();
}

class AntiKidnapApp extends StatelessWidget {
  const AntiKidnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safety Monitor',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const AppRoot(),
    );
  }
}

/// Wires up all services and hands them to HomeScreen. Also preloads the
/// YAMNet model in the background so the first "Start Monitoring" tap
/// isn't slowed down by the model-loading step.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final StorageService _storageService;
  late final AudioTriggerService _audioService;
  late final IncidentController _incidentController;

  @override
  void initState() {
    super.initState();
    _storageService = StorageService();
    _audioService = AudioTriggerService();
    _incidentController = IncidentController(
      audioService: _audioService,
      locationService: LocationService(),
      smsService: SmsService(),
      backendService: BackendService(),
      storageService: _storageService,
    );

    // Preload the YAMNet model in the background (non-blocking). If this
    // fails (e.g. model files weren't added to assets/models/ yet), the
    // error is logged but the app still runs — startMonitoring() will
    // retry loading the model on first use instead.
    _audioService.loadModel().catchError((e) {
      // ignore: avoid_print
      print('YAMNet model failed to preload: $e');
    });
  }

  @override
  void dispose() {
    _incidentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      controller: _incidentController,
      storageService: _storageService,
    );
  }
}

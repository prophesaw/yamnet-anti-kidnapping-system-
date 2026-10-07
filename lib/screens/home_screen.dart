import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_settings.dart';
import '../models/emergency_contact.dart';
import '../services/incident_controller.dart';
import '../services/storage_service.dart';
import '../services/foreground_task_service.dart';
import '../widgets/cancellation_dialog.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  final IncidentController controller;
  final StorageService storageService;

  const HomeScreen({
    super.key,
    required this.controller,
    required this.storageService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _monitoring = false;
  AppSettings _settings = AppSettings();
  List<EmergencyContact> _contacts = [];
  String _debugStatus = 'Not monitoring yet';
  StreamSubscription? _classificationSub;
  Timer? _debugRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final settings = await widget.storageService.loadSettings();
    final contacts = await widget.storageService.loadContacts();
    setState(() {
      _settings = settings;
      _contacts = contacts;
    });
  }

  Future<void> _toggleMonitoring() async {
    if (_monitoring) {
      // Stop everything and cancel live UI updates
      await widget.controller.stopMonitoring();
      await ForegroundTaskService.stop();
      await _classificationSub?.cancel();
      _classificationSub = null;
      _debugRefreshTimer?.cancel();

      setState(() {
        _monitoring = false;
        _debugStatus = 'Not monitoring yet';
      });
      return;
    }

    // Ensure any previous refresh timer is stopped
    _debugRefreshTimer?.cancel();

    if (_contacts.isEmpty) {
      _showSnack(
          'Add at least one emergency contact before enabling monitoring.');
      return;
    }

    try {
      final micStatus = await Permission.microphone.request();
      final locStatus = await Permission.locationAlways.request();
      final notifStatus = await Permission.notification.request();
      final smsStatus = await Permission.sms.request();

      if (!micStatus.isGranted) {
        _showSnack('Microphone permission is required to start monitoring.');
        return;
      }
      if (!locStatus.isGranted) {
        _showSnack(
            'Location "Allow all the time" is required to start monitoring.');
        return;
      }
      if (!notifStatus.isGranted) {
        _showSnack('Notification permission is required to start monitoring.');
        return;
      }
      if (!smsStatus.isGranted) {
        _showSnack('SMS permission is required to send emergency alerts.');
        return;
      }

      await ForegroundTaskService.requestPermissions();
      await ForegroundTaskService.start();

      await widget.controller.startMonitoring(
        settings: _settings,
        onTriggerFired: _showCancellationDialog,
      );

      // Subscribe to live classification updates so the debug text updates
      _classificationSub?.cancel();
      _classificationSub =
          widget.controller.audioService.classificationStream.listen((result) {
        if (!mounted) return;
        setState(() {
          final pct = (result.confidence * 100).toStringAsFixed(0);
          _debugStatus =
              '${result.label} — $pct%${result.isDistress ? "  ⚠️ ABOVE THRESHOLD" : ""}';
        });
      });

      // Periodic UI refresh so the "Bytes received" counter updates even when
      // there are no new classification events.
      _debugRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });

      setState(() => _monitoring = true);
    } catch (e, stack) {
      // Clean up any partial subscriptions/timers on failure
      await _classificationSub?.cancel();
      _classificationSub = null;
      _debugRefreshTimer?.cancel();

      // ignore: avoid_print
      print('START MONITORING FAILED: $e\n$stack');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Failed to start monitoring'),
            content: SingleChildScrollView(child: Text('$e')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showCancellationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CancellationDialog(
        windowSeconds: _settings.cancellationWindowSeconds,
        correctPin: _settings.cancelPin,
        onCancelled: () async {
          await widget.controller.cancelTrigger(settings: _settings);
          _showSnack('Alert cancelled.');
        },
        onExpired: () async {
          await widget.controller.confirmIncidentAndAlert(
            contacts: _contacts,
            settings: _settings,
          );
          _showSnack('Alert sent to your emergency contacts.');
        },
      ),
    );
  }

  Future<void> _manualSos() async {
    if (_contacts.isEmpty) {
      _showSnack('Add at least one emergency contact first.');
      return;
    }
    await widget.controller.confirmIncidentAndAlert(
      contacts: _contacts,
      settings: _settings,
      note: 'Manually triggered via SOS button.',
    );
    _showSnack('SOS alert sent to your emergency contacts.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _classificationSub?.cancel();
    _debugRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'Emergency Contacts',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ContactsScreen(storageService: widget.storageService),
                ),
              );
              _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(storageService: widget.storageService),
                ),
              );
              _loadData();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _monitoring ? Icons.mic : Icons.mic_off,
              size: 96,
              color: _monitoring ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _monitoring ? 'Monitoring active' : 'Monitoring off',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('${_contacts.length} emergency contact(s) configured'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'YAMNet: $_debugStatus\n'
                'Model loaded: ${widget.controller.audioService.modelLoaded}\n'
                'Bytes received: ${widget.controller.audioService.totalBytesReceived}'
                '${widget.controller.audioService.streamError != null ? "\nSTREAM ERROR: ${widget.controller.audioService.streamError}" : ""}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _toggleMonitoring,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: Text(_monitoring ? 'Stop Monitoring' : 'Start Monitoring'),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _manualSos,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(28),
              ),
              child: const Text('SOS',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

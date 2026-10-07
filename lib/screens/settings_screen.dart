import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storageService;

  const SettingsScreen({super.key, required this.storageService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings _settings = AppSettings();
  late TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.storageService.loadSettings();
    setState(() {
      _settings = settings;
      _pinController.text = settings.cancelPin;
    });
  }

  Future<void> _save() async {
    _settings.cancelPin = _pinController.text.trim().isEmpty
        ? _settings.cancelPin
        : _pinController.text.trim();
    await widget.storageService.saveSettings(_settings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Trigger sensitivity (YAMNet confidence)',
              style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Lower values make the trigger MORE sensitive (fires on lower-confidence '
            'matches). Higher values require the model to be more certain a distress '
            'sound (scream/shout/yell/crying) actually occurred. Tune this empirically '
            'during testing — start around 30-50%.',
            style: TextStyle(color: Colors.grey),
          ),
          Slider(
            value: _settings.triggerConfidenceThreshold,
            min: 0.1,
            max: 0.9,
            divisions: 16,
            label: '${(_settings.triggerConfidenceThreshold * 100).round()}%',
            onChanged: (v) => setState(() => _settings.triggerConfidenceThreshold = v),
          ),
          const SizedBox(height: 16),

          Text('Cancellation window', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'How many seconds you have to cancel a trigger before an alert is sent.',
            style: TextStyle(color: Colors.grey),
          ),
          Slider(
            value: _settings.cancellationWindowSeconds.toDouble(),
            min: 3,
            max: 15,
            divisions: 12,
            label: '${_settings.cancellationWindowSeconds}s',
            onChanged: (v) => setState(
              () => _settings.cancellationWindowSeconds = v.round(),
            ),
          ),
          const SizedBox(height: 16),

          Text('Cancellation PIN', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Required to cancel a false trigger. Keep this simple and memorable.',
            style: TextStyle(color: Colors.grey),
          ),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'PIN'),
          ),
          const SizedBox(height: 24),

          Text('Live location updates', style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  title: Text('Every ${_settings.locationUpdateIntervalSeconds}s'),
                  subtitle: const Text('Update interval'),
                ),
              ),
              Expanded(
                child: ListTile(
                  title: Text('${_settings.locationUpdateDurationMinutes} min'),
                  subtitle: const Text('Total duration'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          ElevatedButton(onPressed: _save, child: const Text('Save Settings')),
        ],
      ),
    );
  }
}

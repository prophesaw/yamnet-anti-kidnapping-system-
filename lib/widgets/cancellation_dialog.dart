import 'dart:async';
import 'package:flutter/material.dart';

class CancellationDialog extends StatefulWidget {
  final int windowSeconds;
  final String correctPin;
  final VoidCallback onCancelled;
  final VoidCallback onExpired;

  const CancellationDialog({
    super.key,
    required this.windowSeconds,
    required this.correctPin,
    required this.onCancelled,
    required this.onExpired,
  });

  @override
  State<CancellationDialog> createState() => _CancellationDialogState();
}

class _CancellationDialogState extends State<CancellationDialog> {
  late int _secondsLeft;
  Timer? _timer;
  final TextEditingController _pinController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.windowSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        widget.onExpired();
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _tryCancel() {
    if (_pinController.text == widget.correctPin) {
      _timer?.cancel();
      widget.onCancelled();
      Navigator.of(context).pop();
    } else {
      setState(() => _error = 'Incorrect PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Possible distress sound detected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sending an alert to your emergency contacts in $_secondsLeft seconds.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Enter PIN to cancel',
                errorText: _error,
              ),
              onSubmitted: (_) => _tryCancel(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: _tryCancel, child: const Text('Cancel Alert')),
        ],
      ),
    );
  }
}

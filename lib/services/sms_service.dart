import 'package:another_telephony/telephony.dart';
import '../models/emergency_contact.dart';

/// Sends SMS directly through the device's own carrier connection using
/// the native Android SmsManager (via the `another_telephony` plugin —
/// a maintained fork of the now-discontinued `telephony` package).
///
/// This is the core, cost-free alerting path for this project: it does
/// NOT depend on any paid third-party SMS gateway, and it does NOT
/// require an internet connection to work, only cellular signal.
class SmsService {
  final Telephony telephony = Telephony.instance;

  Future<bool> requestPermission() async {
    final granted = await telephony.requestSmsPermissions;
    return granted ?? false;
  }

  Future<void> sendAlertToContacts({
    required List<EmergencyContact> contacts,
    required double? latitude,
    required double? longitude,
    String? note,
  }) async {
    final hasLocation = latitude != null && longitude != null;
    final mapsLink = hasLocation
        ? 'https://maps.google.com/?q=$latitude,$longitude'
        : 'Location is currently unavailable.';
    final message = note != null
        ? 'EMERGENCY ALERT: I may be in danger. My location: $mapsLink. $note'
        : 'EMERGENCY ALERT: I may be in danger. My last known location: $mapsLink';

    for (final contact in contacts) {
      try {
        await telephony.sendSms(to: contact.phoneNumber, message: message);
      } catch (e) {
        // ignore: avoid_print
        print('Failed to send SMS to ${contact.phoneNumber}: $e');
      }
    }
  }

  Future<void> sendLocationUpdate({
    required List<EmergencyContact> contacts,
    required double latitude,
    required double longitude,
  }) async {
    final mapsLink = 'https://maps.google.com/?q=$latitude,$longitude';
    final message = 'Location update: $mapsLink';
    for (final contact in contacts) {
      try {
        await telephony.sendSms(to: contact.phoneNumber, message: message);
      } catch (e) {
        // ignore: avoid_print
        print('Failed to send location update to ${contact.phoneNumber}: $e');
      }
    }
  }
}

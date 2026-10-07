import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/emergency_contact.dart';
import '../models/app_settings.dart';

/// Handles all local (on-device) persistence: emergency contacts,
/// app settings, and a queue of location updates that couldn't be
/// sent to the backend while offline.
class StorageService {
  static const _contactsKey = 'emergency_contacts';
  static const _settingsKey = 'app_settings';
  static const _offlineQueueKey = 'offline_location_queue';

  Future<List<EmergencyContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contactsKey);
    if (raw == null) return [];
    final List<dynamic> list = jsonDecode(raw);
    final contacts = list
        .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
        .toList();
    contacts.sort((a, b) => a.priority.compareTo(b.priority));
    return contacts;
  }

  Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString(_contactsKey, raw);
  }

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return AppSettings();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> queueLocationUpdate(Map<String, dynamic> update) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_offlineQueueKey) ?? [];
    raw.add(jsonEncode(update));
    await prefs.setStringList(_offlineQueueKey, raw);
  }

  Future<List<Map<String, dynamic>>> getQueuedUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_offlineQueueKey) ?? [];
    return raw.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<void> clearQueuedUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineQueueKey);
  }
}

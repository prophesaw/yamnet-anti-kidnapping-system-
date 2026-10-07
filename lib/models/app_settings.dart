class AppSettings {
  /// YAMNet confidence (0.0-1.0) above which a distress-related sound
  /// class must score before it counts as a candidate trigger. Lower
  /// values = more sensitive (fires more easily); higher values =
  /// requires the model to be more certain. Tune this empirically
  /// during testing — start around 0.3-0.5.
  double triggerConfidenceThreshold;

  /// How many seconds the user has to cancel a trigger before an alert
  /// is sent automatically.
  int cancellationWindowSeconds;

  /// How often (in seconds) to send a follow-up location update after
  /// an incident has been triggered.
  int locationUpdateIntervalSeconds;

  /// How long (in minutes) to keep sending location updates after
  /// an incident is triggered.
  int locationUpdateDurationMinutes;

  /// PIN required to cancel a trigger (kept simple/local; not a security
  /// boundary, just a deliberate-action check).
  String cancelPin;

  AppSettings({
    this.triggerConfidenceThreshold = 0.4,
    this.cancellationWindowSeconds = 5,
    this.locationUpdateIntervalSeconds = 30,
    this.locationUpdateDurationMinutes = 15,
    this.cancelPin = '1234',
  });

  Map<String, dynamic> toJson() => {
        'triggerConfidenceThreshold': triggerConfidenceThreshold,
        'cancellationWindowSeconds': cancellationWindowSeconds,
        'locationUpdateIntervalSeconds': locationUpdateIntervalSeconds,
        'locationUpdateDurationMinutes': locationUpdateDurationMinutes,
        'cancelPin': cancelPin,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      triggerConfidenceThreshold:
          (json['triggerConfidenceThreshold'] as num?)?.toDouble() ?? 0.4,
      cancellationWindowSeconds: json['cancellationWindowSeconds'] as int? ?? 5,
      locationUpdateIntervalSeconds: json['locationUpdateIntervalSeconds'] as int? ?? 30,
      locationUpdateDurationMinutes: json['locationUpdateDurationMinutes'] as int? ?? 15,
      cancelPin: json['cancelPin'] as String? ?? '1234',
    );
  }
}

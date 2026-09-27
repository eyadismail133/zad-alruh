import 'package:flutter/foundation.dart';

const Object _sentinel = Object();

@immutable
class UserPreferences {
  final String darkMode;
  final double textScale;
  final String selectedCity;
  final String selectedTimezone;
  final int quranDefaultGoal;
  final bool notificationsEnabled;
  final String? activeDhikrSessionId;
  final DateTime? updatedAt;

  const UserPreferences({
    this.darkMode = 'system',
    this.textScale = 1.0,
    this.selectedCity = 'القاهرة',
    this.selectedTimezone = 'Africa/Cairo',
    this.quranDefaultGoal = 2,
    this.notificationsEnabled = false,
    this.activeDhikrSessionId,
    this.updatedAt,
  });

  UserPreferences copyWith({
    String? darkMode,
    double? textScale,
    String? selectedCity,
    String? selectedTimezone,
    int? quranDefaultGoal,
    bool? notificationsEnabled,
    Object? activeDhikrSessionId = _sentinel,
    bool clearActiveDhikrSession = false,
    DateTime? updatedAt,
  }) {
    final String? resolvedSessionId;
    if (clearActiveDhikrSession) {
      resolvedSessionId = null;
    } else if (!identical(activeDhikrSessionId, _sentinel)) {
      resolvedSessionId = activeDhikrSessionId as String?;
    } else {
      resolvedSessionId = this.activeDhikrSessionId;
    }

    return UserPreferences(
      darkMode: darkMode ?? this.darkMode,
      textScale: textScale ?? this.textScale,
      selectedCity: selectedCity ?? this.selectedCity,
      selectedTimezone: selectedTimezone ?? this.selectedTimezone,
      quranDefaultGoal: quranDefaultGoal ?? this.quranDefaultGoal,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      activeDhikrSessionId: resolvedSessionId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': 1,
      'dark_mode': darkMode,
      'text_scale': textScale,
      'selected_city': selectedCity,
      'selected_timezone': selectedTimezone,
      'quran_default_goal': quranDefaultGoal,
      'notifications_enabled': notificationsEnabled ? 1 : 0,
      'active_dhikr_session_id': activeDhikrSessionId,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      darkMode: map['dark_mode'] as String? ?? 'system',
      textScale: (map['text_scale'] as num?)?.toDouble() ?? 1.0,
      selectedCity: map['selected_city'] as String? ?? 'القاهرة',
      selectedTimezone: map['selected_timezone'] as String? ?? 'Africa/Cairo',
      quranDefaultGoal: (map['quran_default_goal'] as num?)?.toInt() ?? 2,
      notificationsEnabled: (map['notifications_enabled'] as num?)?.toInt() == 1,
      activeDhikrSessionId: map['active_dhikr_session_id'] as String?,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserPreferences &&
        other.darkMode == darkMode &&
        other.textScale == textScale &&
        other.selectedCity == selectedCity &&
        other.selectedTimezone == selectedTimezone &&
        other.quranDefaultGoal == quranDefaultGoal &&
        other.notificationsEnabled == notificationsEnabled &&
        other.activeDhikrSessionId == activeDhikrSessionId;
  }

  @override
  int get hashCode => Object.hash(
        darkMode,
        textScale,
        selectedCity,
        selectedTimezone,
        quranDefaultGoal,
        notificationsEnabled,
        activeDhikrSessionId,
      );

  @override
  String toString() =>
      'UserPreferences(dark: $darkMode, textScale: $textScale, city: $selectedCity, activeSession: $activeDhikrSessionId)';
}

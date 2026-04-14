class ReminderDefaults {
  const ReminderDefaults({
    required this.reminderEnabled,
    required this.reminderMinutesBefore,
    required this.reminderDelivery,
  });

  final bool reminderEnabled;
  final int reminderMinutesBefore;
  final String reminderDelivery;

  factory ReminderDefaults.fromJson(Map<String, dynamic> json) {
    return ReminderDefaults(
      reminderEnabled: json['reminderEnabled'] == true,
      reminderMinutesBefore:
          (json['reminderMinutesBefore'] as num?)?.toInt() ?? 30,
      reminderDelivery: (json['reminderDelivery'] ?? 'email').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reminderEnabled': reminderEnabled,
      'reminderMinutesBefore': reminderMinutesBefore,
      'reminderDelivery': reminderDelivery,
    };
  }

  ReminderDefaults copyWith({
    bool? reminderEnabled,
    int? reminderMinutesBefore,
    String? reminderDelivery,
  }) {
    return ReminderDefaults(
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      reminderDelivery: reminderDelivery ?? this.reminderDelivery,
    );
  }
}

class AccountSettings {
  const AccountSettings({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.pendingEmail,
    required this.avatarUrl,
    required this.calendarFeedUrl,
    required this.calendarFeedWebcalUrl,
    required this.reminderDefaults,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String pendingEmail;
  final String avatarUrl;
  final String calendarFeedUrl;
  final String calendarFeedWebcalUrl;
  final ReminderDefaults reminderDefaults;

  factory AccountSettings.fromJson(Map<String, dynamic> json) {
    return AccountSettings(
      firstName: (json['firstName'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      pendingEmail: (json['pendingEmail'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
      calendarFeedUrl: (json['calendarFeedUrl'] ?? '').toString(),
      calendarFeedWebcalUrl: (json['calendarFeedWebcalUrl'] ?? '').toString(),
      reminderDefaults: ReminderDefaults.fromJson(
        (json['reminderDefaults'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
    );
  }

  AccountSettings copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? pendingEmail,
    String? avatarUrl,
    String? calendarFeedUrl,
    String? calendarFeedWebcalUrl,
    ReminderDefaults? reminderDefaults,
  }) {
    return AccountSettings(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      pendingEmail: pendingEmail ?? this.pendingEmail,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      calendarFeedUrl: calendarFeedUrl ?? this.calendarFeedUrl,
      calendarFeedWebcalUrl:
          calendarFeedWebcalUrl ?? this.calendarFeedWebcalUrl,
      reminderDefaults: reminderDefaults ?? this.reminderDefaults,
    );
  }
}

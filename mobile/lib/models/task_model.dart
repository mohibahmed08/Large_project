class CalendarTask {
  CalendarTask({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.isCompleted,
    required this.source,
    required this.reminderEnabled,
    required this.reminderMinutesBefore,
  });

  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCompleted;
  final String source;
  final bool reminderEnabled;
  final int reminderMinutesBefore;

  factory CalendarTask.fromJson(Map<String, dynamic> json) {
    return CalendarTask(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      startDate: _parseDate(json['dueDate'] ?? json['startDate']),
      endDate: _parseDate(json['endDate']),
      isCompleted: json['isCompleted'] == true,
      source: (json['source'] ?? 'manual').toString(),
      reminderEnabled: json['reminderEnabled'] == true,
      reminderMinutesBefore: (json['reminderMinutesBefore'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString();
    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text)?.toLocal();
  }
}

class CalendarTask {
  CalendarTask({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.dueDate,
    required this.endDate,
    required this.isCompleted,
    required this.source,
  });

  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime? dueDate;
  final DateTime? endDate;
  final bool isCompleted;
  final String source;

  factory CalendarTask.fromJson(Map<String, dynamic> json) {
    return CalendarTask(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      dueDate: _parseDate(json['dueDate']),
      endDate: _parseDate(json['endDate']),
      isCompleted: json['isCompleted'] == true,
      source: (json['source'] ?? '').toString(),
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

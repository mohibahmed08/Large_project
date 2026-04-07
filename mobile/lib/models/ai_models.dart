class SuggestionItem {
  SuggestionItem({
    required this.title,
    required this.description,
    required this.suggestedTime,
  });

  final String title;
  final String description;
  final String suggestedTime;

  factory SuggestionItem.fromJson(Map<String, dynamic> json) {
    return SuggestionItem(
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      suggestedTime: (json['suggestedTime'] ?? '').toString(),
    );
  }
}

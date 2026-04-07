import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../models/user_model.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';

class AIScreen extends StatefulWidget {
  const AIScreen({
    super.key,
    required this.initialSession,
    required this.selectedDate,
    required this.onSessionUpdated,
    required this.onCreateTaskFromSuggestion,
  });

  final UserSession initialSession;
  final DateTime selectedDate;
  final ValueChanged<UserSession> onSessionUpdated;
  final Future<void> Function(String title, String description, String suggestedTime)
      onCreateTaskFromSuggestion;

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final AiService _aiService = AiService();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _preferencesController = TextEditingController();
  late UserSession _session;
  bool _isSending = false;
  bool _isLoadingSuggestions = false;
  final List<_ChatBubbleData> _messages = [
    const _ChatBubbleData(
      role: 'assistant',
      text: 'Ask about your day, your schedule, or get event suggestions.',
    ),
  ];
  List<SuggestionItem> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _preferencesController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _isSending = true;
      _messages.add(_ChatBubbleData(role: 'user', text: text));
      _messageController.clear();
    });

    try {
      final result = await _aiService.chat(
        session: _session,
        messages: _messages
            .map((message) => {'role': message.role, 'content': message.text})
            .toList(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _session = result.session;
        _messages.add(_ChatBubbleData(role: 'assistant', text: result.reply));
      });
      widget.onSessionUpdated(_session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _loadSuggestions() async {
    setState(() {
      _isLoadingSuggestions = true;
    });

    try {
      final result = await _aiService.suggestEvents(
        session: _session,
        date: widget.selectedDate,
        preferences: _preferencesController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _session = result.session;
        _suggestions = result.suggestions;
      });
      widget.onSessionUpdated(_session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingSuggestions = false;
      });
    }
  }

  Future<void> _saveSuggestion(SuggestionItem suggestion) async {
    try {
      await widget.onCreateTaskFromSuggestion(
        suggestion.title,
        suggestion.description,
        suggestion.suggestedTime,
      );
      if (!mounted) {
        return;
      }
      _showSnackBar('Saved suggestion to your calendar.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule ideas with context',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Use the same assistant style as the web sidebar to ask questions or generate suggestions for the selected day.',
                      style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _preferencesController,
                      decoration: const InputDecoration(
                        labelText: 'Suggestion preferences',
                        hintText:
                            'Quiet evening, outdoor ideas, study-focused, etc.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            _isLoadingSuggestions ? null : _loadSuggestions,
                        icon: _isLoadingSuggestions
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(
                          'Suggest events for ${widget.selectedDate.month}/${widget.selectedDate.day}/${widget.selectedDate.year}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _suggestions
                    .map(
                      (suggestion) => Card(
                        color: AppTheme.surfaceAlt.withValues(alpha: 0.7),
                        child: ListTile(
                          title: Text(suggestion.title),
                          subtitle: Text(
                            '${suggestion.suggestedTime.isEmpty ? 'No suggested time' : suggestion.suggestedTime}\n${suggestion.description}',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              height: 1.35,
                            ),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            onPressed: () => _saveSuggestion(suggestion),
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Add to calendar',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppTheme.accent.withValues(alpha: 0.18)
                          : AppTheme.surfaceAlt.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: isUser
                            ? AppTheme.textPrimary
                            : AppTheme.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Ask something about your calendar...',
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isSending ? null : _sendMessage,
                    child: _isSending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubbleData {
  const _ChatBubbleData({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;
}

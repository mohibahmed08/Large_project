import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:geolocator/geolocator.dart';

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
    required this.onCalendarChanged,
  });

  final UserSession initialSession;
  final DateTime selectedDate;
  final ValueChanged<UserSession> onSessionUpdated;
  final Future<void> Function(String title, String description, String suggestedTime)
      onCreateTaskFromSuggestion;
  final Future<void> Function() onCalendarChanged;

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
  bool _isFetchingLocation = false;
  double? _latitude;
  double? _longitude;
  String? _locationNotice;
  final Set<String> _savedSuggestionKeys = <String>{};
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
    _refreshLocation();
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
      _messages.add(const _ChatBubbleData(role: 'assistant', text: ''));
      _messageController.clear();
    });

    try {
      await for (final event in _aiService.chatStream(
        session: _session,
        messages: _messages
            .where((message) => message.text.isNotEmpty)
            .map((message) => {'role': message.role, 'content': message.text})
            .toList(),
        latitude: _latitude,
        longitude: _longitude,
      )) {
        if (!mounted) {
          return;
        }

        if (event.type == AiChatStreamEventType.delta) {
          setState(() {
            final lastIndex = _messages.length - 1;
            final previous = _messages[lastIndex];
            _messages[lastIndex] = _ChatBubbleData(
              role: previous.role,
              text: previous.text + event.delta,
            );
          });
        } else if (event.type == AiChatStreamEventType.done &&
            event.session != null) {
          _session = event.session!;
          widget.onSessionUpdated(_session);
          if (event.calendarChanged) {
            await widget.onCalendarChanged();
          }
        } else if (event.type == AiChatStreamEventType.error) {
          throw Exception(event.error ?? 'Streaming failed.');
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.role == 'assistant' &&
            _messages.last.text.isEmpty) {
          _messages.removeLast();
        }
      });
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
        latitude: _latitude,
        longitude: _longitude,
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
    final key = _suggestionKey(suggestion);
    if (_savedSuggestionKeys.contains(key)) {
      return;
    }

    try {
      await widget.onCreateTaskFromSuggestion(
        suggestion.title,
        suggestion.description,
        suggestion.suggestedTime,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedSuggestionKeys.add(key);
      });
      _showSnackBar('Saved suggestion to your calendar.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _suggestionKey(SuggestionItem suggestion) {
    return '${suggestion.title}|${suggestion.suggestedTime}|${suggestion.description}';
  }

  Future<void> _refreshLocation() async {
    if (_isFetchingLocation) {
      return;
    }

    setState(() {
      _isFetchingLocation = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }
        setState(() {
          _locationNotice = 'Location services are off, so nearby search may be less accurate.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        setState(() {
          _locationNotice =
              'Location permission is off, so the AI is using time and calendar context only.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationNotice =
            'Nearby suggestions are using your current location.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locationNotice =
            'Could not read device location, so nearby suggestions may be generic.';
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isFetchingLocation = false;
      });
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
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
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _locationNotice ??
                                      'Checking location for nearby suggestions...',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed:
                                    _isFetchingLocation ? null : _refreshLocation,
                                icon: _isFetchingLocation
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.my_location),
                                tooltip: 'Refresh location',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
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
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ..._suggestions.map(
                      (suggestion) {
                        final isSaved = _savedSuggestionKeys.contains(
                          _suggestionKey(suggestion),
                        );

                        return Card(
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
                              onPressed:
                                  isSaved ? null : () => _saveSuggestion(suggestion),
                              icon: Icon(
                                isSaved
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: isSaved ? AppTheme.success : null,
                              ),
                              tooltip: isSaved
                                  ? 'Already added'
                                  : 'Add to calendar',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  ..._messages.map((message) {
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
                        child: MarkdownBody(
                          data: message.text,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                              color: AppTheme.textPrimary,
                              height: 1.4,
                            ),
                            a: const TextStyle(
                              color: AppTheme.accent,
                              decoration: TextDecoration.underline,
                            ),
                            strong: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                            listBullet: const TextStyle(
                              color: AppTheme.textPrimary,
                            ),
                            blockquote: const TextStyle(
                              color: AppTheme.textMuted,
                              height: 1.4,
                            ),
                            code: TextStyle(
                              color: isUser
                                  ? AppTheme.textPrimary
                                  : AppTheme.accentStrong,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
          ],
        ),
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

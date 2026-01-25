import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/chat_message.dart';

/// Event types from the WebSocket
enum ChatEventType {
  message,
  chunk,
  toolUse,
  toolResult,
  milestonesUpdated,
  error,
}

/// Represents a chat event from the WebSocket
class ChatEvent {
  final ChatEventType type;
  final dynamic data;

  ChatEvent({required this.type, this.data});
}

/// Tool use event data
class ToolUseData {
  final String name;
  final Map<String, dynamic> input;

  ToolUseData({required this.name, required this.input});
}

/// Tool result event data
class ToolResultData {
  final String name;
  final String result;
  final bool isError;

  ToolResultData({required this.name, required this.result, this.isError = false});
}

class ChatService {
  static const String _baseWsUrl = 'ws://localhost:8000';

  WebSocketChannel? _channel;
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _eventController = StreamController<ChatEvent>.broadcast();

  String? _currentGoalId;
  bool _isConnected = false;

  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<ChatEvent> get eventStream => _eventController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect(String goalId) async {
    if (_isConnected && _currentGoalId == goalId) {
      return;
    }

    await disconnect();

    try {
      _currentGoalId = goalId;
      final uri = Uri.parse('$_baseWsUrl/chat/$goalId');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;

      _isConnected = true;
      _connectionController.add(true);

      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      rethrow;
    }
  }

  int _streamIdCounter = -1000; // Use negative IDs for streaming messages

  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String);
      final type = json['type'] as String?;

      switch (type) {
        case 'message':
          // Full message (used for welcome message or non-streamed responses)
          final message = ChatMessage(
            id: json['id'] is int
                ? json['id']
                : (json['id'] != null
                    ? int.tryParse(json['id'].toString()) ??
                        DateTime.now().millisecondsSinceEpoch
                    : DateTime.now().millisecondsSinceEpoch),
            role: json['role'] == 'assistant'
                ? MessageRole.assistant
                : MessageRole.user,
            content: json['content'] ?? '',
            createdAt: json['created_at'] != null
                ? DateTime.parse(json['created_at'])
                : DateTime.now(),
          );
          _messageController.add(message);
          _eventController.add(ChatEvent(type: ChatEventType.message, data: message));
          break;

        case 'stream_end':
          // End of streaming - just emit an event, don't add another message
          _eventController.add(ChatEvent(type: ChatEventType.message, data: null));
          break;

        case 'chunk':
          // Handle streaming chunks with negative IDs
          final message = ChatMessage(
            id: _streamIdCounter--,
            role: MessageRole.assistant,
            content: json['content'] ?? '',
            createdAt: DateTime.now(),
          );
          _messageController.add(message);
          _eventController.add(ChatEvent(type: ChatEventType.chunk, data: message));
          break;

        case 'tool_use':
          final toolData = ToolUseData(
            name: json['name'] ?? '',
            input: Map<String, dynamic>.from(json['input'] ?? {}),
          );
          _eventController.add(ChatEvent(type: ChatEventType.toolUse, data: toolData));
          break;

        case 'tool_result':
          final resultData = ToolResultData(
            name: json['name'] ?? '',
            result: json['result'] ?? '',
            isError: json['is_error'] ?? false,
          );
          _eventController.add(ChatEvent(type: ChatEventType.toolResult, data: resultData));
          break;

        case 'milestones_updated':
          final milestones = json['milestones'] as List?;
          print('ChatService: received milestones_updated with ${milestones?.length ?? 0} milestones');
          _eventController.add(ChatEvent(
            type: ChatEventType.milestonesUpdated,
            data: milestones,
          ));
          break;

        case 'error':
          _eventController.add(ChatEvent(
            type: ChatEventType.error,
            data: json['content'] ?? 'Unknown error',
          ));
          break;
      }
    } catch (e) {
      // Handle parsing errors silently or log them
      print('Chat message parse error: $e');
    }
  }

  void _handleError(dynamic error) {
    _isConnected = false;
    _connectionController.add(false);
  }

  void _handleDone() {
    _isConnected = false;
    _connectionController.add(false);
  }

  void sendMessage(String content) {
    if (!_isConnected || _channel == null) {
      throw Exception('Not connected to chat');
    }

    final payload = jsonEncode({
      'type': 'message',
      'content': content,
    });

    _channel!.sink.add(payload);
  }

  Future<void> disconnect() async {
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    _isConnected = false;
    _currentGoalId = null;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
    _eventController.close();
  }
}

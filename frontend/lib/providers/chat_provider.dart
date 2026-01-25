import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';

// Re-export chat service types
export '../services/chat_service.dart' show ChatEventType, ChatEvent, ToolUseData, ToolResultData;

// Chat service provider
final chatServiceProvider = Provider<ChatService>((ref) {
  final service = ChatService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Chat connection state
class ChatConnectionState {
  final bool isConnected;
  final bool isConnecting;
  final String? error;
  final String? goalId;

  const ChatConnectionState({
    this.isConnected = false,
    this.isConnecting = false,
    this.error,
    this.goalId,
  });

  ChatConnectionState copyWith({
    bool? isConnected,
    bool? isConnecting,
    String? error,
    String? goalId,
  }) {
    return ChatConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error,
      goalId: goalId ?? this.goalId,
    );
  }
}

final chatConnectionProvider =
    StateNotifierProvider<ChatConnectionNotifier, ChatConnectionState>((ref) {
  return ChatConnectionNotifier(ref);
});

class ChatConnectionNotifier extends StateNotifier<ChatConnectionState> {
  final Ref _ref;
  StreamSubscription<bool>? _connectionSubscription;

  ChatConnectionNotifier(this._ref) : super(const ChatConnectionState());

  Future<void> connect(String goalId) async {
    if (state.isConnecting) return;
    if (state.isConnected && state.goalId == goalId) return;

    state = state.copyWith(isConnecting: true, error: null, goalId: goalId);

    try {
      final chatService = _ref.read(chatServiceProvider);

      // Listen to connection state changes
      _connectionSubscription?.cancel();
      _connectionSubscription = chatService.connectionStream.listen((connected) {
        state = state.copyWith(isConnected: connected, isConnecting: false);
      });

      await chatService.connect(goalId);
      state = state.copyWith(isConnected: true, isConnecting: false);
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        isConnected: false,
        error: e.toString(),
      );
    }
  }

  Future<void> disconnect() async {
    _connectionSubscription?.cancel();
    final chatService = _ref.read(chatServiceProvider);
    await chatService.disconnect();
    state = const ChatConnectionState();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }
}

// Tool activity state for showing what the AI is doing
class ToolActivityState {
  final bool isProcessing;
  final String? currentTool;
  final String? lastResult;
  final bool lastResultWasError;

  const ToolActivityState({
    this.isProcessing = false,
    this.currentTool,
    this.lastResult,
    this.lastResultWasError = false,
  });

  ToolActivityState copyWith({
    bool? isProcessing,
    String? currentTool,
    String? lastResult,
    bool? lastResultWasError,
  }) {
    return ToolActivityState(
      isProcessing: isProcessing ?? this.isProcessing,
      currentTool: currentTool,
      lastResult: lastResult,
      lastResultWasError: lastResultWasError ?? this.lastResultWasError,
    );
  }
}

final toolActivityProvider =
    StateNotifierProvider.family<ToolActivityNotifier, ToolActivityState, String>(
        (ref, goalId) {
  return ToolActivityNotifier(ref, goalId);
});

class ToolActivityNotifier extends StateNotifier<ToolActivityState> {
  final Ref _ref;
  final String goalId;
  StreamSubscription<ChatEvent>? _eventSubscription;

  ToolActivityNotifier(this._ref, this.goalId) : super(const ToolActivityState()) {
    _listenToEvents();
  }

  void _listenToEvents() {
    final chatService = _ref.read(chatServiceProvider);
    _eventSubscription = chatService.eventStream.listen(_handleEvent);
  }

  void _handleEvent(ChatEvent event) {
    switch (event.type) {
      case ChatEventType.toolUse:
        final data = event.data as ToolUseData;
        state = state.copyWith(
          isProcessing: true,
          currentTool: _formatToolName(data.name),
        );
        break;

      case ChatEventType.toolResult:
        final data = event.data as ToolResultData;
        state = state.copyWith(
          isProcessing: false,
          currentTool: null,
          lastResult: data.result,
          lastResultWasError: data.isError,
        );
        break;

      case ChatEventType.message:
        // Clear tool state when a complete message arrives
        state = const ToolActivityState();
        break;

      default:
        break;
    }
  }

  String _formatToolName(String toolName) {
    switch (toolName) {
      case 'add_milestone':
        return 'Adding milestone...';
      case 'update_milestone':
        return 'Updating milestone...';
      case 'delete_milestone':
        return 'Removing milestone...';
      case 'reorder_milestones':
        return 'Reordering milestones...';
      case 'get_milestones':
        return 'Checking milestones...';
      default:
        return 'Processing...';
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

// Provider to trigger milestone refresh when chat updates them
final milestonesUpdatedProvider =
    StateNotifierProvider.family<MilestonesUpdatedNotifier, int, String>(
        (ref, goalId) {
  return MilestonesUpdatedNotifier(ref, goalId);
});

class MilestonesUpdatedNotifier extends StateNotifier<int> {
  final Ref _ref;
  final String goalId;
  StreamSubscription<ChatEvent>? _eventSubscription;

  MilestonesUpdatedNotifier(this._ref, this.goalId) : super(0) {
    _listenToEvents();
  }

  void _listenToEvents() {
    final chatService = _ref.read(chatServiceProvider);
    _eventSubscription = chatService.eventStream.listen(_handleEvent);
  }

  void _handleEvent(ChatEvent event) {
    if (event.type == ChatEventType.milestonesUpdated) {
      // Increment to trigger refresh
      print('MilestonesUpdatedNotifier: received milestonesUpdated event, incrementing state to ${state + 1}');
      state = state + 1;
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

// Chat messages for a specific goal
final chatMessagesProvider =
    StateNotifierProvider.family<ChatMessagesNotifier, List<ChatMessage>, String>(
        (ref, goalId) {
  return ChatMessagesNotifier(ref, goalId);
});

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;
  final String goalId;
  StreamSubscription<ChatMessage>? _messageSubscription;
  int? _currentStreamingId;
  String _currentStreamingContent = '';
  int _localIdCounter = -1; // Use negative IDs for local messages

  ChatMessagesNotifier(this._ref, this.goalId) : super([]) {
    _listenToMessages();
  }

  void _listenToMessages() {
    final chatService = _ref.read(chatServiceProvider);
    _messageSubscription = chatService.messageStream.listen(_handleMessage);
  }

  void _handleMessage(ChatMessage message) {
    // Check if this is a streaming chunk (negative IDs are streaming)
    if (message.id < 0) {
      // Accumulate streaming content
      if (_currentStreamingId == null) {
        _currentStreamingId = message.id;
        _currentStreamingContent = message.content;

        // Add new streaming message
        state = [
          ...state,
          ChatMessage(
            id: _currentStreamingId!,
            role: MessageRole.assistant,
            content: _currentStreamingContent,
            createdAt: message.createdAt,
          ),
        ];
      } else {
        // Update existing streaming message
        _currentStreamingContent += message.content;

        state = [
          ...state.where((m) => m.id != _currentStreamingId),
          ChatMessage(
            id: _currentStreamingId!,
            role: MessageRole.assistant,
            content: _currentStreamingContent,
            createdAt: message.createdAt,
          ),
        ];
      }
    } else {
      // Complete message - replace the streaming message with final version
      // Don't add a new message, the streaming version is already showing the content
      if (_currentStreamingId != null) {
        // Just reset streaming state - the streamed content is already correct
        _currentStreamingId = null;
        _currentStreamingContent = '';
      } else {
        // No streaming happened (e.g., welcome message) - add the message
        if (!state.any((m) => m.id == message.id)) {
          state = [...state, message];
        }
      }
    }
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty) return;

    // Add user message locally with negative ID
    final userMessage = ChatMessage(
      id: _localIdCounter--,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
    state = [...state, userMessage];

    // Reset streaming state for new response
    _currentStreamingId = null;
    _currentStreamingContent = '';

    // Send via WebSocket
    final chatService = _ref.read(chatServiceProvider);
    chatService.sendMessage(content);
  }

  void clearMessages() {
    state = [];
    _currentStreamingId = null;
    _currentStreamingContent = '';
    _localIdCounter = -1;
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

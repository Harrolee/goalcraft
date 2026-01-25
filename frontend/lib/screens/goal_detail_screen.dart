import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/goals_provider.dart';
import '../providers/chat_provider.dart';
import '../models/goal.dart';
import '../models/milestone.dart';
import '../widgets/milestone_tile.dart';
import '../widgets/chat_bubble.dart';

// Provider for chat panel visibility
final chatPanelOpenProvider = StateProvider<bool>((ref) => false);

// Provider for chat panel width
final chatPanelWidthProvider = StateProvider<double>((ref) => 400.0);

class GoalDetailScreen extends ConsumerStatefulWidget {
  final String goalId;

  const GoalDetailScreen({
    super.key,
    required this.goalId,
  });

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    ref.read(chatMessagesProvider(widget.goalId).notifier).sendMessage(content);
    _messageController.clear();
    _focusNode.requestFocus();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _toggleChatPanel() {
    final isOpen = ref.read(chatPanelOpenProvider);
    ref.read(chatPanelOpenProvider.notifier).state = !isOpen;

    // Connect to chat when opening
    if (!isOpen) {
      ref.read(chatConnectionProvider.notifier).connect(widget.goalId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalAsync = ref.watch(goalDetailProvider(widget.goalId));
    final isChatOpen = ref.watch(chatPanelOpenProvider);
    final chatWidth = ref.watch(chatPanelWidthProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: goalAsync.when(
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Goal'),
          data: (goal) => Text(goal.title),
        ),
        actions: [
          IconButton(
            icon: Icon(isChatOpen ? Icons.chat : Icons.chat_outlined),
            onPressed: _toggleChatPanel,
            tooltip: isChatOpen ? 'Close Chat' : 'Open AI Chat',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(goalDetailProvider(widget.goalId).notifier).refresh(),
          ),
        ],
      ),
      body: Row(
        children: [
          // Main content area
          Expanded(
            child: goalAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => _buildErrorState(context, error),
              data: (goal) => _GoalDetailContent(goal: goal, goalId: widget.goalId),
            ),
          ),
          // Chat panel (animated)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: isChatOpen ? chatWidth : 0,
            child: isChatOpen
                ? _ChatPanel(
                    goalId: widget.goalId,
                    width: chatWidth,
                    messageController: _messageController,
                    scrollController: _scrollController,
                    focusNode: _focusNode,
                    onSend: _sendMessage,
                    onClose: _toggleChatPanel,
                    onWidthChanged: (delta) {
                      final newWidth = (chatWidth - delta).clamp(300.0, 600.0);
                      ref.read(chatPanelWidthProvider.notifier).state = newWidth;
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: isChatOpen
          ? null
          : FloatingActionButton.extended(
              onPressed: _toggleChatPanel,
              icon: const Icon(Icons.chat),
              label: const Text('Ask AI'),
            ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load goal',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.read(goalDetailProvider(widget.goalId).notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPanel extends ConsumerStatefulWidget {
  final String goalId;
  final double width;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final Function(double) onWidthChanged;

  const _ChatPanel({
    required this.goalId,
    required this.width,
    required this.messageController,
    required this.scrollController,
    required this.focusNode,
    required this.onSend,
    required this.onClose,
    required this.onWidthChanged,
  });

  @override
  ConsumerState<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<_ChatPanel> {
  StreamSubscription<ChatEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToEvents() {
    final chatService = ref.read(chatServiceProvider);
    _eventSubscription = chatService.eventStream.listen((event) {
      if (event.type == ChatEventType.milestonesUpdated) {
        print('_ChatPanel: received milestonesUpdated event, refreshing goal');
        ref.read(goalDetailProvider(widget.goalId).notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(chatConnectionProvider);
    final messages = ref.watch(chatMessagesProvider(widget.goalId));
    final toolActivity = ref.watch(toolActivityProvider(widget.goalId));

    // Auto-scroll when new messages arrive
    ref.listen(chatMessagesProvider(widget.goalId), (previous, next) {
      if (next.length > (previous?.length ?? 0)) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (widget.scrollController.hasClients) {
            widget.scrollController.animateTo(
              widget.scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Resize handle + header
          Row(
            children: [
              // Resize handle
              GestureDetector(
                onHorizontalDragUpdate: (details) {
                  widget.onWidthChanged(details.delta.dx);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(
                    width: 8,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Header
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.smart_toy_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'AI Assistant',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              connectionState.isConnected
                                  ? 'Connected'
                                  : connectionState.isConnecting
                                      ? 'Connecting...'
                                      : 'Disconnected',
                              style: TextStyle(
                                fontSize: 11,
                                color: connectionState.isConnected
                                    ? Colors.green
                                    : connectionState.isConnecting
                                        ? Colors.orange
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!connectionState.isConnected && !connectionState.isConnecting)
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () => ref.read(chatConnectionProvider.notifier).connect(widget.goalId),
                          tooltip: 'Reconnect',
                          visualDensity: VisualDensity.compact,
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: widget.onClose,
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Error banner
          if (connectionState.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.error.withOpacity(0.1),
              child: Text(
                connectionState.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          // Messages
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ChatBubble(message: message),
                      );
                    },
                  ),
          ),
          // Tool activity indicator
          if (toolActivity.isProcessing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    toolActivity.currentTool ?? 'Processing...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          // Input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.messageController,
                    focusNode: widget.focusNode,
                    decoration: InputDecoration(
                      hintText: connectionState.isConnected
                          ? 'Ask about your goal...'
                          : 'Connecting...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    enabled: connectionState.isConnected && !toolActivity.isProcessing,
                    onSubmitted: (_) => widget.onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: connectionState.isConnected && !toolActivity.isProcessing ? widget.onSend : null,
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledBackgroundColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Ask me anything!',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Get advice, break down milestones,\nor track your progress.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalDetailContent extends ConsumerWidget {
  final Goal goal;
  final String goalId;

  const _GoalDetailContent({
    required this.goal,
    required this.goalId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completedMilestones =
        goal.milestones.where((m) => m.status == MilestoneStatus.completed).length;
    final totalMilestones = goal.milestones.length;
    final progress =
        totalMilestones > 0 ? completedMilestones / totalMilestones : 0.0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _GoalHeader(
            goal: goal,
            completedMilestones: completedMilestones,
            totalMilestones: totalMilestones,
            progress: progress,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: goal.milestones.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyMilestones(context))
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final milestone = goal.milestones[index];
                      return MilestoneTile(
                        milestone: milestone,
                        onToggle: () {
                          ref
                              .read(goalDetailProvider(goalId).notifier)
                              .toggleMilestoneStatus(milestone.id);
                        },
                      );
                    },
                    childCount: goal.milestones.length,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyMilestones(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.checklist_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No milestones yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Chat with AI to generate milestones for your goal.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _GoalHeader extends StatelessWidget {
  final Goal goal;
  final int completedMilestones;
  final int totalMilestones;
  final double progress;

  const _GoalHeader({
    required this.goal,
    required this.completedMilestones,
    required this.totalMilestones,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            goal.title,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (goal.description != null && goal.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              goal.description!,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (goal.targetDate != null) ...[
                _InfoChip(
                  icon: Icons.calendar_today_outlined,
                  label: DateFormat.yMMMd().format(goal.targetDate!),
                ),
                const SizedBox(width: 12),
              ],
              _InfoChip(
                icon: Icons.flag_outlined,
                label: 'Created ${DateFormat.yMMMd().format(goal.createdAt)}',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$completedMilestones of $totalMilestones milestones completed',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Milestones',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

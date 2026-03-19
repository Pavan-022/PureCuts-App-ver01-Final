import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/support_chat/services/support_chat_service.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key, this.service});

  final SupportChatService? service;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  late final SupportChatService _service;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();

  bool _sending = false;
  String? _chatId;
  String? _bootstrapError;
  int _lastRenderedMessageCount = 0;
  bool _markingSeen = false;
  final List<_PendingMessage> _pendingMessages = <_PendingMessage>[];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SupportChatService();
    _bootstrapChat();
  }

  Future<void> _bootstrapChat() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;

    if (mounted) {
      setState(() {
        _bootstrapError = null;
      });
    }

    try {
      final chatId = await _service.ensureSupportChat(
        uid: user.uid,
        userName: user.name,
        userEmail: user.email,
        userPhone: user.phone,
      );

      if (!mounted) return;
      setState(() => _chatId = chatId);

      await _service.markAdminMessagesSeen(uid: user.uid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapError =
            'Unable to open support chat right now. Please try again.';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Support chat error: $e')));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;

    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final pendingId = DateTime.now().microsecondsSinceEpoch.toString();
    final pending = _PendingMessage(
      clientMessageId: pendingId,
      text: text,
      timeLabel: _formatTime(Timestamp.now()),
    );

    setState(() {
      _pendingMessages.add(pending);
      _sending = true;
    });
    _scrollToBottom(animated: true);

    _controller.clear();

    try {
      await _service.sendSupportMessage(
        uid: user.uid,
        text: text,
        userName: user.name,
        userEmail: user.email,
        userPhone: user.phone,
        chatId: _chatId,
        clientMessageId: pendingId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingMessages.removeWhere(
          (item) => item.clientMessageId == pendingId,
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message. $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _scrollToBottom({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (!animated) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  int _toMillis(dynamic value) {
    if (value is Timestamp) return value.toDate().millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    return 0;
  }

  Timestamp? _resolvedMessageTimestamp(Map<String, dynamic> data) {
    final serverTs = data['serverTimestamp'];
    if (serverTs is Timestamp) return serverTs;
    final localTs = data['timestamp'];
    if (localTs is Timestamp) return localTs;
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Support Chat'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
      ),
      body: user == null
          ? const Center(child: Text('Please login to chat with support.'))
          : _bootstrapError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 22,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _bootstrapError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _bootstrapChat,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _chatId == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Preparing support chat...',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _service.messagesStream(_chatId!),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text('Could not load chat right now.'),
                              );
                            }

                            final docs = snapshot.data?.docs ?? [];
                            final hasPending = _pendingMessages.isNotEmpty;
                            final initialLoading =
                                snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                docs.isEmpty &&
                                !hasPending;
                            if (initialLoading) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final orderedDocs =
                                List<
                                    QueryDocumentSnapshot<Map<String, dynamic>>
                                  >.from(docs)
                                  ..sort((a, b) {
                                    final ams = _toMillis(
                                      _resolvedMessageTimestamp(a.data()),
                                    );
                                    final bms = _toMillis(
                                      _resolvedMessageTimestamp(b.data()),
                                    );
                                    if (ams == bms) {
                                      return a.id.compareTo(b.id);
                                    }
                                    return ams.compareTo(bms);
                                  });

                            final acknowledgedClientIds = orderedDocs
                                .map(
                                  (doc) =>
                                      (doc.data()['clientMessageId']
                                                  as String? ??
                                              '')
                                          .trim(),
                                )
                                .where((id) => id.isNotEmpty)
                                .toSet();
                            if (orderedDocs.isEmpty) {
                              final pendingOnly = _pendingMessages;
                              if (pendingOnly.isEmpty) {
                                return _EmptyChat(onStart: _focusComposer);
                              }
                              return ListView(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  8,
                                ),
                                children: pendingOnly
                                    .map(
                                      (item) => _ChatBubble(
                                        text: item.text,
                                        time: '${item.timeLabel} • Sending...',
                                        isMine: true,
                                      ),
                                    )
                                    .toList(),
                              );
                            }

                            final hasUnreadAdminMessage = orderedDocs.any((
                              doc,
                            ) {
                              final data = doc.data();
                              final senderId =
                                  (data['senderId'] as String? ?? '').trim();
                              final senderRole =
                                  (data['senderRole'] as String? ?? '')
                                      .trim()
                                      .toLowerCase();
                              final seen = data['seen'] == true;
                              final isAdminMessage =
                                  senderRole == 'admin' || senderId == 'admin';
                              return isAdminMessage && !seen;
                            });
                            if (hasUnreadAdminMessage && !_markingSeen) {
                              _markingSeen = true;
                              _service
                                  .markAdminMessagesSeen(uid: user.uid)
                                  .whenComplete(() => _markingSeen = false);
                            }

                            final hasNewMessage =
                                orderedDocs.length != _lastRenderedMessageCount;
                            if (hasNewMessage) {
                              final animate = _lastRenderedMessageCount > 0;
                              _lastRenderedMessageCount = orderedDocs.length;
                              _scrollToBottom(animated: animate);
                            }

                            final visiblePending = _pendingMessages
                                .where(
                                  (pending) => !acknowledgedClientIds.contains(
                                    pending.clientMessageId,
                                  ),
                                )
                                .toList();

                            return ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              itemCount:
                                  orderedDocs.length + visiblePending.length,
                              itemBuilder: (context, index) {
                                if (index >= orderedDocs.length) {
                                  final pending =
                                      visiblePending[index -
                                          orderedDocs.length];
                                  return _ChatBubble(
                                    text: pending.text,
                                    time: '${pending.timeLabel} • Sending...',
                                    isMine: true,
                                  );
                                }

                                final data = orderedDocs[index].data();
                                final senderId =
                                    (data['senderId'] as String? ?? '').trim();
                                final isMine = senderId == user.uid;
                                final text =
                                    (data['text'] as String? ??
                                            data['message'] as String? ??
                                            '')
                                        .trim();
                                final ts = _resolvedMessageTimestamp(data);

                                return _ChatBubble(
                                  text: text,
                                  time: _formatTime(ts),
                                  isMine: isMine,
                                );
                              },
                            );
                          },
                        ),
                ),
                _Composer(
                  controller: _controller,
                  focusNode: _composerFocusNode,
                  onSend: _handleSend,
                  isSending: _sending,
                ),
              ],
            ),
    );
  }

  void _focusComposer() {
    FocusScope.of(context).requestFocus(_composerFocusNode);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.isSending,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: isSending ? null : onSend,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSending ? AppColors.textHint : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.time,
    required this.isMine,
  });

  final String text;
  final String time;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 14),
          ),
          border: Border.all(
            color: isMine ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMine ? Colors.white : AppColors.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: AppColors.primary,
                size: 34,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Need help?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start a conversation with PureCuts support. We are here to help.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Write a message'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingMessage {
  _PendingMessage({
    required this.clientMessageId,
    required this.text,
    required this.timeLabel,
  });

  final String clientMessageId;
  final String text;
  final String timeLabel;
}

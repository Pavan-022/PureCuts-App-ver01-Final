import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/support_chat/presentation/support_chat_screen.dart';
import 'package:purecuts/features/support_chat/services/support_chat_service.dart';

/// A draggable support-chat FAB that snaps to the nearest screen edge.
///
/// **Usage**: Place as the last child of a body `Stack` (NOT as
/// `Scaffold.floatingActionButton`) so that the actual layout position
/// moves with each drag and hit-testing always works.
class SupportChatFab extends StatelessWidget {
  const SupportChatFab({super.key, this.service});

  final SupportChatService? service;

  @override
  Widget build(BuildContext context) {
    return _SupportChatFabAnimated(service: service);
  }
}

class _SupportChatFabAnimated extends StatefulWidget {
  const _SupportChatFabAnimated({this.service});

  final SupportChatService? service;

  @override
  State<_SupportChatFabAnimated> createState() =>
      _SupportChatFabAnimatedState();
}

class _SupportChatFabAnimatedState extends State<_SupportChatFabAnimated>
    with TickerProviderStateMixin {
  static const List<String> _messages = [
    'Support',
    'Need help?',
    'Place bulk orders here',
  ];

  static const double _fabSize = 56.0;
  static const double _edgePadding = 16.0;

  // ── Persisted position across widget rebuilds (static) ──────────────
  static double _persistedLeft = double.nan;
  static double _persistedTop = double.nan;

  // ── Instance position ──────────────────────────────────────────────
  double _left = 0;
  double _top = 0;
  bool _positionInitialized = false;

  // ── Snap animation bookkeeping ─────────────────────────────────────
  double _snapStartLeft = 0;
  double _snapStartTop = 0;
  double _snapTargetLeft = 0;
  double _snapTargetTop = 0;

  // ── Cached layout bounds (updated every build via LayoutBuilder) ───
  double _maxW = 0;
  double _maxH = 0;

  late final AnimationController _floatController;
  late final AnimationController _snapController;
  Timer? _messageTimer;
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onSnapTick);

    _messageTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _messages.length;
      });
    });
  }

  // ── Snap animation tick ────────────────────────────────────────────
  void _onSnapTick() {
    setState(() {
      _left = _snapStartLeft +
          (_snapTargetLeft - _snapStartLeft) * _snapController.value;
      _top = _snapStartTop +
          (_snapTargetTop - _snapStartTop) * _snapController.value;

      _left = _left.clamp(_edgePadding, _maxW - _fabSize - _edgePadding);
      _top = _top.clamp(_edgePadding, _maxH - _fabSize - _edgePadding);

      _persistedLeft = _left;
      _persistedTop = _top;
    });
  }

  // ── Snap to nearest screen edge ────────────────────────────────────
  void _snapToNearestEdge() {
    final double leftEdge = _edgePadding;
    final double rightEdge = _maxW - _fabSize - _edgePadding;
    final double topEdge = _edgePadding;
    final double bottomEdge = _maxH - _fabSize - _edgePadding;

    final distLeft = (_left - leftEdge).abs();
    final distRight = (_left - rightEdge).abs();
    final distTop = (_top - topEdge).abs();
    final distBottom = (_top - bottomEdge).abs();

    final minDist =
        [distLeft, distRight, distTop, distBottom].reduce(math.min);

    _snapStartLeft = _left;
    _snapStartTop = _top;

    if (minDist == distLeft) {
      _snapTargetLeft = leftEdge;
      _snapTargetTop = _top;
    } else if (minDist == distRight) {
      _snapTargetLeft = rightEdge;
      _snapTargetTop = _top;
    } else if (minDist == distTop) {
      _snapTargetLeft = _left;
      _snapTargetTop = topEdge;
    } else {
      _snapTargetLeft = _left;
      _snapTargetTop = bottomEdge;
    }

    _snapController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _floatController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    final chatService = widget.service ?? SupportChatService();

    return StreamBuilder<int>(
      stream: chatService.unreadCountStreamForUser(user.uid),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return LayoutBuilder(
          builder: (context, constraints) {
            _maxW = constraints.maxWidth;
            _maxH = constraints.maxHeight;

            // Initialise position once we know layout dimensions
            if (!_positionInitialized && _maxW > 0 && _maxH > 0) {
              if (!_persistedLeft.isNaN) {
                _left = _persistedLeft.clamp(
                    _edgePadding, _maxW - _fabSize - _edgePadding);
                _top = _persistedTop.clamp(
                    _edgePadding, _maxH - _fabSize - _edgePadding);
              } else {
                // Default: bottom-right corner
                _left = _maxW - _fabSize - _edgePadding;
                _top = _maxH - _fabSize - _edgePadding;
              }
              _positionInitialized = true;
            }

            // Safety clamp (e.g. after rotation / resize)
            final double clampedLeft =
                _left.clamp(_edgePadding, _maxW - _fabSize - _edgePadding);
            final double clampedTop =
                _top.clamp(_edgePadding, _maxH - _fabSize - _edgePadding);

            final bool isLeft = clampedLeft < _maxW / 2;

            return Stack(
              children: [
                Positioned(
                  left: clampedLeft,
                  top: clampedTop,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      _snapController.stop();
                      setState(() {
                        _left = (_left + details.delta.dx).clamp(
                            _edgePadding, _maxW - _fabSize - _edgePadding);
                        _top = (_top + details.delta.dy).clamp(
                            _edgePadding, _maxH - _fabSize - _edgePadding);
                        _persistedLeft = _left;
                        _persistedTop = _top;
                      });
                    },
                    onPanEnd: (_) => _snapToNearestEdge(),
                    child: SizedBox(
                      width: _fabSize,
                      height: _fabSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // ── FAB button ─────────────────────────
                          Positioned.fill(
                            child: FloatingActionButton(
                              heroTag: null,
                              backgroundColor: AppColors.primary,
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SupportChatScreen(
                                        service: chatService),
                                  ),
                                );
                              },
                              child: const Icon(
                                  Icons.support_agent_rounded),
                            ),
                          ),

                          // ── Unread badge ───────────────────────
                          if (unreadCount > 0)
                            Positioned(
                              right: isLeft ? null : -3,
                              left: isLeft ? -3 : null,
                              top: -3,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius:
                                      BorderRadius.circular(999),
                                  border: Border.all(
                                      color: Colors.white, width: 1.4),
                                ),
                                child: Text(
                                  unreadCount > 99
                                      ? '99+'
                                      : unreadCount.toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),

                          // ── Floating hint bubble ──────────────
                          Positioned(
                            left: isLeft ? 8 : null,
                            right: isLeft ? null : 8,
                            bottom: 70,
                            child: AnimatedBuilder(
                              animation: _floatController,
                              builder: (context, child) {
                                final offsetY =
                                    -3 * _floatController.value;
                                return Transform.translate(
                                  offset: Offset(0, offsetY),
                                  child: child,
                                );
                              },
                              child: IgnorePointer(
                                child: _SupportHintBubble(
                                  message: _messages[_messageIndex],
                                  isLeft: isLeft,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Hint bubble & pointer painter (unchanged)
// ═══════════════════════════════════════════════════════════════════════

class _SupportHintBubble extends StatelessWidget {
  const _SupportHintBubble({required this.message, required this.isLeft});

  final String message;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withOpacity(0.25)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: isLeft ? const Offset(-0.12, 0) : const Offset(0.12, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: Text(
                message,
                key: ValueKey<String>(message),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            left: isLeft ? 18 : null,
            right: isLeft ? null : 18,
            bottom: -7,
            child: CustomPaint(
              size: const Size(12, 8),
              painter: _BubblePointerPainter(
                fillColor: Colors.white,
                borderColor: AppColors.primary.withOpacity(0.25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubblePointerPainter extends CustomPainter {
  const _BubblePointerPainter({
    required this.fillColor,
    required this.borderColor,
  });

  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    final fill = Paint()..color = fillColor;
    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(path, fill);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(covariant _BubblePointerPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor;
  }
}

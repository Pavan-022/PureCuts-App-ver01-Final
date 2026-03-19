import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/support_chat/presentation/support_chat_screen.dart';
import 'package:purecuts/features/support_chat/services/support_chat_service.dart';

class SupportChatFab extends StatelessWidget {
  const SupportChatFab({super.key, this.service});

  final SupportChatService? service;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final chatService = service ?? SupportChatService();

    return StreamBuilder<int>(
      stream: chatService.unreadCountStreamForUser(user.uid),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: AppColors.primary,
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SupportChatScreen(service: chatService),
                  ),
                );
              },
              icon: const Icon(Icons.support_agent_rounded),
              label: const Text('Support'),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -3,
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
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.4),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

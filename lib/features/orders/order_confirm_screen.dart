// lib/features/orders/order_confirm_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/services/firestore_service.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/main_nav/main_nav_screen.dart';
import 'package:purecuts/features/orders/order_provider.dart';

class OrderConfirmScreen extends StatefulWidget {
  final int total;
  const OrderConfirmScreen({super.key, required this.total});

  @override
  State<OrderConfirmScreen> createState() => _OrderConfirmScreenState();
}

class _OrderConfirmScreenState extends State<OrderConfirmScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  String _status = 'Placed';
  final List<String> _steps = [
    'Placed',
    'Confirmed',
    'Processing',
    'Delivered',
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();

    // ✅ Save cart items to OrderProvider BEFORE clearing the cart
    final cart = context.read<CartModel>();
    final orders = context.read<OrderProvider>();
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid ?? '';

    final orderedItems = cart.items
        .map(
          (item) => {
            'id': item.id,
            'name': item.name,
            'brand': item.brand,
            'image': item.image,
            'price': item.price,
            'originalPrice': item.price,
            'size': '',
            'tag': '',
            'quantity': item.quantity,
          },
        )
        .toList();

    orders.addOrderedItems(orderedItems);

    if (uid.trim().isNotEmpty && orderedItems.isNotEmpty) {
      _firestoreService
          .registerUserPurchase(
            uid: uid,
            items: orderedItems,
            total: widget.total,
          )
          .catchError((_) {
            // Best effort persistence for review eligibility and order history.
          });
    }

    // ✅ Clear cart AFTER saving
    cart.clear();

    _simulateProgress();
  }

  void _simulateProgress() async {
    for (final step in ['Confirmed', 'Processing']) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _status = step);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Order Placed! 🎉',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹${widget.total} • ORD-${DateTime.now().millisecondsSinceEpoch % 10000}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 40),
              // Status stepper
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Status',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(_steps.length, (i) {
                      final stepIndex = _steps.indexOf(_status);
                      final isDone = i <= stepIndex;
                      final isActive = i == stepIndex;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isDone
                                    ? AppColors.primary
                                    : AppColors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDone
                                      ? AppColors.primary
                                      : AppColors.divider,
                                  width: 2,
                                ),
                              ),
                              child: isDone
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _steps[i],
                              style: TextStyle(
                                color: isActive
                                    ? AppColors.accent
                                    : isDone
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: AppColors.accent,
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainNavScreen()),
                    (_) => false,
                  ),
                  child: const Text('Continue Shopping'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

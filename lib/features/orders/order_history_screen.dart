import 'package:flutter/material.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/constants/app_constants.dart';
import 'package:purecuts/features/orders/order_confirm_screen.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _ordersFor(int tabIndex) {
    var list = List<Map<String, dynamic>>.from(AppConstants.orders);
    if (tabIndex == 1) {
      list = list.where((o) => o['status'] == 'Processing').toList();
    } else if (tabIndex == 2) {
      list = list
          .where((o) =>
              o['status'] == 'Delivered' || o['status'] == 'Cancelled')
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) => (o['id'] as String).toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFB69DF8),
                Color(0xFFC4B5FD),
                Color(0xFFDDD6FE),
                Color(0xFFEDE9FE),
                Colors.white,
              ],
              stops: [0.0, 0.18, 0.42, 0.70, 1.0],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Order History',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'All Orders'),
            Tab(text: 'Ongoing'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search orders...',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textHint, size: 20),
                filled: true,
                fillColor: AppColors.background,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [0, 1, 2].map((i) {
                final orders = _ordersFor(i);
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            color: AppColors.textHint, size: 52),
                        const SizedBox(height: 12),
                        const Text('No orders yet',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  itemBuilder: (_, idx) =>
                      _OrderCard(order: orders[idx]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDelivered = order['status'] == 'Delivered';
    final isCancelled = order['status'] == 'Cancelled';
    final statusColor = isDelivered
        ? const Color(0xFF22C55E)
        : isCancelled
            ? AppColors.error
            : AppColors.primary;
    final statusBg = isDelivered
        ? const Color(0xFFDCFCE7)
        : isCancelled
            ? const Color(0xFFFFEEEE)
            : AppColors.primary.withOpacity(0.1);
    const String imageUrl = 'https://picsum.photos/seed/order/200';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              imageUrl,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 72,
                color: AppColors.surface,
                child: const Icon(Icons.image,
                    color: AppColors.textHint, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text(order['id'],
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(order['status'],
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  order['date'],
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order['items']} item(s)',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '\u20B9${order['total']}',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15),
                    ),
                    Row(
                      children: [
                        _actionBtn(
                          label: 'Details',
                          outline: true,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => OrderConfirmScreen(
                                      total: (order['total'] as num)
                                          .toInt()))),
                        ),
                        const SizedBox(width: 6),
                        _actionBtn(
                          label: 'Reorder',
                          outline: false,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
      {required String label,
      required bool outline,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : AppColors.primary,
          border: Border.all(
              color: outline ? AppColors.border : AppColors.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: outline
                  ? AppColors.textSecondary
                  : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

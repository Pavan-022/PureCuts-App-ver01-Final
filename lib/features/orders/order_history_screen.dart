import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/models/order_model.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/orders/order_provider.dart';
import 'package:purecuts/features/orders/order_details_screen.dart';
import 'package:purecuts/features/products/product_detail_screen.dart';

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
  String? _lastHydratedUid;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.read<AuthProvider>().user?.uid ?? '';
    if (uid == _lastHydratedUid) return;
    _lastHydratedUid = uid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final orders = context.read<OrderProvider>();
      if (uid.trim().isEmpty) {
        orders.clear();
      } else {
        orders.fetchUserOrders(uid: uid, forceRefresh: true);
        orders.loadPurchasedProducts(uid: uid, forceRefresh: true);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _normalizeStatus(String? value) {
    final s = (value ?? '').trim().toLowerCase();
    if (s == 'completed') return 'delivered';
    if (s == 'out_for_delivery') return 'processing';
    return s;
  }

  List<OrderModel> _getFilteredOrders(
    List<OrderModel> allOrders,
    int tabIndex,
  ) {
    var list = allOrders;

    // Filter by status
    if (tabIndex == 1) {
      // Completed orders
      list = list
          .where(
            (o) =>
                _normalizeStatus(o.status) == 'delivered' ||
                _normalizeStatus(o.status) == 'cancelled',
          )
          .toList();
    } else if (tabIndex == 2) {
      // Ongoing orders
      list = list
          .where(
            (o) =>
                _normalizeStatus(o.status) == 'placed' ||
                _normalizeStatus(o.status) == 'confirmed' ||
                _normalizeStatus(o.status) == 'processing',
          )
          .toList();
    }

    // Search by order ID
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) => o.orderId.toLowerCase().contains(q)).toList();
    }

    return list;
  }

  List<Map<String, dynamic>> _getFilteredBought(
    List<Map<String, dynamic>> allBought,
    int tabIndex,
  ) {
    var list = allBought;

    if (tabIndex == 1) {
      // Completed orders
      list = list.where((p) {
        final status = _normalizeStatus(
          (p['lastOrderStatus'] ?? p['status'] ?? 'placed').toString(),
        );
        return status == 'delivered' || status == 'cancelled';
      }).toList();
    } else if (tabIndex == 2) {
      // Ongoing orders (exclude completed)
      list = list.where((p) {
        final status = _normalizeStatus(
          (p['lastOrderStatus'] ?? p['status'] ?? 'placed').toString(),
        );
        return status == 'placed' ||
            status == 'confirmed' ||
            status == 'processing';
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) {
        final name = (p['name'] ?? '').toString().toLowerCase();
        final brand = (p['brand'] ?? '').toString().toLowerCase();
        final orderId = (p['lastOrderId'] ?? '').toString().toLowerCase();
        return name.contains(q) || brand.contains(q) || orderId.contains(q);
      }).toList();
    }

    DateTime _toDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String)
        return DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    list.sort(
      (a, b) =>
          _toDate(b['lastOrderedAt']).compareTo(_toDate(a['lastOrderedAt'])),
    );

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final allBought = orderProvider.boughtProducts;

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
        title: const Text(
          'Order History',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'All Orders'),
            Tab(text: 'Completed'),
            Tab(text: 'Ongoing'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search orders...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textHint,
                  size: 20,
                ),
                filled: true,
                fillColor: AppColors.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: (orderProvider.ordersLoading || orderProvider.isLoading)
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [0, 1, 2].map((i) {
                      final filteredOrders = _getFilteredOrders(
                        orderProvider.orders,
                        i,
                      );
                      final filteredBought = _getFilteredBought(allBought, i);

                      if (filteredOrders.isEmpty && filteredBought.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                color: AppColors.textHint,
                                size: 52,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No orders yet',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (filteredOrders.isEmpty && filteredBought.isNotEmpty) {
                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredBought.length,
                          itemBuilder: (_, idx) =>
                              _BoughtOrderCard(product: filteredBought[idx]),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredOrders.length,
                        itemBuilder: (_, idx) =>
                            _OrderCard(order: filteredOrders[idx]),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BoughtOrderCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _BoughtOrderCard({required this.product});

  String _formatDateTime(dynamic value) {
    DateTime? dt;
    if (value is DateTime) dt = value;
    if (value is Timestamp) dt = value.toDate();
    if (value is String) dt = DateTime.tryParse(value);
    if (value is int) dt = DateTime.fromMillisecondsSinceEpoch(value);
    if (dt == null) return 'Date/Time unavailable';
    return DateFormat('d MMM yyyy, h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final image = (product['image'] ?? '').toString();
    final name = (product['name'] ?? 'Product').toString();
    final brand = (product['brand'] ?? '').toString();
    final price = product['price'] ?? 0;
    final lastOrderId = (product['lastOrderId'] ?? '').toString();
    final lastStatus = (product['lastOrderStatus'] ?? 'Purchased').toString();
    final paymentMode = (product['lastPaymentMethod'] ?? '').toString();
    final lastOrderedAt = product['lastOrderedAt'];

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      ),
      child: Container(
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
              child: image.isNotEmpty
                  ? Image.network(
                      image,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₹$price',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    brand,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(lastOrderedAt),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastOrderId.isNotEmpty
                        ? 'Order: $lastOrderId • $lastStatus'
                        : lastStatus,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (paymentMode.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Payment: ${paymentMode.toUpperCase()}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 72,
    height: 72,
    color: AppColors.surface,
    child: const Icon(Icons.image, color: AppColors.textHint, size: 28),
  );
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  const _OrderCard({required this.order});

  Color _getStatusColor() {
    switch (order.status.toLowerCase()) {
      case 'delivered':
        return const Color(0xFF22C55E);
      case 'cancelled':
        return AppColors.error;
      case 'processing':
      case 'confirmed':
        return AppColors.primary;
      case 'placed':
      default:
        return AppColors.textSecondary;
    }
  }

  Color _getStatusBackground() {
    switch (order.status.toLowerCase()) {
      case 'delivered':
        return const Color(0xFFDCFCE7);
      case 'cancelled':
        return const Color(0xFFFFEEEE);
      case 'processing':
      case 'confirmed':
      case 'placed':
        return AppColors.primary.withOpacity(0.1);
      default:
        return AppColors.surface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final statusBg = _getStatusBackground();
    final productImage = order.items.isNotEmpty
        ? (order.items.first['image'] ?? '')
        : '';

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
            child: (productImage.isNotEmpty)
                ? Image.network(
                    productImage,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.orderId,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.statusDisplay,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  order.formattedDate,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.items.length} item(s) • ${order.deliveryAddressShort}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Payment: ${order.paymentMethod.toUpperCase()}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₹${order.totalAmount}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Row(
                      children: [
                        _actionBtn(
                          label: 'Details',
                          outline: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailsScreen(order: order),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (order.canReorder)
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

  Widget _buildPlaceholder() => Container(
    width: 72,
    height: 72,
    color: AppColors.surface,
    child: const Icon(Icons.image, color: AppColors.textHint, size: 28),
  );

  Widget _actionBtn({
    required String label,
    required bool outline,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : AppColors.primary,
          border: Border.all(
            color: outline ? AppColors.border : AppColors.primary,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: outline ? AppColors.textSecondary : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

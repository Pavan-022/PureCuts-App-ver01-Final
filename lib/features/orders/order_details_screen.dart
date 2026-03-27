import 'package:flutter/material.dart';

import 'package:purecuts/core/models/order_model.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/features/products/product_detail_screen.dart';

class OrderDetailsScreen extends StatelessWidget {
  final OrderModel order;

  const OrderDetailsScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final statusSteps = ['Placed', 'Confirmed', 'Processing', 'Delivered'];
    final currentStepIndex = _getCurrentStepIndex(order.status);

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
          'Order Details',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Order Header
          _buildCard([
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.formattedDateTime,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Payment mode: ${order.paymentMethod.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(order.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _getStatusColor(order.status)),
                    ),
                    child: Text(
                      order.statusDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(order.status),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Status Timeline
          _buildCard([_buildTimeline(statusSteps, currentStepIndex)]),
          const SizedBox(height: 16),

          // Delivery Address
          Text('Delivery Address', style: _sectionTitleStyle()),
          const SizedBox(height: 8),
          _buildCard([
            _buildAddressSection(
              receiverName: order.receiverName,
              receiverPhone: order.receiverPhone,
              address: order.deliveryAddressString,
            ),
          ]),
          const SizedBox(height: 16),

          // Items
          Text('Items (${order.items.length})', style: _sectionTitleStyle()),
          const SizedBox(height: 8),
          _buildCard(_buildItemsList(context)),
          const SizedBox(height: 16),

          // Bill Details
          Text('Bill Details', style: _sectionTitleStyle()),
          const SizedBox(height: 8),
          _buildCard([
            _buildBillRow(
              'Item Total',
              '₹${order.billDetails?['itemTotal'] ?? order.totalAmount}',
            ),
            const Divider(height: 16),
            _buildBillRow(
              'Delivery Charge',
              order.billDetails?['deliveryCharge'] == 0
                  ? 'FREE'
                  : '₹${order.billDetails?['deliveryCharge'] ?? 0}',
            ),
            const Divider(height: 16),
            _buildBillRow(
              'Handling Charge',
              '₹${order.billDetails?['handlingCharge'] ?? 0}',
            ),
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Divider(thickness: 2),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Grand Total',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '₹${order.totalAmount}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Payment & Contact
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 420;
              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: isNarrow ? 0 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Payment Method', style: _sectionTitleStyle()),
                        const SizedBox(height: 8),
                        _buildCard([
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              order.paymentMethod.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  SizedBox(width: isNarrow ? 0 : 12, height: isNarrow ? 12 : 0),
                  Expanded(
                    flex: isNarrow ? 0 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer Email', style: _sectionTitleStyle()),
                        const SizedBox(height: 8),
                        _buildCard([
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: SelectableText(
                              order.customerEmail.trim().isEmpty
                                  ? '-'
                                  : order.customerEmail,
                              maxLines: 3,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Action Buttons
          if (order.canCancel)
            SizedBox(
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _showCancelConfirmation(context),
                child: const Text(
                  'Cancel Order',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (order.canReorder)
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _showReorderConfirmation(context),
                child: const Text(
                  'Reorder',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(children: children),
  );

  Widget _buildTimeline(List<String> steps, int currentIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          steps.length,
          (i) => Expanded(
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= currentIndex
                        ? AppColors.primary
                        : Colors.grey[300],
                  ),
                  child: Center(
                    child: i <= currentIndex
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  steps[i],
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressSection({
    required String receiverName,
    required String receiverPhone,
    required String address,
  }) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          receiverName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          receiverPhone,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          address,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  List<Widget> _buildItemsList(BuildContext context) => order.items.map((item) {
    final qty = item['quantity'] ?? 1;
    final price = item['price'] ?? 0;
    final product = _toProductPayload(item);
    final imageUrl = (product['image'] ?? '').toString();

    void openProduct() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    }

    return InkWell(
      onTap: openProduct,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: openProduct,
              borderRadius: BorderRadius.circular(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _itemPlaceholder(),
                      )
                    : _itemPlaceholder(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? 'Product',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item['brand'] ?? ''} • Qty: $qty',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '₹${(price * qty).toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }).toList();

  Widget _itemPlaceholder() => Container(
    width: 56,
    height: 56,
    color: const Color(0xFFF2F2F7),
    child: const Icon(
      Icons.image_outlined,
      color: AppColors.textHint,
      size: 22,
    ),
  );

  Map<String, dynamic> _toProductPayload(Map<String, dynamic> item) {
    final rawId = (item['productId'] ?? item['id'] ?? '').toString().trim();
    final normalizedId = rawId.contains('::')
        ? rawId.split('::').first.trim()
        : rawId;

    return {
      ...item,
      'id': normalizedId,
      'productId': normalizedId,
      'price': item['price'] ?? 0,
      'name': (item['name'] ?? 'Product').toString(),
      'brand': (item['brand'] ?? '').toString(),
      'image': (item['image'] ?? '').toString(),
      'description': (item['description'] ?? '').toString(),
    };
  }

  Widget _buildBillRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );

  TextStyle _sectionTitleStyle() => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textHint,
    letterSpacing: 0.3,
  );

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
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

  int _getCurrentStepIndex(String status) {
    switch (status.toLowerCase()) {
      case 'placed':
        return 0;
      case 'confirmed':
        return 1;
      case 'processing':
        return 2;
      case 'delivered':
        return 3;
      default:
        return 0;
    }
  }

  void _showCancelConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order'),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Order cancellation initiated')),
              );
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _showReorderConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reorder'),
        content: const Text('Add all items from this order to your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Items added to cart')),
              );
            },
            child: const Text('Add to Cart'),
          ),
        ],
      ),
    );
  }
}

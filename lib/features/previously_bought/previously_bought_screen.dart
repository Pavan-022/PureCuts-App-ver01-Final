import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/widgets/sticky_cart_bar.dart';

import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/main_nav/main_nav_screen.dart';
import 'package:purecuts/features/orders/order_provider.dart';

class PreviouslyBoughtScreen extends StatefulWidget {
  const PreviouslyBoughtScreen({super.key});

  @override
  State<PreviouslyBoughtScreen> createState() => _PreviouslyBoughtScreenState();
}

class _PreviouslyBoughtScreenState extends State<PreviouslyBoughtScreen> {
  String _search = '';
  String? _lastHydratedUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = Provider.of<AuthProvider>(context).user?.uid ?? '';
    if (uid == _lastHydratedUid) return;
    _lastHydratedUid = uid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final orders = context.read<OrderProvider>();
      if (uid.trim().isEmpty) {
        orders.clear();
      } else {
        orders.loadPurchasedProducts(uid: uid, forceRefresh: true);
      }
    });
  }

  void _goToShop() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final allBought = orderProvider.boughtProducts;

    final products = _search.isEmpty
        ? allBought
        : allBought
              .where(
                (p) =>
                    (p['name'] as String? ?? '').toLowerCase().contains(
                      _search.toLowerCase(),
                    ) ||
                    (p['brand'] as String? ?? '').toLowerCase().contains(
                      _search.toLowerCase(),
                    ),
              )
              .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Lavender gradient covering the top area
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 200,
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
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(allBought.length),
                if (allBought.isNotEmpty) _buildSearchBar(),
                const SizedBox(height: 4),
                Expanded(
                  child: orderProvider.isLoading && allBought.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : allBought.isEmpty
                      ? _buildNeverOrdered(context)
                      : products.isEmpty
                      ? _buildEmpty()
                      : _buildList(products),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Consumer<CartModel>(
        builder: (context, cart, _) {
          if (cart.itemCount == 0) return const SizedBox.shrink();
          return const StickyCartBar();
        },
      ),
    );
  }

  Widget _buildHeader(int total) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Order Again',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                total == 0
                    ? 'No purchases yet'
                    : '$total item${total > 1 ? 's' : ''} you\'ve ordered before',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _search = v),
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Search your past purchases...',
            hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
            prefixIcon: Icon(Icons.search, color: AppColors.textHint, size: 18),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  /// Shown when the user has NEVER placed any order
  Widget _buildNeverOrdered(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: AppColors.primary,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No purchases yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Items you order will appear here so you can quickly reorder them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _goToShop,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Place your order from here',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when the user has orders but search returns nothing
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: AppColors.primary,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No results found',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a different search term',
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> products) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: products.length,
      itemBuilder: (context, i) => _BoughtItem(product: products[i]),
    );
  }
}

class _BoughtItem extends StatelessWidget {
  final Map<String, dynamic> product;
  const _BoughtItem({required this.product});

  @override
  Widget build(BuildContext context) {
    final imageUrl = product['image'] as String? ?? '';
    final name = product['name'] as String? ?? 'Product';
    final brand = product['brand'] as String? ?? '';
    final price = (product['price'] as num?)?.toInt() ?? 0;
    final id = product['id'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_outlined,
                        color: AppColors.textHint,
                      ),
                    )
                  : const Icon(Icons.image_outlined, color: AppColors.textHint),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (brand.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    brand,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '₹$price',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Consumer<CartModel>(
            builder: (context, cart, _) {
              final qty = id.isEmpty ? 0 : cart.quantityOf(id);
              if (qty == 0) {
                return _AddButton(
                  onTap: () => context.read<CartModel>().add({
                    'id': id,
                    'name': name,
                    'brand': brand,
                    'image': imageUrl,
                    'price': price,
                  }),
                );
              }

              return _QtyControl(
                qty: qty,
                onMinus: () => context.read<CartModel>().remove(id),
                onPlus: () => context.read<CartModel>().add({
                  'id': id,
                  'name': name,
                  'brand': brand,
                  'image': imageUrl,
                  'price': price,
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Add',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _QtyControl({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onMinus,
            child: const SizedBox(
              width: 32,
              height: 34,
              child: Icon(
                Icons.remove_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          GestureDetector(
            onTap: onPlus,
            child: const SizedBox(
              width: 32,
              height: 34,
              child: Icon(
                Icons.add_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

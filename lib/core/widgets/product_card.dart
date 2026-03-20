import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/cart_model.dart';
import '../../features/products/product_detail_screen.dart';
import '../../features/products/product_list_screen.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final ValueChanged<Map<String, dynamic>>? onAddToCart;
  final bool showHeartIcon;
  final bool showBoughtEarlierBadge;

  const ProductCard({
    super.key,
    required this.product,
    this.onAddToCart,
    this.showHeartIcon = true,
    this.showBoughtEarlierBadge = false,
  });

  void _handleAddToCart(BuildContext context) {
    if (onAddToCart != null) {
      onAddToCart!(product);
      return;
    }
    context.read<CartModel>().add(product);
  }

  void _openProductDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  void _openSimilarProducts(BuildContext context) {
    final tag = (product['tag'] ?? '').toString().trim();
    final brand = (product['brand'] ?? '').toString().trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductListScreen(
          initialTag: tag.isNotEmpty ? tag : null,
          initialBrand: tag.isEmpty && brand.isNotEmpty ? brand : null,
        ),
      ),
    );
  }

  String _normalizeImagePath(String raw) {
    final path = raw.trim();
    if (path.isEmpty) return '';

    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    if (path.startsWith('gs://')) {
      final withoutScheme = path.substring(5);
      final slash = withoutScheme.indexOf('/');
      if (slash <= 0 || slash == withoutScheme.length - 1) return path;
      final bucket = withoutScheme.substring(0, slash);
      final objectPath = withoutScheme.substring(slash + 1);
      return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(objectPath)}?alt=media';
    }

    if (path.startsWith('assets/')) return path;

    // Raw storage object path, e.g. "products/image.png"
    return 'https://firebasestorage.googleapis.com/v0/b/purecuts-11a7c.firebasestorage.app/o/${Uri.encodeComponent(path)}?alt=media';
  }

  Widget _buildProductImage(String imagePath) {
    final resolved = _normalizeImagePath(imagePath);
    if (resolved.isEmpty) {
      return Container(
        height: 110,
        color: AppColors.surface,
        child: const Icon(Icons.image, color: AppColors.textHint, size: 40),
      );
    }

    if (!resolved.startsWith('assets/')) {
      return Image.network(
        resolved,
        height: 110,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          height: 110,
          color: AppColors.surface,
          child: const Icon(Icons.image, color: AppColors.textHint, size: 40),
        ),
      );
    }

    return Image.asset(
      resolved,
      height: 110,
      width: double.infinity,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        height: 110,
        color: AppColors.surface,
        child: const Icon(Icons.image, color: AppColors.textHint, size: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartModel>();
    final qty = cart.quantityOf(product['id']);

    final hasDiscount =
        (product['originalPrice'] as num? ?? 0) >
        (product['price'] as num? ?? 0);

    return GestureDetector(
      onTap: () => _openProductDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // ← key fix: don't expand unbounded
          children: [
            // ── Image area ───────────────────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: _buildProductImage(
                    (product['image'] ?? '').toString(),
                  ),
                ),

                // Heart
                if (showHeartIcon)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_border,
                        size: 16,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),

                // Discount badge
                if (hasDiscount)
                  Positioned(
                    top: 6,
                    right: showHeartIcon ? 30 : 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '-${(((product['originalPrice'] as num) - (product['price'] as num)) / (product['originalPrice'] as num) * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                // Bought earlier badge
                if (showBoughtEarlierBadge)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Bought earlier',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                // Size badge
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 10,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          product['size'] ?? '100 g',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ADD / stepper button
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: qty == 0
                      ? GestureDetector(
                          onTap: () => _handleAddToCart(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.success,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              'ADD',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => context.read<CartModel>().remove(
                                  product['id'],
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Icon(
                                    Icons.remove,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                              Text(
                                '$qty',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _handleAddToCart(context),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),

            // ── Product details ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand
                  Text(
                    product['brand'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),

                  // Name
                  Text(
                    product['name'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Rating
                  Row(
                    children: [
                      Icon(Icons.star, color: AppColors.warning, size: 11),
                      const SizedBox(width: 2),
                      Text(
                        '${product['rating'] ?? ''}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          '(${product['reviews'] ?? ''})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Price row
                  Row(
                    children: [
                      Text(
                        '₹${product['price']}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 5),
                      if (hasDiscount)
                        Flexible(
                          child: Text(
                            '₹${product['originalPrice']}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 10,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AppColors.textHint,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // See more
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openSimilarProducts(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See more like this',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 8,
                          color: AppColors.success,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

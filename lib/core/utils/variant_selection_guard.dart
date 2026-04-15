import 'package:flutter/material.dart';

bool _hasInlineVariants(dynamic raw) {
  if (raw is! Iterable) return false;

  for (final item in raw) {
    if (item == null) continue;
    if (item is Map && item.isNotEmpty) return true;
    if (item is String && item.trim().isNotEmpty) return true;
  }

  return false;
}

bool quickAddRequiresVariantSelection(Map<String, dynamic> product) {
  final productId = (product['id'] ?? '').toString().trim();
  final variantId = (product['variantId'] ?? '').toString().trim();

  // Variant-specific payloads are already safe to add.
  if (variantId.isNotEmpty || productId.contains('::')) {
    return false;
  }

  final productType = (product['productType'] ?? product['type'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final isVariantTyped =
      productType == 'variable' ||
      productType == 'variant' ||
      productType == 'variation' ||
      productType == 'configurable';

  final hasInlineVariants =
      _hasInlineVariants(product['variants']) ||
      _hasInlineVariants(product['productVariants']) ||
      _hasInlineVariants(product['variantOptions']);

  final hasVariantLabelHint = (product['variableOptions'] ?? '')
      .toString()
      .trim()
      .isNotEmpty;

  return isVariantTyped || hasInlineVariants || hasVariantLabelHint;
}

bool ensureVariantSelectedBeforeQuickAdd(
  BuildContext context,
  Map<String, dynamic> product, {
  bool floating = false,
}) {
  final requiresVariant = quickAddRequiresVariantSelection(product);
  if (!requiresVariant) return true;

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  if (floating) {
    final media = MediaQuery.of(context);
    final bottomSafeOffset = media.padding.bottom + 44;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottomSafeOffset),
        content: const Text(
          'Please select a variant on the product details page.',
        ),
      ),
    );
  } else {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Please select a variant on the product details page.'),
      ),
    );
  }
  return false;
}

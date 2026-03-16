import 'package:cloud_firestore/cloud_firestore.dart';

import 'product_models.dart';

class ProductRepository {
  ProductRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Fetches a single product with its variants and latest 20 reviews
  /// in a single parallel [Future.wait] call.
  ///
  /// Throws [StateError] if the product document does not exist.
  Future<Product> getProductById(String productId) async {
    final productRef = _db.collection('products').doc(productId);

    final productDoc = await productRef.get();
    if (!productDoc.exists || productDoc.data() == null) {
      throw StateError('Product $productId not found');
    }

    QuerySnapshot<Map<String, dynamic>>? variantSnap;
    QuerySnapshot<Map<String, dynamic>>? reviewSnap;

    try {
      variantSnap = await productRef.collection('variants').get();
    } catch (_) {
      variantSnap = null;
    }

    try {
      reviewSnap = await productRef
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
    } catch (_) {
      reviewSnap = null;
    }

    final variants =
        (variantSnap?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map((doc) => ProductVariant.fromMap(doc.id, doc.data()))
            .toList();

    final reviews =
        (reviewSnap?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map((doc) => ReviewModel.fromMap(doc.id, doc.data()))
            .toList();

    return Product.fromMap(
      productDoc.id,
      productDoc.data()!,
      variants: variants,
      reviews: reviews,
    );
  }

  /// Returns up to [limit] recommended products, filtered by [brand] when
  /// provided, then loosely sorted by [category] keyword match.
  ///
  /// The current product ([currentProductId]) is always excluded.
  Future<List<Product>> getRecommendedProducts({
    required String currentProductId,
    String? category,
    String? brand,
    int limit = 10,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('products')
        .limit(limit * 3);

    final normalizedBrand = (brand ?? '').trim();
    if (normalizedBrand.isNotEmpty) {
      query = query.where('brand', isEqualTo: normalizedBrand);
    }

    final snap = await query.get();

    final base = snap.docs
        .where((doc) => doc.id != currentProductId)
        .map((doc) => Product.fromMap(doc.id, doc.data()))
        .toList();

    // Secondary sort by category keyword when brand filter was not applied.
    if (normalizedBrand.isEmpty && (category ?? '').trim().isNotEmpty) {
      final lowerCategory = category!.toLowerCase();
      base.sort((a, b) {
        final aMatch = a.description.toLowerCase().contains(lowerCategory)
            ? 1
            : 0;
        final bMatch = b.description.toLowerCase().contains(lowerCategory)
            ? 1
            : 0;
        return bMatch.compareTo(aMatch);
      });
    }

    return base.take(limit).toList();
  }

  /// Streams live updates for a product, re-fetching full detail
  /// (variants + reviews) on every document change.
  Stream<Product> watchProduct(String productId) {
    return _db
        .collection('products')
        .doc(productId)
        .snapshots()
        .asyncMap((_) => getProductById(productId));
  }
}

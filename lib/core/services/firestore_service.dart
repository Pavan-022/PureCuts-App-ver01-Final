import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:purecuts/core/models/product_model.dart';
import 'package:purecuts/core/models/user_model.dart';
import 'package:purecuts/features/products/detail/product_models.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const String _usersCollection = 'users';
  static const String _productsCollection = 'products';
  static const String _ordersCollection = 'orders';
  static const String _productSharesCollection = 'productShares';

  String _baseProductId(String value) {
    final id = value.trim();
    if (id.isEmpty) return '';
    final sep = id.indexOf('::');
    if (sep <= 0) return id;
    return id.substring(0, sep);
  }

  // ── Create user profile (only if it doesn't already exist) ───────────────

  Future<void> createUserProfile(UserModel user) async {
    final ref = _db.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set(user.toMap());
    }
  }

  // ── Overwrite / update user profile ───────────────────────────────────────

  Future<void> setUserProfile(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  // ── Update a single field in user profile ────────────────────────────────

  Future<void> updateUserField(String uid, String field, dynamic value) async {
    await _db.collection('users').doc(uid).update({field: value});
  }

  // ── Fetch user profile ────────────────────────────────────────────────────

  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return UserModel.fromMap(doc.data()!, uid);
    return null;
  }

  // ── Fetch all products ────────────────────────────────────────────────────

  Future<List<ProductModel>> getProducts() async {
    final snap = await _db.collection('products').get();
    return snap.docs
        .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<String> createProduct(Map<String, dynamic> data) async {
    final ref = await _db.collection('products').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<String> createVariant(
    String productId,
    Map<String, dynamic> data,
  ) async {
    final ref = await _db
        .collection('products')
        .doc(productId)
        .collection('variants')
        .add({...data, 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  Future<List<ProductVariant>> getProductVariants(String productId) async {
    final snap = await _db
        .collection('products')
        .doc(productId)
        .collection('variants')
        .orderBy('createdAt')
        .get();

    return snap.docs
        .map((doc) => ProductVariant.fromMap(doc.id, doc.data()))
        .toList();
  }

  // ── Fetch products by category ────────────────────────────────────────────

  Future<List<ProductModel>> getProductsByCategory(String category) async {
    final snap = await _db
        .collection('products')
        .where('category', isEqualTo: category)
        .get();
    return snap.docs
        .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  // ── Fetch categories ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCategories() async {
    final snap = await _db.collection('categories').orderBy('order').get();
    if (snap.docs.isEmpty) return [];
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getSubCategories() async {
    final snap = await _db.collection('subCategories').get();
    if (snap.docs.isEmpty) return [];
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> getBrands() async {
    final snap = await _db.collection('brands').get();
    if (snap.docs.isEmpty) return [];
    final brands = snap.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
    brands.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );
    return brands;
  }

  Future<bool> isProductFavorited({
    required String uid,
    required String productId,
  }) async {
    if (uid.trim().isEmpty || productId.trim().isEmpty) return false;

    try {
      final userDoc = await _db.collection(_usersCollection).doc(uid).get();
      final data = userDoc.data() ?? const <String, dynamic>{};
      final list =
          (data['favoriteProductIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      return list.contains(productId);
    } catch (_) {
      return false;
    }
  }

  Future<void> setProductFavorited({
    required String uid,
    required String productId,
    required bool isFavorited,
    Map<String, dynamic>? productData,
  }) async {
    if (uid.trim().isEmpty || productId.trim().isEmpty) return;

    await _db.collection(_usersCollection).doc(uid).set({
      'favoriteProductIds': isFavorited
          ? FieldValue.arrayUnion([productId])
          : FieldValue.arrayRemove([productId]),
      'favoriteProductMeta.$productId': isFavorited
          ? {
              ...?productData,
              'productId': productId,
              'updatedAt': FieldValue.serverTimestamp(),
            }
          : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> recordProductShare({
    required String productId,
    required String uid,
    String? channel,
    Map<String, dynamic>? meta,
  }) async {
    if (productId.trim().isEmpty) return;

    final normalizedUid = uid.trim();

    if (normalizedUid.isNotEmpty) {
      await _db.collection(_usersCollection).doc(normalizedUid).set({
        'sharedProductIds': FieldValue.arrayUnion([productId]),
        'lastSharedProduct': {
          'productId': productId,
          'channel': channel ?? 'system_share_sheet',
          'meta': meta ?? {},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    try {
      await _db.collection(_productSharesCollection).add({
        'productId': productId,
        'uid': normalizedUid.isEmpty ? 'anonymous' : normalizedUid,
        'channel': channel ?? 'system_share_sheet',
        'meta': meta ?? {},
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _db.collection(_productsCollection).doc(productId).set({
        'sharedCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort analytics for restricted rules; ignore failures.
    }
  }

  Future<void> registerUserPurchase({
    required String uid,
    required List<Map<String, dynamic>> items,
    required int total,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty || items.isEmpty) return;

    final productIds = items
        .map((e) => _baseProductId((e['id'] ?? '').toString()))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (productIds.isEmpty) return;

    await _db.collection(_ordersCollection).add({
      'uid': cleanUid,
      'items': items,
      'productIds': productIds,
      'total': total,
      'status': 'placed',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection(_usersCollection).doc(cleanUid).set({
      'purchasedProductIds': FieldValue.arrayUnion(productIds),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> hasUserPurchasedProduct({
    required String uid,
    required String productId,
  }) async {
    final cleanUid = uid.trim();
    final cleanProductId = _baseProductId(productId);
    if (cleanUid.isEmpty || cleanProductId.isEmpty) return false;

    try {
      final userDoc = await _db
          .collection(_usersCollection)
          .doc(cleanUid)
          .get();
      final data = userDoc.data() ?? const <String, dynamic>{};
      final purchased =
          (data['purchasedProductIds'] as List?)
              ?.map((e) => _baseProductId(e.toString()))
              .toList() ??
          const <String>[];
      if (purchased.contains(cleanProductId)) return true;

      final orders = await _db
          .collection(_ordersCollection)
          .where('uid', isEqualTo: cleanUid)
          .where('productIds', arrayContains: cleanProductId)
          .limit(1)
          .get();
      return orders.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> uploadReviewMedia({
    required String uid,
    required String productId,
    required List<XFile> files,
  }) async {
    if (files.isEmpty) return const [];
    final cleanUid = uid.trim();
    final cleanProductId = _baseProductId(productId);
    if (cleanUid.isEmpty || cleanProductId.isEmpty) return const [];

    final uploaded = <String>[];
    final failed = <String>[];
    for (final file in files) {
      try {
        final lower = file.name.toLowerCase();
        String contentType;
        if (lower.endsWith('.mp4') ||
            lower.endsWith('.mov') ||
            lower.endsWith('.avi') ||
            lower.endsWith('.mkv')) {
          contentType = 'video/mp4';
        } else {
          contentType = 'image/jpeg';
        }

        final ext = file.name.contains('.')
            ? file.name.substring(file.name.lastIndexOf('.'))
            : '';
        final ref = _storage.ref(
          'reviews/$cleanProductId/$cleanUid/${DateTime.now().millisecondsSinceEpoch}$ext',
        );
        UploadTask uploadTask;
        if (!kIsWeb && file.path.isNotEmpty) {
          uploadTask = ref.putFile(
            File(file.path),
            SettableMetadata(contentType: contentType),
          );
        } else {
          uploadTask = ref.putData(
            await file.readAsBytes(),
            SettableMetadata(contentType: contentType),
          );
        }
        final task = await uploadTask;
        final url = await task.ref.getDownloadURL();
        uploaded.add(url);
      } catch (e) {
        failed.add('${file.name}: $e');
      }
    }

    if (files.isNotEmpty && uploaded.isEmpty) {
      throw StateError(
        'Could not upload media. Please check storage permissions/rules and try again.',
      );
    }
    if (failed.isNotEmpty) {
      throw StateError(
        'Uploaded ${uploaded.length}/${files.length} files. Some files failed to upload.',
      );
    }

    return uploaded;
  }

  Future<void> submitProductReview({
    required String uid,
    required String productId,
    required String userName,
    required double rating,
    required String comment,
    List<String> mediaUrls = const [],
  }) async {
    final cleanUid = uid.trim();
    final cleanProductId = _baseProductId(productId);
    if (cleanUid.isEmpty || cleanProductId.isEmpty) return;

    final canReview = await hasUserPurchasedProduct(
      uid: cleanUid,
      productId: cleanProductId,
    );
    if (!canReview) {
      throw StateError('Only users who bought this product can review it.');
    }

    final reviewRef = _db
        .collection(_productsCollection)
        .doc(cleanProductId)
        .collection('reviews')
        .doc(cleanUid);

    final existingReview = await reviewRef.get();

    await reviewRef.set({
      'uid': cleanUid,
      'userName': userName.trim().isEmpty ? 'Verified Buyer' : userName.trim(),
      'rating': rating,
      'comment': comment.trim(),
      'mediaUrls': mediaUrls,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existingReview.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteProductReview({
    required String uid,
    required String productId,
  }) async {
    final cleanUid = uid.trim();
    final cleanProductId = _baseProductId(productId);
    if (cleanUid.isEmpty || cleanProductId.isEmpty) return;

    await _db
        .collection(_productsCollection)
        .doc(cleanProductId)
        .collection('reviews')
        .doc(cleanUid)
        .delete();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purecuts/core/models/product_model.dart';
import 'package:purecuts/core/models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    final snap = await _db
        .collection('categories')
        .orderBy('order')
        .get();
    if (snap.docs.isEmpty) return [];
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }
}

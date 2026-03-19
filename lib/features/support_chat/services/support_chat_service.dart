import 'package:cloud_firestore/cloud_firestore.dart';

class SupportChatService {
  SupportChatService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String _chatsCollection = 'chats';
  static const String _messagesSubcollection = 'messages';
  static const String _adminId = 'admin';

  String chatIdForUser(String uid) => 'support_$uid';

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection(_chatsCollection);

  CollectionReference<Map<String, dynamic>> _messagesRef(String chatId) =>
      _chats.doc(chatId).collection(_messagesSubcollection);

  Future<bool> chatExists(String chatId) async {
    final snap = await _chats.doc(chatId).get();
    return snap.exists;
  }

  Future<String> ensureSupportChat({
    required String uid,
    String? userName,
    String? userEmail,
    String? userPhone,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      throw ArgumentError('uid cannot be empty');
    }

    final chatId = chatIdForUser(cleanUid);
    final chatRef = _chats.doc(chatId);

    await chatRef.set({
      'chatId': chatId,
      'type': 'support',
      'participants': [cleanUid, _adminId],
      'userId': cleanUid,
      'adminId': _adminId,
      'userName': (userName ?? '').trim(),
      'userEmail': (userEmail ?? '').trim(),
      'userPhone': (userPhone ?? '').trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return chatId;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId) {
    return _messagesRef(
      chatId,
    ).orderBy('timestamp', descending: false).snapshots();
  }

  Stream<int> unreadCountStreamForUser(String uid) {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return const Stream<int>.empty();

    final chatId = chatIdForUser(cleanUid);
    return _messagesRef(chatId)
        .where('senderRole', isEqualTo: 'admin')
        .where('seen', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.size);
  }

  Future<void> sendSupportMessage({
    required String uid,
    required String text,
    String? userName,
    String? userEmail,
    String? userPhone,
    String? chatId,
    String? clientMessageId,
  }) async {
    final cleanUid = uid.trim();
    final message = text.trim();
    if (cleanUid.isEmpty || message.isEmpty) return;

    final resolvedChatId = (chatId ?? '').trim().isNotEmpty
        ? chatId!.trim()
        : await ensureSupportChat(
            uid: cleanUid,
            userName: userName,
            userEmail: userEmail,
            userPhone: userPhone,
          );

    final messageRef = _messagesRef(resolvedChatId).doc();
    final localNow = Timestamp.now();

    await messageRef.set({
      'messageId': messageRef.id,
      'chatId': resolvedChatId,
      'senderId': cleanUid,
      'senderRole': 'user',
      'text': message,
      'message': message,
      'clientMessageId': (clientMessageId ?? '').trim(),
      'seen': false,
      'timestamp': localNow,
      'serverTimestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _chats.doc(resolvedChatId).set({
      'lastMessage': message,
      'lastMessageBy': cleanUid,
      'lastTimestamp': localNow,
      'lastServerTimestamp': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markAdminMessagesSeen({required String uid}) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;

    final chatId = chatIdForUser(cleanUid);
    final query = await _messagesRef(chatId)
        .where('senderRole', isEqualTo: 'admin')
        .where('seen', isEqualTo: false)
        .get();

    if (query.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in query.docs) {
      batch.update(doc.reference, {
        'seen': true,
        'seenAt': FieldValue.serverTimestamp(),
      });
    }

    batch.set(_chats.doc(chatId), {
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }
}

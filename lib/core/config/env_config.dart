import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static String get firebaseApiKey => dotenv.env['FIREBASE_API_KEY'] ?? '';
  static String get firebaseAuthDomain =>
      dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '';
  static String get firebaseProjectId => dotenv.env['FIREBASE_PROJECT_ID'] ?? '';
  static String get firebaseStorageBucket =>
      dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '';
  static String get firebaseMessagingSenderId =>
      dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '';
  static String get firebaseAppId => dotenv.env['FIREBASE_APP_ID'] ?? '';
  static String get firebaseMeasurementId =>
      dotenv.env['FIREBASE_MEASUREMENT_ID'] ?? '';

  static String get algoliaAppId => dotenv.env['ALGOLIA_APP_ID'] ?? '';
  static String get algoliaSearchApiKey =>
      dotenv.env['ALGOLIA_SEARCH_API_KEY'] ?? '';
  static String get algoliaIndexName =>
      dotenv.env['ALGOLIA_INDEX_NAME'] ?? 'products';

  /// Initialize environment variables
  static Future<void> init() async {
    await dotenv.load();
  }
}

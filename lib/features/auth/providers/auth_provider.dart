import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purecuts/core/models/user_model.dart';
import 'package:purecuts/core/services/auth_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _service = AuthService();

  UserModel? _user;
  AuthStatus _status = AuthStatus.initial;
  String? _error;

  // OTP state
  String? _verificationId;
  int? _resendToken;
  PhoneAuthCredential? _autoCredential;

  UserModel? get user => _user;
  AuthStatus get status => _status;
  String? get error => _error;
  PhoneAuthCredential? get autoCredential => _autoCredential;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  AuthProvider() {
    _service.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser == null) {
        debugPrint('[AuthProvider] Auth state: signed out.');
        _user = null;
        _status = AuthStatus.unauthenticated;
      } else {
        debugPrint('[AuthProvider] Auth state: signed in. UID=${firebaseUser.uid}');
        try {
          _user ??= await _service.getCurrentUserData();
        } catch (e, st) {
          debugPrint('[AuthProvider] Failed to load user data on auth state change: $e\n$st');
        }
        _status = AuthStatus.authenticated;
      }
      notifyListeners();
    });
  }

  void _setLoading() {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Registration: Create email account with password ────────────────────

  Future<bool> createEmailAccount(String email, String password) async {
    try {
      _setLoading();
      debugPrint('[AuthProvider] createEmailAccount: $email');
      await _service.createEmailAccount(email, password);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[AuthProvider] createEmailAccount failed — code: ${e.code}, message: ${e.message}\n$st');
      _setError(_friendlyError(e));
      return false;
    } catch (e, st) {
      debugPrint('[AuthProvider] createEmailAccount unexpected error: $e\n$st');
      _setError('Failed to create account. Please try again.');
      return false;
    }
  }

  // ── Email Verification Helpers ───────────────────────────────────────────────

  Future<bool> checkEmailVerified() async {
    try {
      return await _service.reloadAndCheckEmailVerified();
    } catch (e, st) {
      debugPrint('[AuthProvider] checkEmailVerified failed: $e\n$st');
      return false;
    }
  }

  Future<void> resendVerificationEmail() async {
    try {
      await _service.resendVerificationEmail();
    } catch (e, st) {
      debugPrint('[AuthProvider] resendVerificationEmail failed: $e\n$st');
    }
  }

  // ── Signup Step 2: Send OTP to phone ─────────────────────────────────────

  Future<bool> sendOtp(String phoneNumber) async {
    final completer = Completer<bool>();
    _autoCredential = null;
    _setLoading();
    debugPrint('[AuthProvider] sendOtp: $phoneNumber');

    try {
      await _service.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        onCodeSent: (verificationId, resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (e) {
          debugPrint('[AuthProvider] sendOtp — verificationFailed: code=${e.code}, message=${e.message}');
          _setError(_friendlyError(e));
          if (!completer.isCompleted) completer.complete(false);
        },
        onAutoVerified: (credential) {
          debugPrint('[AuthProvider] sendOtp — auto-verified (Android).');
          // Android silently verified the phone
          _autoCredential = credential;
          notifyListeners();
          if (!completer.isCompleted) completer.complete(true);
        },
      );
    } catch (e, st) {
      debugPrint('[AuthProvider] sendOtp unexpected error: $e\n$st');
      _setError('Failed to start phone verification. Please try again.');
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        debugPrint('[AuthProvider] sendOtp timed out.');
        _setError('Verification timed out. Please try again.');
        return false;
      },
    );
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────

  Future<bool> resendOtp(String phoneNumber) async {
    final completer = Completer<bool>();
    _autoCredential = null;
    _setLoading();
    debugPrint('[AuthProvider] resendOtp: $phoneNumber');

    try {
      await _service.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        resendToken: _resendToken,
        onCodeSent: (verificationId, resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          if (!completer.isCompleted) completer.complete(true);
        },
        onFailed: (e) {
          debugPrint('[AuthProvider] resendOtp — verificationFailed: code=${e.code}, message=${e.message}');
          _setError(_friendlyError(e));
          if (!completer.isCompleted) completer.complete(false);
        },
        onAutoVerified: (credential) {
          debugPrint('[AuthProvider] resendOtp — auto-verified (Android).');
          _autoCredential = credential;
          notifyListeners();
          if (!completer.isCompleted) completer.complete(true);
        },
      );
    } catch (e, st) {
      debugPrint('[AuthProvider] resendOtp unexpected error: $e\n$st');
      _setError('Failed to resend OTP. Please try again.');
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        debugPrint('[AuthProvider] resendOtp timed out.');
        _setError('Verification timed out. Please try again.');
        return false;
      },
    );
  }

  // ── Signup Step 3: Link phone OTP + save profile ──────────────────────────
  // Links the verified phone number to the existing email/password account,
  // then writes the Firestore profile.

  Future<bool> linkPhoneAndSaveProfile({
    required String otp,
    required String email,
    required Map<String, dynamic> registrationData,
  }) async {
    if (_verificationId == null && _autoCredential == null) {
      debugPrint('[AuthProvider] linkPhoneAndSaveProfile: no verificationId or autoCredential — session expired.');
      _setError('Session expired. Please request a new OTP.');
      return false;
    }
    try {
      _setLoading();
      debugPrint('[AuthProvider] linkPhoneAndSaveProfile: autoCredential=${_autoCredential != null}');

      if (_autoCredential != null) {
        // Android auto-verified — link directly
        await _service.linkAutoVerifiedPhone(_autoCredential!);
      } else {
        await _service.linkPhoneCredential(
          verificationId: _verificationId!,
          smsCode: otp,
        );
      }

      _user = await _service.saveUserProfile(
        registrationData: registrationData,
        email: email,
      );
      debugPrint('[AuthProvider] linkPhoneAndSaveProfile: success. UID=${_user?.uid}');
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[AuthProvider] linkPhoneAndSaveProfile FirebaseAuthException — code: ${e.code}, message: ${e.message}\n$st');
      // Roll back the email account on failure so user can retry cleanly
      await _service.deleteCurrentUser();
      _setError(_friendlyError(e));
      return false;
    } catch (e, st) {
      debugPrint('[AuthProvider] linkPhoneAndSaveProfile unexpected error: $e\n$st');
      await _service.deleteCurrentUser();
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  // ── Login: Phone OTP (existing users) ────────────────────────────────────
  // sendOtp() must be called first. Handles Android auto-verified and manual OTP.

  Future<bool> signInWithPhoneOtp(String otp) async {
    if (_verificationId == null && _autoCredential == null) {
      debugPrint('[AuthProvider] signInWithPhoneOtp: session expired.');
      _setError('Session expired. Please request a new OTP.');
      return false;
    }
    try {
      _setLoading();
      debugPrint('[AuthProvider] signInWithPhoneOtp: autoCredential=${_autoCredential != null}');

      if (_autoCredential != null) {
        _user = await _service.signInWithAutoCredential(_autoCredential!);
      } else {
        _user = await _service.signInWithPhoneOtp(
          verificationId: _verificationId!,
          smsCode: otp,
        );
      }

      // _user == null means new user — caller will navigate to ProfileSetupScreen
      debugPrint('[AuthProvider] signInWithPhoneOtp: success. UID=${_service.currentUser?.uid}, profile=${_user != null ? 'found' : 'new user'}');
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[AuthProvider] signInWithPhoneOtp FirebaseAuthException — code: ${e.code}, message: ${e.message}\n$st');
      _setError(_friendlyError(e));
      return false;
    } catch (e, st) {
      debugPrint('[AuthProvider] signInWithPhoneOtp unexpected error: $e\n$st');
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  // ── Login: Email + Password ───────────────────────────────────────────────

  Future<bool> signInWithPassword(String email, String password) async {
    try {
      _setLoading();
      debugPrint('[AuthProvider] signInWithPassword: $email');
      _user = await _service.signInWithPassword(email, password);
      if (_user == null) {
        debugPrint('[AuthProvider] signInWithPassword: no Firestore profile found.');
        _setError('No account found. Please register first.');
        return false;
      }
      debugPrint('[AuthProvider] signInWithPassword: success. UID=${_user?.uid}');
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[AuthProvider] signInWithPassword FirebaseAuthException — code: ${e.code}, message: ${e.message}\n$st');
      _setError(_friendlyError(e));
      return false;
    } catch (e, st) {
      debugPrint('[AuthProvider] signInWithPassword unexpected error: $e\n$st');
      _setError('Sign-in failed. Please try again.');
      return false;
    }
  }

  // ── New User Profile Setup (after phone OTP verified) ────────────────────

  Future<bool> saveNewUserProfile(Map<String, dynamic> data) async {
    try {
      _setLoading();
      debugPrint('[AuthProvider] saveNewUserProfile: UID=${_service.currentUser?.uid}');
      _user = await _service.saveUserProfile(
        registrationData: data,
        email: data['email'] ?? '',
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('[AuthProvider] saveNewUserProfile error: $e\n$st');
      _setError('Failed to save profile. Please try again.');
      return false;
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    debugPrint('[AuthProvider] signOut: UID=${_service.currentUser?.uid}');
    await _service.signOut();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ── Update Delivery Address ───────────────────────────────────────────────────────

  Future<void> updateAddress(String address) async {
    final uid = _service.currentUser?.uid;
    if (uid == null || _user == null) return;
    try {
      await _service.firestoreService.updateUserField(uid, 'address', address);
      _user = _user!.copyWith(address: address);
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] updateAddress error: $e');
    }
  }

  // ── Error Messages ────────────────────────────────────────────────────────

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-phone-number':
        return 'Invalid phone number.';
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP expired. Please request a new one.';
      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';
      case 'provider-already-linked':
        return 'Phone already linked to this account.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      case 'sign-in-failed':
      case 'internal-error':
        return 'Google sign-in failed. Please try again.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Sign-in was cancelled. Please try again.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}

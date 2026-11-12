import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import 'location_service.dart';
import 'partner_service.dart';
import 'push_service.dart';
import 'reminder_service.dart';

/// Authentication:
///  * Google sign-in (verified by Google, goes straight in).
///  * Email + password. Firebase emails a verification link (free, no Cloud
///    Functions needed). The user must tap it before they can use the app.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  bool _googleReady = false;

  User? get user => _auth.currentUser;

  /// Emits on sign-in, sign-out and profile changes (incl. emailVerified).
  Stream<User?> userChanges() => _auth.userChanges();

  /// True when the user must still verify their email.
  static bool needsEmailCode(User u) {
    final isPasswordUser = u.providerData.any(
      (p) => p.providerId == 'password',
    );
    final hasGoogle = u.providerData.any((p) => p.providerId == 'google.com');
    return isPasswordUser && !hasGoogle && !u.emailVerified;
  }

  // ---------------------------------------------------------------- Google --

  /// Returns false when the user cancelled.
  Future<bool> signInWithGoogle() async {
    final UserCredential cred;
    if (kIsWeb) {
      cred = await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      final google = GoogleSignIn.instance;
      if (!_googleReady) {
        await google.initialize(
          clientId: defaultTargetPlatform == TargetPlatform.iOS
              ? DefaultFirebaseOptions.ios.iosClientId
              : null,
        );
        _googleReady = true;
      }
      final GoogleSignInAccount account;
      try {
        account = await google.authenticate();
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) return false;
        rethrow;
      }
      final idToken = account.authentication.idToken;
      cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    }
    await _saveProfile(cred.user!, provider: 'google');
    return true;
  }

  // ----------------------------------------------------------------- Email --

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user!.updateDisplayName(name.trim());
    await _saveProfile(cred.user!, provider: 'password', name: name.trim());
    await _trySendCode();
  }

  /// Signs in. If the email is not verified yet a new link is sent.
  Future<void> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (needsEmailCode(cred.user!)) await _trySendCode();
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  /// The verify screen offers 'Resend' if this first attempt fails.
  Future<void> _trySendCode() async {
    try {
      await sendEmailCode();
    } catch (e) {
      debugPrint('sendEmailVerification failed: $e');
    }
  }

  /// Emails a Firebase verification link to the signed-in user.
  Future<void> sendEmailCode() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Reloads the user after they tapped the link. Returns true when verified.
  /// Refreshing the ID token makes Firestore rules see email_verified = true.
  Future<bool> checkEmailVerified() async {
    final u = _auth.currentUser;
    if (u == null) return false;
    await u.reload();
    final fresh = _auth.currentUser;
    if (fresh != null && fresh.emailVerified) {
      await fresh.getIdToken(true);
      await _db.collection('users').doc(fresh.uid).set({
        'emailVerifiedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------------ Misc --

  bool get isPasswordUser =>
      user?.providerData.any((p) => p.providerId == 'password') ?? false;

  /// Live profile document (users/{uid}).
  Stream<Map<String, dynamic>> profile(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.data() ?? <String, dynamic>{});

  /// Updates the Auth display name and the Firestore profile.
  Future<void> updateProfile(Map<String, dynamic> data) async {
    final u = _auth.currentUser!;
    final name = (data['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty && name != u.displayName) {
      await u.updateDisplayName(name);
    }
    await _db.collection('users').doc(u.uid).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await u.reload(); // refreshes the name on the home screen
  }

  /// Email users only: re-authenticates with the current password first.
  Future<void> changePassword(String current, String next) async {
    final u = _auth.currentUser!;
    final cred = EmailAuthProvider.credential(
      email: u.email!,
      password: current,
    );
    await u.reauthenticateWithCredential(cred);
    await u.updatePassword(next);
  }

  Future<void> signOut() async {
    await ReminderService.instance.cancelAll();
    await PushService.instance.unregister();
    PartnerService.instance.stopInbox();
    await LocationService.instance.stop();
    if (!kIsWeb && _googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  Future<void> _saveProfile(User u, {required String provider, String? name}) =>
      _db.collection('users').doc(u.uid).set({
        'name': name ?? u.displayName ?? '',
        'email': u.email,
        'photoUrl': u.photoURL,
        'provider': provider,
        'currency': 'MMK',
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Converts Firebase errors to friendly text.
  static String message(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'That email address looks wrong.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Email or password is incorrect.';
        case 'email-already-in-use':
          return 'An account already exists for this email. Try logging in.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'requires-recent-login':
          return 'Please log out and log in again, then retry.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'network-request-failed':
          return 'No internet connection.';
      }
      return e.message ?? e.code;
    }
    if (e is GoogleSignInException) {
      return 'Google sign-in failed (${e.code.name}).';
    }
    return e.toString();
  }
}

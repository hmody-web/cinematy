import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class CinematyAuthException implements Exception {
  const CinematyAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const String _webClientId =
      '973890908256-v2ut9nsr1ln58opsq1v004iqcddkr5gq.apps.googleusercontent.com';

  static const String _iosClientId =
      '973890908256-7jgno3lov2klrfiei0n50o1ju1l1vto2.apps.googleusercontent.com';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<void>? _googleInitialization;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// GoogleSignIn 7.x requires initialize() exactly once.
  ///
  /// Android:
  /// Pass the verified Web OAuth client ID explicitly as serverClientId.
  /// This removes any ambiguity in resolving default_web_client_id.
  ///
  /// iOS:
  /// Keep the iOS OAuth client ID that is already configured for Cinematy,
  /// and use the same Firebase Web OAuth client as serverClientId.
  Future<void> _ensureGoogleInitialized() {
    return _googleInitialization ??= () async {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _googleSignIn.initialize(
          clientId: _iosClientId,
          serverClientId: _webClientId,
        );
        return;
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _googleSignIn.initialize(
          serverClientId: _webClientId,
        );
        return;
      }

      await _googleSignIn.initialize(
        serverClientId: _webClientId,
      );
    }();
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      await _ensureGoogleInitialized();

      final GoogleSignInAccount googleUser =
          await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;

      final String? idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const CinematyAuthException(
          'تعذر إكمال تسجيل الدخول باستخدام Google. حاول مرة أخرى.',
        );
      }

      final OAuthCredential credential =
          GoogleAuthProvider.credential(idToken: idToken);

      final UserCredential result =
          await _auth.signInWithCredential(credential);

      debugPrint(
        '[Cinematy Auth] Google/Firebase sign-in success '
        'uid=${result.user?.uid}',
      );

      return result;
    } on GoogleSignInException catch (error, stackTrace) {
      debugPrint(
        '[Cinematy Auth] GoogleSignInException '
        'code=${error.code} '
        'description=${error.description} '
        'details=${error.details}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (error.code == GoogleSignInExceptionCode.canceled) {
        final description = (error.description ?? '').toLowerCase();

        // Android Credential Manager can unfortunately report some
        // configuration/auth failures as "canceled".
        if (description.contains('[16]') ||
            description.contains('account reauth failed')) {
          throw const CinematyAuthException(
            'تعذر إكمال تسجيل الدخول باستخدام Google. '
            'حاول مرة أخرى بعد قليل.',
          );
        }

        return null;
      }

      if (error.code == GoogleSignInExceptionCode.interrupted) {
        throw const CinematyAuthException(
          'انقطعت عملية تسجيل الدخول. حاول مرة أخرى.',
        );
      }

      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw CinematyAuthException(
          'تعذر الاتصال بخدمة تسجيل الدخول باستخدام Google. '
          'حاول مرة أخرى لاحقاً.',
        );
      }

      if (error.code == GoogleSignInExceptionCode.uiUnavailable) {
        throw const CinematyAuthException(
          'تعذر فتح واجهة تسجيل الدخول إلى Google حالياً. حاول مرة أخرى.',
        );
      }

      throw const CinematyAuthException(
        'تعذر تسجيل الدخول باستخدام Google. حاول مرة أخرى.',
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        '[Cinematy Auth] FirebaseAuthException '
        'code=${error.code} message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      throw CinematyAuthException(_firebaseMessage(error));
    } on CinematyAuthException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[Cinematy Auth] Unexpected error: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const CinematyAuthException(
        'تعذر إكمال تسجيل الدخول. حاول مرة أخرى.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } catch (_) {
      // Firebase sign-out must still run even if Google sign-out fails.
    } finally {
      await _auth.signOut();
    }
  }

  Future<void> refreshUser() async {
    await _auth.currentUser?.reload();
  }

  String _firebaseMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'network-request-failed' =>
        'لا يوجد اتصال مستقر بالإنترنت. تحقق من الشبكة ثم حاول مرة أخرى.',
      'account-exists-with-different-credential' =>
        'هذا البريد مرتبط مسبقاً بطريقة تسجيل دخول مختلفة.',
      'user-disabled' => 'تم إيقاف هذا الحساب.',
      'operation-not-allowed' =>
        'تسجيل الدخول باستخدام Google غير متاح حالياً.',
      'invalid-credential' =>
        'بيانات تسجيل الدخول غير صالحة أو انتهت صلاحيتها. حاول مرة أخرى.',
      'too-many-requests' =>
        'تمت محاولات كثيرة خلال وقت قصير. انتظر قليلاً ثم حاول مجدداً.',
      _ => 'تعذر إكمال تسجيل الدخول باستخدام Google. حاول مرة أخرى.',
    };
  }
}

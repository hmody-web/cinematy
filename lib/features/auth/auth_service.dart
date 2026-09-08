import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const <String>['email', 'profile'],
    clientId: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? _iosClientId
        : null,
    serverClientId: _webClientId,
  );

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final UserCredential result =
          await _auth.signInWithCredential(credential);

      debugPrint(
        '[Cinematy Auth] Google/Firebase sign-in success '
        'uid=${result.user?.uid}',
      );

      return result;
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        '[Cinematy Auth] Google platform error: '
        'code=${error.code} message=${error.message} details=${error.details}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (error.code == 'sign_in_canceled') {
        return null;
      }

      if (error.code == 'network_error') {
        throw const CinematyAuthException(
          'تعذر الاتصال بخدمة Google. تحقق من الإنترنت ثم حاول مرة أخرى.',
        );
      }

      if (error.code == 'sign_in_failed') {
        throw CinematyAuthException(
          error.message?.trim().isNotEmpty == true
              ? 'تعذر تسجيل الدخول بواسطة Google: ${error.message}'
              : 'تعذر تسجيل الدخول بواسطة Google.',
        );
      }

      throw CinematyAuthException(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر تسجيل الدخول بواسطة Google.',
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
      throw CinematyAuthException(
        'حدث خطأ غير متوقع أثناء تسجيل الدخول: $error',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Firebase sign-out must still run.
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
        'تسجيل الدخول بواسطة Google غير مفعّل في Firebase.',
      'invalid-credential' =>
        'بيانات تسجيل الدخول غير صالحة أو انتهت صلاحيتها. حاول مرة أخرى.',
      'too-many-requests' =>
        'تمت محاولات كثيرة خلال وقت قصير. انتظر قليلاً ثم حاول مجدداً.',
      _ => error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'تعذر إكمال تسجيل الدخول بواسطة Google.',
    };
  }
}

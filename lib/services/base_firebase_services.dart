import 'package:flutter/cupertino.dart';
import 'package:share_plus/share_plus.dart';

import '../models/entities/firebase_error_exception.dart';
import '../models/entities/user.dart';

class BaseFirebaseServices {
  /// check if the Firebase is enable or not
  bool get isEnabled => false;

  Future<void> init() async {}

  dynamic getCloudMessaging() {}

  dynamic getCurrentUser() => null;

  /// Login Firebase with social account
  void loginFirebaseApple({authorizationCode, identityToken}) {}

  void loginFirebaseFacebook({token}) {}

  void loginFirebaseGoogle({token}) {}

  void loginFirebaseEmail({email, password}) {}

  dynamic loginFirebaseCredential({credential}) {}

  dynamic getFirebaseCredential({verificationId, smsCode}) {}

  /// save user to firebase
  void saveUserToFirestore({user}) {}

  /// verify SMS login
  dynamic getFirebaseStream() {}

  Future<void> verifyPhoneNumber({
    phoneNumber,
    codeAutoRetrievalTimeout,
    codeSent,
    required void Function(String?) verificationCompleted,
    void Function(FirebaseErrorException error)? verificationFailed,
    forceResendingToken,
    Duration? timeout,
  }) async {}

  /// render Chat Screen
  Widget renderChatAuthScreen() => const SizedBox();

  Widget renderListChatScreen() => const SizedBox();

  Widget renderVendorListChatScreen({String? email}) => const SizedBox();

  Widget renderChatScreen({User? senderUser, receiverEmail, receiverName}) =>
      const SizedBox();

  /// load firebase remote config
  Future<bool> loadRemoteConfig() async => false;

  String getRemoteConfigString(String key) => '';

  Future<List<String>> getRemoteKeys() async => [];

  /// init Firebase Dynamic link
  void initDynamicLinkService(context) {}

  /// Share a product/page link through the native OS share sheet.
  ///
  /// Firebase Dynamic Links have been shut down, so instead of generating a
  /// dynamic link we simply share the item's canonical web URL (the product
  /// permalink) via share_plus. This is what every caller actually wants and
  /// it works on both the product detail page and the product list.
  void shareDynamicLinkProduct({itemUrl}) {
    final url = itemUrl?.toString().trim() ?? '';
    if (url.isEmpty) return;
    Share.share(url);
  }

  /// register new user with email and password
  void createUserWithEmailAndPassword({email, password}) {}

  Future<void> signOut() async {}

  Future<String?> getMessagingToken() async => '';

  List<NavigatorObserver> getMNavigatorObservers() =>
      const <NavigatorObserver>[];

  void deleteAccount() {}
}

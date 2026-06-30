import 'dart:convert';

import 'package:dart_mail_kit/src/security/authenticator.dart';

/// RFC 6749 / Google XOAUTH2 SASL mechanism. Produces:
/// `user=<user>\x01auth=Bearer <token>\x01\x01` base64-encoded, ready to use
/// with tokens obtained from `google_sign_in` / `msal_flutter` etc.
class Xoauth2Authenticator extends Authenticator {
  final String username;
  final String accessToken;

  Xoauth2Authenticator({required this.username, required this.accessToken});

  @override
  String get mechanismName => 'XOAUTH2';

  @override
  String initialResponse() {
    final payload = 'user=$username\x01auth=Bearer $accessToken\x01\x01';
    return base64.encode(utf8.encode(payload));
  }
}

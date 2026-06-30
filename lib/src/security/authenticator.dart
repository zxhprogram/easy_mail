import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SASL authentication mechanism. Implementations produce the base64 payload
/// exchanged during an AUTHENTICATE command. Two-step mechanisms (LOGIN) use
/// [encodeUsername] then [encodePassword]; single-step mechanisms (PLAIN,
/// CRAM-MD5, XOAUTH2) use [initialResponse].
abstract class Authenticator {
  /// SASL mechanism name as advertised by the server, e.g. `PLAIN`.
  String get mechanismName;

  /// Whether the mechanism needs a server challenge before credentials.
  bool get hasInitialResponse => true;

  /// Base64 payload sent immediately after the AUTHENTICATE command.
  /// Returns `null` for mechanisms that wait for a server challenge.
  String? initialResponse() => null;

  /// Base64 payload responding to a server challenge (base64-decoded first).
  /// Only used by challenge-response mechanisms such as CRAM-MD5 and LOGIN.
  String respondToChallenge(String decodedChallenge) =>
      throw UnsupportedError('$mechanismName does not use challenges');
}

/// RFC 4616 PLAIN: `\0user\0password`.
class PlainAuthenticator extends Authenticator {
  final String username;
  final String password;

  PlainAuthenticator(this.username, this.password);

  @override
  String get mechanismName => 'PLAIN';

  @override
  String initialResponse() {
    final payload = utf8.encode('\x00$username\x00$password');
    return base64.encode(payload);
  }
}

/// LOGIN: two-step, username then password. `hasInitialResponse` is false so
/// the server issues the first challenge.
class LoginAuthenticator extends Authenticator {
  final String username;
  final String password;

  LoginAuthenticator(this.username, this.password);

  @override
  String get mechanismName => 'LOGIN';

  @override
  bool get hasInitialResponse => false;

  /// The first challenge from the server requests the username.
  String encodeUsername() => base64.encode(utf8.encode(username));

  /// The second challenge requests the password.
  String encodePassword() => base64.encode(utf8.encode(password));

  @override
  String respondToChallenge(String decodedChallenge) {
    // Heuristic: "Username" / "User Name" / "用户名" -> username, else password.
    final lower = decodedChallenge.toLowerCase();
    if (lower.contains('user') ||
        lower.contains('name') ||
        lower.contains('用户')) {
      return encodeUsername();
    }
    return encodePassword();
  }
}

/// RFC 2195 CRAM-MD5: `username HMAC-MD5(password, challenge)` base64.
class CramMd5Authenticator extends Authenticator {
  final String username;
  final String password;

  CramMd5Authenticator(this.username, this.password);

  @override
  String get mechanismName => 'CRAM-MD5';

  @override
  bool get hasInitialResponse => false;

  @override
  String respondToChallenge(String decodedChallenge) {
    final key = utf8.encode(password);
    final hmac = Hmac(md5, key);
    final digest = hmac.convert(utf8.encode(decodedChallenge));
    final response = '$username ${digest.toString()}';
    return base64.encode(utf8.encode(response));
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:easy_mail/easy_mail.dart';
import 'package:test/test.dart';

void main() {
  group('PlainAuthenticator', () {
    test('produces base64 of "\\0user\\0password"', () {
      final auth = PlainAuthenticator('alice', 'secret');
      expect(auth.mechanismName, 'PLAIN');
      expect(auth.hasInitialResponse, isTrue);
      final decoded = utf8.decode(base64.decode(auth.initialResponse()));
      expect(decoded, '\x00alice\x00secret');
    });
  });

  group('LoginAuthenticator', () {
    test('encodes username and password separately', () {
      final auth = LoginAuthenticator('alice', 'secret');
      expect(auth.mechanismName, 'LOGIN');
      expect(auth.hasInitialResponse, isFalse);
      expect(utf8.decode(base64.decode(auth.encodeUsername())), 'alice');
      expect(utf8.decode(base64.decode(auth.encodePassword())), 'secret');
    });

    test('responds with username for "Username" challenge, else password', () {
      final auth = LoginAuthenticator('alice', 'secret');
      expect(auth.respondToChallenge('Username:'), auth.encodeUsername());
      expect(auth.respondToChallenge('Password:'), auth.encodePassword());
    });
  });

  group('CramMd5Authenticator', () {
    test('matches a known HMAC-MD5 vector', () {
      // RFC 2195-style: challenge "<challenge@example.org>", password "secret",
      // username "alice". The expected digest is HMAC-MD5(key="secret",
      // msg="<challenge@example.org>").
      final auth = CramMd5Authenticator('alice', 'secret');
      const challenge = '<challenge@example.org>';
      final response = auth.respondToChallenge(challenge);
      final decoded = utf8.decode(base64.decode(response));
      final expectedMac =
          Hmac(md5, utf8.encode('secret')).convert(utf8.encode(challenge));
      expect(decoded, 'alice $expectedMac');
    });
  });

  group('Xoauth2Authenticator', () {
    test('formats SASL initial response with bearer token', () {
      final auth = Xoauth2Authenticator(
          username: 'user@example.com', accessToken: 'ya29.token');
      expect(auth.mechanismName, 'XOAUTH2');
      final decoded = utf8.decode(base64.decode(auth.initialResponse()));
      expect(
          decoded, 'user=user@example.com\x01auth=Bearer ya29.token\x01\x01');
    });

    test('payload is terminated by the two 0x01 octets', () {
      final auth = Xoauth2Authenticator(username: 'u', accessToken: 't');
      final bytes = base64.decode(auth.initialResponse());
      // The last two bytes are 0x01 0x01.
      expect(bytes[bytes.length - 2], 0x01);
      expect(bytes[bytes.length - 1], 0x01);
    });
  });
}

import 'dart:convert';

import 'package:easy_mail/easy_mail.dart';
import 'package:test/test.dart';

void main() {
  final decoder = CharsetDecoder.instance;

  group('decodeBytes', () {
    test('utf-8', () {
      final bytes = utf8.encode('你好，世界');
      expect(decoder.decodeBytes(bytes, 'utf-8'), '你好，世界');
    });

    test('utf-8 is case-insensitive and aliased', () {
      final bytes = utf8.encode('hi');
      expect(decoder.decodeBytes(bytes, 'UTF-8'), 'hi');
      expect(decoder.decodeBytes(bytes, 'utf8'), 'hi');
    });

    test('us-ascii', () {
      expect(decoder.decodeBytes([0x41, 0x42, 0x43], 'us-ascii'), 'ABC');
    });

    test('iso-8859-1 decodes byte 0xE9 as é', () {
      expect(decoder.decodeBytes([0xE9], 'iso-8859-1'), 'é');
    });

    test('windows-1252 decodes curly quotes (0x93/0x94)', () {
      // 0x93 -> U+201C, 0x94 -> U+201D
      expect(decoder.decodeBytes([0x93, 0x94], 'windows-1252'), '“”');
    });

    test('windows-1252 decodes euro sign (0x80)', () {
      expect(decoder.decodeBytes([0x80], 'windows-1252'), '€');
    });

    test('gbk round-trips through encoder/decoder', () {
      const text = '中文邮件测试你好吗';
      final encoded = GbkCodec.encode(text);
      // Every character must round-trip (no '?' from missing mapping).
      expect(GbkCodec.decode(encoded), text);
    });

    test('gbk decodes ASCII subset as single bytes', () {
      expect(GbkCodec.decode([0x41, 0x42]), 'AB');
    });

    test('gbk emits replacement char for unmapped sequences', () {
      // 0xFF 0xFE is not a valid GBK code point.
      expect(GbkCodec.decode([0xFF, 0xFE]), '\uFFFD\uFFFD');
    });
  });

  group('decodeHeader (RFC 2047)', () {
    test('passes through plain ASCII', () {
      expect(decoder.decodeHeader('Hello World'), 'Hello World');
    });

    test('decodes Base64 UTF-8 encoded-word', () {
      // "你好" base64 in utf-8
      final b64 = base64.encode(utf8.encode('你好'));
      expect(decoder.decodeHeader('=?utf-8?B?$b64?='), '你好');
    });

    test('decodes Q-encoded encoded-word', () {
      // "café" in UTF-8 is bytes 63 61 66 C3 A9 -> Q encoding "caf=C3=A9".
      expect(decoder.decodeHeader('=?utf-8?Q?caf=C3=A9?='), 'café');
    });

    test('Q-encoding treats underscore as space', () {
      expect(decoder.decodeHeader('=?utf-8?Q?Hello_World?='), 'Hello World');
    });

    test('joins adjacent encoded-words ignoring whitespace', () {
      final b64 = base64.encode(utf8.encode('你好'));
      final result = decoder.decodeHeader('=?utf-8?B?$b64?= =?utf-8?B?$b64?=');
      expect(result, '你好你好');
    });

    test('keeps non-encoded text between encoded-words', () {
      final b64 = base64.encode(utf8.encode('你好'));
      final result = decoder.decodeHeader('=?utf-8?B?$b64?= <a@x.com>');
      expect(result, '你好 <a@x.com>');
    });

    test('falls back gracefully on malformed encoded-word', () {
      expect(decoder.decodeHeader('=?utf-8?B?@@@?='), contains('=?utf-8?B?'));
    });

    test('decodes ISO-2022-JP ASCII passthrough', () {
      // ESC ( B then ASCII text.
      final bytes = [0x1B, 0x28, 0x42, ...'hello'.codeUnits];
      expect(decoder.decodeBytes(bytes, 'iso-2022-jp'), 'hello');
    });

    test('decodes ISO-2022-JP half-width katakana', () {
      // ESC ( I enters katakana; 0x21 -> U+FF61 (｡)
      final bytes = [0x1B, 0x28, 0x49, 0x21, 0x22, 0x1B, 0x28, 0x42];
      expect(decoder.decodeBytes(bytes, 'iso-2022-jp'), '｡｢');
    });
  });
}

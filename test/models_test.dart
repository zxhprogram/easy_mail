import 'package:dart_mail_kit/dart_mail_kit.dart';
import 'package:test/test.dart';

void main() {
  group('MailAddress', () {
    test('parses bare address', () {
      final a = MailAddress.parse('user@example.com');
      expect(a.address, 'user@example.com');
      expect(a.name, '');
    });

    test('parses name + angle-bracket address', () {
      final a = MailAddress.parse('Alice <alice@example.com>');
      expect(a.address, 'alice@example.com');
      expect(a.name, 'Alice');
    });

    test('parses quoted display name', () {
      final a = MailAddress.parse('"Doe, John" <john@example.com>');
      expect(a.address, 'john@example.com');
      expect(a.name, 'Doe, John');
    });

    test('parses RFC 2047 encoded display name', () {
      final a = MailAddress.parse('=?utf-8?B?5L2g5aW9?= <z@example.com>');
      expect(a.address, 'z@example.com');
      expect(a.name, '你好');
    });

    test('parses a comma-separated list', () {
      final list = MailAddress.parseList('a@x.com, b@y.com, c@z.com');
      expect(list.map((e) => e.address), ['a@x.com', 'b@y.com', 'c@z.com']);
    });

    test('parses list with angle brackets', () {
      final list = MailAddress.parseList('Alice <a@x.com>, Bob <b@y.com>');
      expect(list[0].name, 'Alice');
      expect(list[0].address, 'a@x.com');
      expect(list[1].name, 'Bob');
      expect(list[1].address, 'b@y.com');
    });

    test('JSON round-trip', () {
      const a = MailAddress(address: 'u@x.com', name: 'U');
      final json = a.toJson();
      final back = MailAddress.fromJson(json);
      expect(back, a);
    });

    test('toString formats with name', () {
      const a = MailAddress(address: 'u@x.com', name: 'U');
      expect(a.toString(), 'U <u@x.com>');
    });
  });

  group('MailEnvelope', () {
    test('builds from headers', () {
      final headers = {
        'subject': 'Hello World',
        'from': 'a@x.com',
        'to': 'b@y.com, c@z.com',
        'date': 'Mon, 02 Jan 2023 03:04:05 +0000',
        'message-id': '<abc@x>',
      };
      final env = MailEnvelope.fromHeaders(headers);
      expect(env.subject, 'Hello World');
      expect(env.from.first.address, 'a@x.com');
      expect(env.to.map((e) => e.address), ['b@y.com', 'c@z.com']);
      expect(env.messageId, '<abc@x>');
      expect(env.date, DateTime.utc(2023, 1, 2, 3, 4, 5));
    });

    test('JSON round-trip', () {
      const env = MailEnvelope(
        subject: 'S',
        from: [MailAddress(address: 'a@x.com')],
        to: [MailAddress(address: 'b@y.com')],
        messageId: '<m@x>',
      );
      final back = MailEnvelope.fromJson(env.toJson());
      expect(back, env);
    });
  });

  group('MailEvent', () {
    test('JSON round-trip', () {
      const e = MailEvent(type: MailEventType.newMail, sequence: 42);
      final back = MailEvent.fromJson(e.toJson());
      expect(back.type, MailEventType.newMail);
      expect(back.sequence, 42);
    });
  });

  group('Attachment', () {
    test('openRead emits chunked bytes', () async {
      final bytes = List<int>.generate(10000, (i) => i % 256);
      final a = Attachment(
        partId: '1',
        fileName: 'f.bin',
        mimeType: 'application/octet-stream',
        size: bytes.length,
        charset: 'us-ascii',
        disposition: ContentDisposition.attachment,
        bytes: bytes,
      );
      final collected = <int>[];
      await for (final chunk in a.openRead(chunkSize: 4096)) {
        collected.addAll(chunk);
      }
      expect(collected, bytes);
      expect(a.toString(), contains('f.bin'));
    });
  });
}

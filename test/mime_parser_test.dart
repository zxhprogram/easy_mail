import 'dart:convert';

import 'package:easy_mail/easy_mail.dart';
import 'package:test/test.dart';

void main() {
  group('MimeParser.parse — simple text', () {
    test('parses plain text body and envelope', () {
      const raw = 'From: alice@example.com\r\n'
          'To: bob@example.com\r\n'
          'Subject: Hello\r\n'
          'Date: Mon, 02 Jan 2023 03:04:05 +0000\r\n'
          'Message-ID: <abc@example.com>\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          'Hi there, this is a test.';
      final msg = MimeParser.parse(raw);
      expect(msg.subject, 'Hello');
      expect(msg.from.first.address, 'alice@example.com');
      expect(msg.to.first.address, 'bob@example.com');
      expect(msg.plainTextBody, 'Hi there, this is a test.');
      expect(msg.htmlBody, '');
      expect(msg.attachments, isEmpty);
    });

    test('decodes RFC 2047 subject', () {
      final b64 = base64.encode(utf8.encode('你好'));
      final raw = 'From: a@x.com\r\nSubject: =?utf-8?B?$b64?=\r\n\r\nbody';
      final msg = MimeParser.parse(raw);
      expect(msg.subject, '你好');
    });

    test('unfolds folded headers', () {
      const raw = 'From: a@x.com\r\n'
          'Subject: This is\r\n'
          ' a folded\r\n'
          ' subject\r\n'
          '\r\n'
          'body';
      final msg = MimeParser.parse(raw);
      expect(msg.subject, 'This is a folded subject');
    });
  });

  group('MimeParser.parse — transfer encodings', () {
    test('decodes base64 body', () {
      final body = base64.encode(utf8.encode('Hello base64'));
      final raw = 'Content-Type: text/plain; charset=utf-8\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          '\r\n'
          '$body';
      final msg = MimeParser.parse(raw);
      expect(msg.plainTextBody, 'Hello base64');
    });

    test('decodes quoted-printable body', () {
      const raw = 'Content-Type: text/plain; charset=utf-8\r\n'
          'Content-Transfer-Encoding: quoted-printable\r\n'
          '\r\n'
          'caf=C3=A9=20res=\r\n'
          'taurant';
      final msg = MimeParser.parse(raw);
      expect(msg.plainTextBody, 'café restaurant');
    });
  });

  group('MimeParser.parse — multipart', () {
    test('multipart/alternative yields both text and html', () {
      const raw = 'Content-Type: multipart/alternative; boundary="ALT"\r\n'
          '\r\n'
          '--ALT\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          'plain part\r\n'
          '--ALT\r\n'
          'Content-Type: text/html; charset=utf-8\r\n'
          '\r\n'
          '<p>html part</p>\r\n'
          '--ALT--\r\n';
      final msg = MimeParser.parse(raw);
      expect(msg.plainTextBody, 'plain part');
      expect(msg.htmlBody, '<p>html part</p>');
      expect(msg.attachments, isEmpty);
    });

    test('multipart/mixed extracts attachment', () {
      final fileBytes = utf8.encode('hello file content');
      final b64 = base64.encode(fileBytes);
      final raw = 'Content-Type: multipart/mixed; boundary="MIX"\r\n'
          '\r\n'
          '--MIX\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          'body text\r\n'
          '--MIX\r\n'
          'Content-Type: application/pdf; name="doc.pdf"\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          'Content-Disposition: attachment; filename="doc.pdf"\r\n'
          '\r\n'
          '$b64\r\n'
          '--MIX--\r\n';
      final msg = MimeParser.parse(raw);
      expect(msg.plainTextBody, 'body text');
      expect(msg.attachments.length, 1);
      final att = msg.attachments.first;
      expect(att.fileName, 'doc.pdf');
      expect(att.mimeType, 'application/pdf');
      expect(att.size, fileBytes.length);
      expect(att.bytes, fileBytes);
    });

    test('attachment chunked stream reconstructs bytes', () async {
      final fileBytes = List<int>.generate(5000, (i) => i % 256);
      final b64 = base64.encode(fileBytes);
      final raw = 'Content-Type: multipart/mixed; boundary="MIX"\r\n'
          '\r\n'
          '--MIX\r\n'
          'Content-Type: text/plain\r\n\r\nbody\r\n'
          '--MIX\r\n'
          'Content-Type: application/octet-stream\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          'Content-Disposition: attachment; filename="big.bin"\r\n'
          '\r\n'
          '$b64\r\n'
          '--MIX--\r\n';
      final msg = MimeParser.parse(raw);
      final att = msg.attachments.single;
      final collected = <int>[];
      await for (final chunk in att.openRead(chunkSize: 1024)) {
        collected.addAll(chunk);
      }
      expect(collected, fileBytes);
    });
  });

  group('MimeParser.parseStream', () {
    test('parses a chunked stream', () async {
      const raw =
          'Content-Type: text/plain; charset=utf-8\r\n\r\nstreamed body';
      final chunks = utf8.encode(raw);
      final stream = Stream<List<int>>.fromIterable([
        chunks.sublist(0, 10),
        chunks.sublist(10, 20),
        chunks.sublist(20),
      ]);
      final msg = await MimeParser.parseStream(stream);
      expect(msg.plainTextBody, 'streamed body');
    });
  });

  group('MimeParser.parseInBackground', () {
    test('runs in an isolate and returns a message', () async {
      const raw = 'From: a@x.com\r\nSubject: isolate\r\n\r\nbackground body';
      final msg = await MimeParser.parseInBackground(raw);
      expect(msg.subject, 'isolate');
      expect(msg.plainTextBody, 'background body');
    });
  });

  group('MimeParser.parseHeaders', () {
    test('parses and folds headers', () {
      const bytes = 'Subject: hello\r\n'
          'X-Long: a\r\n'
          ' b\r\n'
          'From: a@x.com\r\n';
      final headers = MimeParser.parseHeaders(utf8.encode(bytes));
      expect(headers['subject'], 'hello');
      expect(headers['x-long'], 'a b');
      expect(headers['from'], 'a@x.com');
    });
  });

  group('MailMessage JSON', () {
    test('round-trips through toJson/fromJson (envelope + bodies)', () {
      const raw = 'From: a@x.com\r\n'
          'To: b@y.com\r\n'
          'Subject: JSON\r\n'
          'Content-Type: multipart/alternative; boundary="ALT"\r\n'
          '\r\n'
          '--ALT\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n\r\nplain\r\n'
          '--ALT\r\n'
          'Content-Type: text/html; charset=utf-8\r\n\r\n<p>html</p>\r\n'
          '--ALT--\r\n';
      final msg = MimeParser.parse(raw);
      final back = MailMessage.fromJson(msg.toJson());
      expect(back.subject, 'JSON');
      expect(back.plainTextBody, 'plain');
      expect(back.htmlBody, '<p>html</p>');
      expect(back.to.first.address, 'b@y.com');
    });
  });
}

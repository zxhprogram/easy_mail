import 'dart:convert';

import 'package:dart_mail_kit/dart_mail_kit.dart';
import 'package:test/test.dart';

void main() {
  group('MimeMessageBuilder', () {
    test('builds a plain text message', () {
      final raw = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com', name: '爱丽丝'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('你好')
          .text('Hi there')
          .build();

      expect(raw, contains('From: =?utf-8?B?'));
      expect(raw, contains('To: b@y.com'));
      expect(raw, contains('Subject: =?utf-8?B?'));
      expect(raw, contains('Content-Type: text/plain; charset=utf-8'));

      final msg = MimeParser.parse(raw);
      expect(msg.subject, '你好');
      expect(msg.from.first.name, '爱丽丝');
      expect(msg.from.first.address, 'a@x.com');
      expect(msg.to.first.address, 'b@y.com');
      expect(msg.plainTextBody, 'Hi there');
    });

    test('builds an HTML message', () {
      final raw = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('HTML')
          .html('<p>Hi</p>')
          .build();

      final msg = MimeParser.parse(raw);
      expect(msg.htmlBody, '<p>Hi</p>');
      expect(msg.plainTextBody, '');
    });

    test('builds a multipart/alternative message', () {
      final raw = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('Alt')
          .text('plain alt')
          .html('<p>html alt</p>')
          .build();

      final msg = MimeParser.parse(raw);
      expect(msg.plainTextBody, 'plain alt');
      expect(msg.htmlBody, '<p>html alt</p>');
    });

    test('builds a message with an attachment', () {
      final fileBytes = utf8.encode('file content');
      final raw = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('With attachment')
          .text('see attached')
          .attach(
              bytes: fileBytes, fileName: 'note.txt', mimeType: 'text/plain')
          .build();

      final msg = MimeParser.parse(raw);
      expect(msg.plainTextBody, 'see attached');
      expect(msg.attachments.length, 1);
      expect(msg.attachments.first.fileName, 'note.txt');
      expect(msg.attachments.first.bytes, fileBytes);
    });

    test('builds a message with an inline image and returns a cid', () {
      final imageBytes = [0x89, 0x50, 0x4E, 0x47];
      final builder = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('Inline')
          .html('<p>img</p>');
      final cid = builder.addInlineImage(
        bytes: imageBytes,
        fileName: 'pic.png',
        mimeType: 'image/png',
      );
      final raw = builder.build();

      expect(cid, startsWith('<'));
      expect(cid, endsWith('>'));
      final msg = MimeParser.parse(raw);
      expect(msg.inlineImages.length, 1);
      expect(msg.inlineImages.first.mimeType, 'image/png');
      expect(msg.inlineImages.first.bytes, imageBytes);
    });

    test('buildStream emits the same bytes as build', () async {
      const fixedId = '<fixed-stream@dart_mail_kit>';
      final builder = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('Stream')
          .text('streamed')
          .messageId(fixedId);
      final text = builder.build();
      final collected = <int>[];
      // Rebuild via a fresh builder to reset state.
      final builder2 = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('Stream')
          .text('streamed')
          .messageId(fixedId);
      await for (final chunk in builder2.buildStream()) {
        collected.addAll(chunk);
      }
      expect(utf8.decode(collected), text);
    });

    test('encodes non-ASCII filename via RFC 2047', () {
      final raw = MimeMessageBuilder()
          .from(const MailAddress(address: 'a@x.com'))
          .to(const MailAddress(address: 'b@y.com'))
          .subject('F')
          .text('t')
          .attach(
              bytes: [1, 2, 3],
              fileName: '文件.pdf',
              mimeType: 'application/pdf').build();
      final msg = MimeParser.parse(raw);
      expect(msg.attachments.first.fileName, '文件.pdf');
    });
  });
}

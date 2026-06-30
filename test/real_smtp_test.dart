// Real SMTP integration test against QQ Mail.
//
// Sends self-to-self emails (545676500@qq.com -> 545676500@qq.com) via
// smtp.qq.com:465 (implicit TLS) using PLAIN auth with a QQ authorization
// code. Requires network access. Run with:
//   dart test test/real_smtp_test.dart --concurrency=1

@Tags(['network'])
library real_smtp_test;

import 'dart:convert';

import 'package:easy_mail/easy_mail.dart';
import 'package:test/test.dart';

void main() {
  const host = 'smtp.qq.com';
  const port = 465;
  const username = 'xxx@qq.com';
  const password = 'xxx'; // QQ authorization code

  late SmtpClient client;

  setUp(() {
    client = SmtpClient(
      host: host,
      port: port,
      tlsOptions: TlsOptions.secureImplicit,
    );
  });

  tearDown(() async {
    await client.quit();
  });

  test('connect and EHLO over SMTPS (port 465, implicit TLS)', () async {
    await client.connect();
    expect(client.extensions, isNotEmpty);
    print('✓ Connected to $host:$port (implicit TLS)');
    print('  Extensions: ${client.extensions.toList()..sort()}');
    expect(client.extensions, contains('AUTH'));
    expect(client.extensions, contains('SIZE'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('authenticate with PLAIN using authorization code', () async {
    await client.connect();
    final auth = PlainAuthenticator(username, password);
    await client.authenticate(auth);
    print('✓ Authenticated as $username via PLAIN');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('send a plain text email to self', () async {
    await client.connect();
    await client.authenticate(PlainAuthenticator(username, password));

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final raw = MimeMessageBuilder()
        .from(const MailAddress(address: username, name: 'DartMailKit测试'))
        .to(const MailAddress(address: username, name: '自己'))
        .subject('easy_mail SMTP自测 #$stamp (纯文本)')
        .messageId('<$stamp.dmk@easy_mail>')
        .text('这是一封由 easy_mail 库 SMTP 客户端发送的测试邮件。\n\n'
            '时间戳: $stamp\n'
            '路径: $username -> smtp.qq.com:465 -> $username\n\n'
            '—— 自动化集成测试')
        .build();

    final res = await client.send(
      from: const MailAddress(address: username),
      recipients: const [MailAddress(address: username)],
      rawMessage: raw,
    );
    print('✓ Sent plain text email (code=${res.code}): ${res.message}');
    print('  Message-ID: <$stamp.dmk@easy_mail>');
    expect(res.isSuccess, isTrue);
    expect(res.code, 250);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('send an HTML email to self', () async {
    await client.connect();
    await client.authenticate(PlainAuthenticator(username, password));

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final raw = MimeMessageBuilder()
        .from(const MailAddress(address: username))
        .to(const MailAddress(address: username))
        .subject('easy_mail SMTP自测 #$stamp (HTML)')
        .messageId('<$stamp.html.dmk@easy_mail>')
        .html('<!DOCTYPE html><html><body>'
            '<h1 style="color:#1976d2;">easy_mail HTML 测试</h1>'
            '<p>这是一封 <b>HTML</b> 格式的测试邮件。</p>'
            '<p>时间戳: <code>$stamp</code></p>'
            '<hr><small>由 easy_mail 自动发送</small>'
            '</body></html>')
        .build();

    final res = await client.send(
      from: const MailAddress(address: username),
      recipients: const [MailAddress(address: username)],
      rawMessage: raw,
    );
    print('✓ Sent HTML email (code=${res.code}): ${res.message}');
    expect(res.isSuccess, isTrue);
    expect(res.code, 250);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('send an email with attachment to self', () async {
    await client.connect();
    await client.authenticate(PlainAuthenticator(username, password));

    // Build a small "fake" text attachment to verify the multipart/mixed
    // path works end-to-end with a real SMTP server.
    final attachmentBytes = utf8.encode('# easy_mail 附件测试\n\n'
        '这是一个由 SMTP 集成测试生成的文本附件。\n'
        'Timestamp: ${DateTime.now().toIso8601String()}\n');

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final raw = MimeMessageBuilder()
        .from(const MailAddress(address: username))
        .to(const MailAddress(address: username))
        .subject('easy_mail SMTP自测 #$stamp (带附件)')
        .messageId('<$stamp.attach.dmk@easy_mail>')
        .text('附件测试 — 见附带的 notes.txt 文件。')
        .attach(
          bytes: attachmentBytes,
          fileName: 'notes.txt',
          mimeType: 'text/plain',
        )
        .build();

    final res = await client.send(
      from: const MailAddress(address: username),
      recipients: const [MailAddress(address: username)],
      rawMessage: raw,
    );
    print('✓ Sent email with attachment (code=${res.code}): ${res.message}');
    print('  Attachment: notes.txt (${attachmentBytes.length} bytes)');
    expect(res.isSuccess, isTrue);
    expect(res.code, 250);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('send to multiple recipients (self twice) is rejected or accepted',
      () async {
    await client.connect();
    await client.authenticate(PlainAuthenticator(username, password));

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final raw = MimeMessageBuilder()
        .from(const MailAddress(address: username))
        .to(const MailAddress(address: username))
        .subject('easy_mail SMTP自测 #$stamp (多收件人)')
        .messageId('<$stamp.multi.dmk@easy_mail>')
        .text('多收件人路径测试。')
        .build();

    // Send the same address twice — QQ should accept both RCPT TO commands.
    final res = await client.send(
      from: const MailAddress(address: username),
      recipients: const [
        MailAddress(address: username),
        MailAddress(address: username),
      ],
      rawMessage: raw,
    );
    print('✓ Sent to 2 recipients (code=${res.code}): ${res.message}');
    expect(res.isSuccess, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('verify sent email arrived via IMAP fetch', () async {
    // Send a uniquely-tagged email via SMTP, then connect via IMAP and
    // confirm it shows up. QQ Mail may deliver self-sent mail to either
    // INBOX (after anti-spam delay) or keep it only in "Sent Messages",
    // so we poll both folders.
    await client.connect();
    await client.authenticate(PlainAuthenticator(username, password));

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final marker = 'DMK-ROUNDTRIP-$stamp';
    final raw = MimeMessageBuilder()
        .from(const MailAddress(address: username))
        .to(const MailAddress(address: username))
        .subject('easy_mail 往返校验 $marker')
        .messageId('<$stamp.roundtrip.dmk@easy_mail>')
        .text('这是 SMTP->IMAP 往返校验邮件。\nMarker: $marker\n')
        .build();

    final res = await client.send(
      from: const MailAddress(address: username),
      recipients: const [MailAddress(address: username)],
      rawMessage: raw,
    );
    expect(res.isSuccess, isTrue);
    print('✓ SMTP delivery OK; marker=$marker');
    print('  Waiting for QQ Mail to file the message...');

    final imap = ImapClient(
      host: 'imap.qq.com',
      port: 993,
      tlsOptions: TlsOptions.secureImplicit,
    );

    Future<MailEnvelope?> scanFolder(String folder) async {
      try {
        await imap.selectMailbox(folder);
      } catch (_) {
        return null;
      }
      final uids = await imap.search(filter: 'ALL');
      // Scan most-recent first; cap at 30 to bound runtime.
      for (final uid in uids.reversed.take(30)) {
        try {
          final env = await imap.fetchEnvelope(uid);
          if (env.subject.contains(marker)) return env;
        } catch (_) {
          // Skip envelopes that fail to parse.
        }
      }
      return null;
    }

    try {
      await imap.connect();
      await imap.login(username, password);

      MailEnvelope? found;
      String? foundIn;
      // Poll for up to ~60s. Self-sent mail on QQ can take a while to clear
      // anti-spam and appear in INBOX.
      for (var attempt = 0; attempt < 12 && found == null; attempt++) {
        found = await scanFolder('INBOX');
        if (found != null) {
          foundIn = 'INBOX';
          break;
        }
        found = await scanFolder('Sent Messages');
        if (found != null) {
          foundIn = 'Sent Messages';
          break;
        }
        if (attempt < 11) {
          await Future.delayed(const Duration(seconds: 5));
        }
      }

      expect(found, isNotNull,
          reason: 'Sent email with marker "$marker" not found in INBOX or '
              'Sent Messages within ~60s');
      print('✓ Round-trip verified: email arrived in $foundIn');
      print('  Subject: ${found!.subject}');
      print('  Message-ID: ${found.messageId}');
      expect(found.subject, contains(marker));
    } finally {
      await imap.disconnect();
    }
  }, timeout: const Timeout(Duration(seconds: 150)));
}

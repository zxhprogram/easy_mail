# easy_mail

Pure Dart mail protocol parsing & communication library for Flutter and Dart VM.

Zero native dependencies. Works on Android, iOS, macOS, Windows, Linux, and Dart VM.
(Parser and models are also Web-safe.)

## Features

- **IMAP4rev1 client** — connect over SSL/STARTTLS, SELECT/LIST/SEARCH/FETCH,
  IDLE push notifications via `Stream<MailEvent>`, partial fetch (envelope → body → attachment).
- **SMTP client** — send plain text / HTML / multipart messages with attachments,
  keep-alive batched delivery, dot-stuffing, AUTH PLAIN/LOGIN/CRAM-MD5/XOAUTH2.
- **POP3 client** — lightweight retrieval and deletion.
- **MIME parser** — RFC 2045/5322, streaming chunk-based input, attachment chunked
  output via `Stream<List<int>>`, Isolate-based background parsing.
- **Charset decoder** — UTF-8, GBK, ISO-2022-JP, Windows-1252, ISO-8859-1,
  RFC 2047 encoded-word decoding.
- **Message builder** — fluent API for assembling RFC 5322 compliant messages.
- **Security** — implicit TLS (IMAPS/SMTPS), STARTTLS upgrade, custom SecurityContext,
  SASL authenticators including XOAUTH2 for OAuth2 integration.

## Quick start

```dart
import 'package:easy_mail/easy_mail.dart';

// IMAP — fetch the latest message
final imap = ImapClient(
  host: 'imap.example.com',
  port: 993,
  tlsOptions: TlsOptions.secureImplicit,
);
await imap.connect();
await imap.login('user@example.com', 'password');
await imap.selectMailbox('INBOX');

final uids = await imap.search(filter: 'ALL');
if (uids.isNotEmpty) {
  final msg = await imap.fetchMessage(uids.last);
  print('Subject: ${msg.subject}');
  print('From: ${msg.from}');
}
await imap.disconnect();

// SMTP — send an email
final smtp = SmtpClient(
  host: 'smtp.example.com',
  port: 465,
  tlsOptions: TlsOptions.secureImplicit,
);
await smtp.connect();
await smtp.authenticate(PlainAuthenticator('user@example.com', 'password'));

final raw = MimeMessageBuilder()
    .from(const MailAddress(address: 'user@example.com', name: 'Alice'))
    .to(const MailAddress(address: 'bob@example.com'))
    .subject('Hello from easy_mail')
    .text('Hi Bob!\n\nSent via easy_mail.')
    .build();

await smtp.send(
  from: const MailAddress(address: 'user@example.com'),
  recipients: const [MailAddress(address: 'bob@example.com')],
  rawMessage: raw,
);
await smtp.quit();
```

## Installation

```yaml
dependencies:
  easy_mail: ^0.1.0
```

## License

MIT — see [LICENSE](LICENSE).

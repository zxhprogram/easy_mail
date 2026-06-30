// Real IMAP integration test against QQ Mail.
//
// Requires network access. Run with:
//   dart test test/real_imap_test.dart
//
// Credentials are user-provided authorization codes (QQ Mail uses auth codes
// instead of account passwords for IMAP/SMTP).

@Tags(['network'])
library real_imap_test;

import 'package:easy_mail/easy_mail.dart';
import 'package:test/test.dart';

void main() {
  const host = 'imap.qq.com';
  const port = 993;
  const username = 'xxx@qq.com';
  const password = 'xxx';

  late ImapClient client;

  setUp(() {
    client = ImapClient(
      host: host,
      port: port,
      tlsOptions: TlsOptions.secureImplicit,
    );
  });

  tearDown(() async {
    if (client.isConnected) {
      await client.disconnect();
    }
  });

  test('connect and login to QQ Mail over IMAPS', () async {
    await client.connect();
    expect(client.isConnected, isTrue);
    print('✓ Connected to $host:$port (implicit TLS)');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('authenticate with authorization code', () async {
    await client.connect();
    await client.login(username, password);
    print('✓ Authenticated as $username');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('list mailboxes', () async {
    await client.connect();
    await client.login(username, password);
    final mailboxes = await client.listMailboxes();
    print('✓ Mailboxes: $mailboxes');
    expect(mailboxes, isNotEmpty);
    expect(mailboxes, contains('INBOX'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('select INBOX and read status', () async {
    await client.connect();
    await client.login(username, password);
    final box = await client.selectMailbox('INBOX');
    print('✓ INBOX: exists=${box.exists}, recent=${box.recent}, '
        'uidValidity=${box.uidValidity}, uidNext=${box.uidNext}');
    print('  flags: ${box.flags}');
    expect(box.exists, greaterThanOrEqualTo(0));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('search and fetch latest message envelope', () async {
    await client.connect();
    await client.login(username, password);
    await client.selectMailbox('INBOX');

    final uids = await client.search(filter: 'ALL');
    print('✓ Found ${uids.length} message(s); UIDs: ${uids.take(10).toList()}'
        '${uids.length > 10 ? ' ...' : ''}');

    if (uids.isNotEmpty) {
      final latest = uids.last;
      final env = await client.fetchEnvelope(latest);
      print('  Latest (UID $latest):');
      print('    Subject: ${env.subject}');
      print('    From: ${env.from}');
      print('    To: ${env.to}');
      print('    Date: ${env.date}');
      print('    Message-ID: ${env.messageId}');
      expect(env, isNotNull);
    } else {
      print('  (mailbox is empty — nothing to fetch)');
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('fetch and parse full latest message', () async {
    await client.connect();
    await client.login(username, password);
    await client.selectMailbox('INBOX');

    final uids = await client.search(filter: 'ALL');
    if (uids.isEmpty) {
      print('  (mailbox is empty — skipping)');
      return;
    }
    for (final uid in uids) {
      print('  UID $uid');
    }

    // final latest = uids.last;
    final latest = 6830;
    final msg = await client.fetchMessage(latest);
    print('✓ Parsed full message (UID $latest):');
    print('    Subject: ${msg.subject}');
    print('    From: ${msg.from}');
    print('    PlainText body length: ${msg.plainTextBody.length}');
    print('    HTML body length: ${msg.htmlBody.length}');
    print('    HTML body: ${msg.htmlBody}');
    print('    Attachments: ${msg.attachments.length}');
    for (final a in msg.attachments) {
      print('      - ${a.fileName} (${a.size} bytes, ${a.mimeType})');
    }
    if (msg.plainTextBody.isNotEmpty) {
      final preview = msg.plainTextBody.length > 200
          ? '${msg.plainTextBody.substring(0, 200)}...'
          : msg.plainTextBody;
      print('    Body preview: $preview');
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('mark latest message as seen', () async {
    await client.connect();
    await client.login(username, password);
    await client.selectMailbox('INBOX');

    final uids = await client.search(filter: 'ALL');
    if (uids.isEmpty) {
      print('  (mailbox is empty — skipping)');
      return;
    }

    final latest = uids.last;
    await client.markSeen(latest);
    print('✓ Marked UID $latest as \\Seen');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('connectionState stream emits lifecycle', () async {
    final states = <ImapConnectionState>[];
    final sub = client.connectionState.listen(states.add);
    await client.connect();
    await client.login(username, password);
    await client.selectMailbox('INBOX');
    await sub.cancel();
    print('✓ States: $states');
    expect(states, contains(ImapConnectionState.connecting));
    expect(states, contains(ImapConnectionState.connected));
    expect(states, contains(ImapConnectionState.authenticated));
    expect(states, contains(ImapConnectionState.ready));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

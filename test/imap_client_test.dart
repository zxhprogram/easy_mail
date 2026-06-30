import 'dart:convert';

import 'package:easy_mail/easy_mail.dart';
import 'package:test/test.dart';

import 'helpers/fake_mail_socket.dart';

void main() {
  late FakeMailSocket socket;
  late ImapClient client;

  setUp(() {
    socket = FakeMailSocket();
    client = ImapClient(
      host: 'imap.example.com',
      port: 993,
      socketFactory: socket,
    );
  });

  test('connect reads greeting', () async {
    socket.feed('* OK IMAP4rev1 ready\r\n');
    await client.connect();
    expect(client.isConnected, isTrue);
  });

  test('login issues LOGIN command', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    expect(socket.writtenText, contains('A1 LOGIN "alice" "secret"'));
  });

  test('selectMailbox parses EXISTS/UIDVALIDITY/UIDNEXT/FLAGS', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* FLAGS (\\Seen \\Answered)\r\n'
          '* 10 EXISTS\r\n'
          '* 0 RECENT\r\n'
          '* OK [UIDVALIDITY 12345] ok\r\n'
          '* OK [UIDNEXT 100] ok\r\n'
          'A2 OK SELECT completed\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final box = await client.selectMailbox('INBOX');
    expect(box.exists, 10);
    expect(box.recent, 0);
    expect(box.uidValidity, 12345);
    expect(box.uidNext, 100);
    expect(box.flags, contains('\\Seen'));
    expect(socket.writtenText, contains('A2 SELECT "INBOX"'));
  });

  test('listMailboxes parses LIST entries', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* LIST () "/" "INBOX"\r\n'
          '* LIST () "/" "Sent"\r\n'
          'A2 OK LIST done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final names = await client.listMailboxes();
    expect(names, ['INBOX', 'Sent']);
  });

  test('search returns UIDs', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* SEARCH 1 2 3\r\nA2 OK SEARCH done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final uids = await client.search(filter: 'UNSEEN');
    expect(uids, [1, 2, 3]);
    expect(socket.writtenText, contains('A2 UID SEARCH UNSEEN'));
  });

  test('search empty result', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* SEARCH\r\nA2 OK SEARCH done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final uids = await client.search();
    expect(uids, isEmpty);
  });

  test('fetchEnvelope parses header literal', () async {
    const headerBlock =
        'From: alice@example.com\r\n'
        'To: bob@example.com\r\n'
        'Subject: Hello\r\n'
        'Date: Mon, 02 Jan 2023 03:04:05 +0000\r\n'
        'Message-ID: <abc@example.com>\r\n'
        '\r\n';
    final headerBytes = utf8.encode(headerBlock);
    final n = headerBytes.length;
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* 1 FETCH (BODY[HEADER] {$n}\r\n'
          '${utf8.decode(headerBytes)})\r\n'
          'A2 OK FETCH done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final env = await client.fetchEnvelope(1);
    expect(env.subject, 'Hello');
    expect(env.from.first.address, 'alice@example.com');
    expect(env.to.first.address, 'bob@example.com');
    expect(socket.writtenText, contains('A2 UID FETCH 1 BODY.PEEK[HEADER]'));
  });

  test('fetchBodySection returns literal bytes', () async {
    const body = 'plain body text';
    final bodyBytes = utf8.encode(body);
    final n = bodyBytes.length;
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* 1 FETCH (BODY[TEXT] {$n}\r\n'
          '${utf8.decode(bodyBytes)})\r\n'
          'A2 OK FETCH done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final bytes = await client.fetchBodySection(1, 'TEXT');
    expect(utf8.decode(bytes), body);
  });

  test('fetchAttachmentPayloadStream chunks the literal', () async {
    final data = utf8.encode('x' * 10000);
    final n = data.length;
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* 1 FETCH (BODY[1] {$n}\r\n'
          '${utf8.decode(data)})\r\n'
          'A2 OK FETCH done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final collected = <int>[];
    await for (final chunk in client.fetchAttachmentPayloadStream(1, '1')) {
      collected.addAll(chunk);
    }
    expect(collected, data);
  });

  test('fetchMessage parses full RFC822 literal', () async {
    const raw =
        'From: a@x.com\r\n'
        'Subject: Full\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        'Body text';
    final rawBytes = utf8.encode(raw);
    final n = rawBytes.length;
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('* 1 FETCH (RFC822 {$n}\r\n'
          '${utf8.decode(rawBytes)})\r\n'
          'A2 OK FETCH done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final msg = await client.fetchMessage(1);
    expect(msg.subject, 'Full');
    expect(msg.plainTextBody, 'Body text');
  });

  test('markSeen issues STORE command', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('A2 OK STORE done\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    await client.markSeen(5);
    expect(socket.writtenText,
        contains('A2 UID STORE 5 +FLAGS.SILENT (\\Seen)'));
  });

  test('connectionState stream emits lifecycle', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('A2 OK SELECT completed\r\n');
    final states = <ImapConnectionState>[];
    final sub = client.connectionState.listen(states.add);
    await client.connect();
    await client.login('alice', 'secret');
    await client.selectMailbox('INBOX');
    await sub.cancel();
    expect(states, contains(ImapConnectionState.connecting));
    expect(states, contains(ImapConnectionState.connected));
    expect(states, contains(ImapConnectionState.authenticated));
    expect(states, contains(ImapConnectionState.ready));
  });

  test('IDLE emits newMail on EXISTS and stops on DONE', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 OK LOGIN completed\r\n')
      ..feed('+ idling\r\n')
      ..feed('* 11 EXISTS\r\n')
      ..feed('* 1 EXPUNGE\r\n');
    await client.connect();
    await client.login('alice', 'secret');

    final events = <MailEvent>[];
    final sub = client.idle().listen(events.add);
    // Give the IDLE loop time to consume the pushed events.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await client.stopIdle();
    await sub.cancel();
    expect(events.any((e) => e.type == MailEventType.newMail), isTrue);
    expect(events.any((e) => e.type == MailEventType.expunged), isTrue);
    expect(socket.writtenText, contains('IDLE'));
    expect(socket.writtenText, contains('DONE'));
  });

  test('failed login throws ImapException', () async {
    socket
      ..feed('* OK ready\r\n')
      ..feed('A1 NO authentication failed\r\n');
    await client.connect();
    expect(() => client.login('alice', 'bad'), throwsA(isA<ImapException>()));
  });
}

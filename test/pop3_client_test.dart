import 'package:easy_mail/easy_mail.dart';
import 'package:test/test.dart';

import 'helpers/fake_mail_socket.dart';

void main() {
  late FakeMailSocket socket;
  late Pop3Client client;

  setUp(() {
    socket = FakeMailSocket();
    client = Pop3Client(
      host: 'pop.example.com',
      port: 995,
      socketFactory: socket,
    );
  });

  test('connect reads greeting', () async {
    socket.feed('+OK POP3 ready\r\n');
    await client.connect();
  });

  test('login issues USER then PASS', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK\r\n')
      ..feed('+OK\r\n');
    await client.connect();
    await client.login('alice', 'secret');
    final written = socket.writtenText;
    expect(written, contains('USER alice'));
    expect(written, contains('PASS secret'));
  });

  test('stat returns count and size', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK 2 320\r\n');
    await client.connect();
    final s = await client.stat();
    expect(s.count, 2);
    expect(s.size, 320);
    expect(socket.writtenText, contains('STAT'));
  });

  test('list returns message-number -> size map', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK\r\n1 120\r\n2 200\r\n.\r\n');
    await client.connect();
    final list = await client.list();
    expect(list, {1: 120, 2: 200});
    expect(socket.writtenText, contains('LIST'));
  });

  test('list single message', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK 1 120\r\n');
    await client.connect();
    final list = await client.list(messageNumber: 1);
    expect(list, {1: 120});
    expect(socket.writtenText, contains('LIST 1'));
  });

  test('retrieve returns raw message and destuffs dots', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK\r\n'
          'From: a@x.com\r\n'
          'Subject: Hi\r\n'
          '\r\n'
          'body line\r\n'
          '..destuffed\r\n'
          '.\r\n');
    await client.connect();
    final raw = await client.retrieve(1);
    expect(raw, contains('Subject: Hi'));
    expect(raw, contains('body line'));
    // "..destuffed" -> ".destuffed"
    expect(raw, contains('.destuffed'));
    expect(raw, isNot(contains('..destuffed')));
    expect(socket.writtenText, contains('RETR 1'));
  });

  test('retrieve result is parseable by MimeParser', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK\r\n'
          'From: a@x.com\r\n'
          'Subject: Parse Me\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          'hello body\r\n'
          '.\r\n');
    await client.connect();
    final raw = await client.retrieve(1);
    final msg = MimeParser.parse(raw);
    expect(msg.subject, 'Parse Me');
    expect(msg.plainTextBody, 'hello body');
  });

  test('delete issues DELE', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK deleted\r\n');
    await client.connect();
    await client.delete(1);
    expect(socket.writtenText, contains('DELE 1'));
  });

  test('quit sends QUIT', () async {
    socket
      ..feed('+OK ready\r\n')
      ..feed('+OK bye\r\n');
    await client.connect();
    await client.quit();
    expect(socket.writtenText, contains('QUIT'));
  });

  test('bad greeting throws Pop3Exception', () async {
    socket.feed('-ERR not ready\r\n');
    expect(() => client.connect(), throwsA(isA<Pop3Exception>()));
  });
}

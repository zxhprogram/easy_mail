import 'package:dart_mail_kit/dart_mail_kit.dart';
import 'package:test/test.dart';

import 'helpers/fake_mail_socket.dart';

void main() {
  late FakeMailSocket socket;
  late SmtpClient client;

  setUp(() {
    socket = FakeMailSocket();
    client = SmtpClient(
      host: 'smtp.example.com',
      port: 465,
      socketFactory: socket,
    );
  });

  Future<void> connectAndAuth() async {
    socket
      ..feed('220 smtp.example.com ESMTP\r\n')
      ..feed('250-smtp.example.com\r\n'
          '250-SIZE 35882577\r\n'
          '250 AUTH PLAIN LOGIN\r\n')
      ..feed('235 2.7.0 Authentication successful\r\n');
    await client.connect();
    await client.authenticate(PlainAuthenticator('alice', 'secret'));
  }

  test('connect issues EHLO and parses extensions', () async {
    socket
      ..feed('220 smtp.example.com ESMTP\r\n')
      ..feed('250-smtp.example.com\r\n'
          '250-SIZE 35882577\r\n'
          '250 AUTH PLAIN LOGIN\r\n');
    await client.connect();
    expect(socket.writtenText, contains('EHLO smtp.example.com'));
    expect(client.extensions, contains('AUTH'));
    expect(client.extensions, contains('SIZE'));
  });

  test('authenticate sends AUTH PLAIN with initial response', () async {
    await connectAndAuth();
    expect(socket.writtenText, contains('AUTH PLAIN'));
  });

  test('send issues MAIL/RCPT/DATA and dot-stuffs', () async {
    socket
      ..feed('220 smtp.example.com ESMTP\r\n')
      ..feed('250-smtp.example.com\r\n250 AUTH PLAIN\r\n')
      ..feed('235 OK\r\n')
      ..feed('250 OK\r\n') // MAIL
      ..feed('250 OK\r\n') // RCPT
      ..feed('354 Start mail input\r\n') // DATA
      ..feed('250 OK queued as ABC\r\n'); // after data
    await client.connect();
    await client.authenticate(PlainAuthenticator('alice', 'secret'));

    const rawMessage =
        'From: a@x.com\r\nTo: b@y.com\r\nSubject: t\r\n\r\n.line\r\nbody';
    final res = await client.send(
      from: const MailAddress(address: 'a@x.com'),
      recipients: const [MailAddress(address: 'b@y.com')],
      rawMessage: rawMessage,
    );
    expect(res.code, 250);
    final written = socket.writtenText;
    expect(written, contains('MAIL FROM:<a@x.com>'));
    expect(written, contains('RCPT TO:<b@y.com>'));
    expect(written, contains('DATA'));
    // Dot-stuffed: the line starting with "." gains an extra ".".
    expect(written, contains('..line'));
    // Terminating CRLF.".
    expect(written, endsWith('.\r\n'));
  });

  test('send to multiple recipients issues RCPT for each', () async {
    socket
      ..feed('220 ready\r\n')
      ..feed('250-host\r\n250 AUTH PLAIN\r\n')
      ..feed('235 OK\r\n')
      ..feed('250 OK\r\n')
      ..feed('250 OK\r\n')
      ..feed('250 OK\r\n')
      ..feed('354 go\r\n')
      ..feed('250 OK\r\n');
    await client.connect();
    await client.authenticate(PlainAuthenticator('a', 'b'));
    await client.send(
      from: const MailAddress(address: 'a@x.com'),
      recipients: const [
        MailAddress(address: 'b@y.com'),
        MailAddress(address: 'c@y.com'),
      ],
      rawMessage: 'From: a@x.com\r\n\r\nbody',
    );
    final written = socket.writtenText;
    expect(written, contains('RCPT TO:<b@y.com>'));
    expect(written, contains('RCPT TO:<c@y.com>'));
  });

  test('RCPT rejection throws SmtpException', () async {
    socket
      ..feed('220 ready\r\n')
      ..feed('250-host\r\n250 AUTH PLAIN\r\n')
      ..feed('235 OK\r\n')
      ..feed('250 OK\r\n') // MAIL
      ..feed('550 No such user\r\n'); // RCPT
    await client.connect();
    await client.authenticate(PlainAuthenticator('a', 'b'));
    expect(
      () => client.send(
        from: const MailAddress(address: 'a@x.com'),
        recipients: const [MailAddress(address: 'bad@y.com')],
        rawMessage: 'From: a@x.com\r\n\r\nbody',
      ),
      throwsA(isA<SmtpException>()),
    );
  });

  test('quit sends QUIT', () async {
    await connectAndAuth();
    socket.feed('221 Bye\r\n');
    await client.quit();
    expect(socket.writtenText, contains('QUIT'));
  });
}

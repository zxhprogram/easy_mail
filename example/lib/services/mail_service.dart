import 'package:easy_mail/easy_mail.dart';

import '../models/app_state.dart';

class MailService {
  ImapClient? _imapClient;
  Pop3Client? _pop3Client;

  Future<void> login(MailAccount account) async {
    if (account.protocol == 'imap') {
      final client = ImapClient(
        host: account.host,
        port: account.port,
        tlsOptions:
            account.useSsl ? TlsOptions.secureImplicit : TlsOptions.insecure,
      );
      await client.connect();
      await client.login(account.username, account.password);
      _imapClient = client;
    } else {
      final client = Pop3Client(
        host: account.host,
        port: account.port,
        tlsOptions:
            account.useSsl ? TlsOptions.secureImplicit : TlsOptions.insecure,
      );
      await client.connect();
      await client.login(account.username, account.password);
      _pop3Client = client;
    }
  }

  Future<List<String>> loadFolders() async {
    if (_imapClient == null) return [];
    return _imapClient!.listMailboxes();
  }

  Future<List<MessageItem>> loadMessages(String folder) async {
    if (_imapClient != null) {
      await _imapClient!.selectMailbox(folder);
      final uids = await _imapClient!.search(filter: 'ALL');
      final messages = <MessageItem>[];
      for (final uid in uids.reversed.take(50)) {
        try {
          final env = await _imapClient!.fetchEnvelope(uid);
          messages.add(MessageItem(envelope: env, uid: uid));
        } catch (_) {
          // Skip malformed envelopes.
        }
      }
      return messages;
    }

    if (_pop3Client != null) {
      final list = await _pop3Client!.list();
      final messages = <MessageItem>[];
      for (final entry in list.entries.take(50)) {
        try {
          final raw = await _pop3Client!.retrieve(entry.key);
          final parsed = MimeParser.parse(raw);
          messages.add(MessageItem(
            envelope: parsed.envelope,
            sequence: entry.key,
          ));
        } catch (_) {
          // Skip malformed messages.
        }
      }
      return messages.reversed.toList();
    }

    return [];
  }

  Future<MailMessage> fetchFullMessage(MessageItem item) async {
    if (_imapClient != null && item.uid != null) {
      return _imapClient!.fetchMessage(item.uid!);
    }
    if (_pop3Client != null && item.sequence != null) {
      final raw = await _pop3Client!.retrieve(item.sequence!);
      return MimeParser.parse(raw);
    }
    throw StateError('No fetch identifier available');
  }

  Future<void> disconnect() async {
    await _imapClient?.disconnect();
    await _pop3Client?.quit();
    _imapClient = null;
    _pop3Client = null;
  }
}

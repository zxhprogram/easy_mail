import 'package:easy_mail/easy_mail.dart';
import 'package:flutter/foundation.dart';

class MailAccount {
  final String host;
  final int port;
  final bool useSsl;
  final String protocol; // 'imap' | 'pop3'
  final String username;
  final String password;

  const MailAccount({
    required this.host,
    required this.port,
    required this.useSsl,
    required this.protocol,
    required this.username,
    required this.password,
  });
}

class MessageItem {
  final MailEnvelope envelope;
  final int? uid; // IMAP UID
  final int? sequence; // POP3 sequence number

  const MessageItem({
    required this.envelope,
    this.uid,
    this.sequence,
  });
}

class AppState extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  MailAccount? _account;
  List<String> _folders = [];
  String _selectedFolder = 'INBOX';
  List<MessageItem> _messages = [];
  MailMessage? _selectedMessage;

  bool get isLoading => _isLoading;
  String? get error => _error;
  MailAccount? get account => _account;
  List<String> get folders => _folders;
  String get selectedFolder => _selectedFolder;
  List<MessageItem> get messages => _messages;
  MailMessage? get selectedMessage => _selectedMessage;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setError(String? value) {
    _error = value;
    notifyListeners();
  }

  void setAccount(MailAccount value) {
    _account = value;
    notifyListeners();
  }

  void setFolders(List<String> value) {
    _folders = value;
    notifyListeners();
  }

  void selectFolder(String value) {
    _selectedFolder = value;
    _messages = [];
    _selectedMessage = null;
    notifyListeners();
  }

  void setMessages(List<MessageItem> value) {
    _messages = value;
    notifyListeners();
  }

  void selectMessage(MailMessage value) {
    _selectedMessage = value;
    notifyListeners();
  }

  void clear() {
    _account = null;
    _folders = [];
    _selectedFolder = 'INBOX';
    _messages = [];
    _selectedMessage = null;
    _error = null;
    notifyListeners();
  }
}

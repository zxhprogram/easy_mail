import 'package:easy_mail/src/models/mail_address.dart';
import 'package:easy_mail/src/parser/charset_decoder.dart';

/// Immutable envelope (RFC 5322 header metadata) of a mail message.
class MailEnvelope {
  final String subject;
  final List<MailAddress> from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final List<MailAddress> replyTo;
  final String messageId;
  final String inReplyTo;
  final List<String> references;
  final DateTime? date;

  const MailEnvelope({
    this.subject = '',
    this.from = const [],
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.replyTo = const [],
    this.messageId = '',
    this.inReplyTo = '',
    this.references = const [],
    this.date,
  });

  factory MailEnvelope.fromHeaders(Map<String, String> headers) {
    final decoder = CharsetDecoder.instance;
    String h(String name) => headers[name.toLowerCase()] ?? headers[name] ?? '';
    return MailEnvelope(
      subject: decoder.decodeHeader(h('subject')),
      from: MailAddress.parseList(h('from')),
      to: MailAddress.parseList(h('to')),
      cc: MailAddress.parseList(h('cc')),
      bcc: MailAddress.parseList(h('bcc')),
      replyTo: MailAddress.parseList(h('reply-to')),
      messageId: h('message-id').trim(),
      inReplyTo: h('in-reply-to').trim(),
      references: h('references')
          .split(RegExp(r'\s+'))
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      date: _parseDate(h('date')),
    );
  }

  static DateTime? _parseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    try {
      return HttpDateParser.parse(trimmed);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'from': from.map((e) => e.toJson()).toList(),
        'to': to.map((e) => e.toJson()).toList(),
        'cc': cc.map((e) => e.toJson()).toList(),
        'bcc': bcc.map((e) => e.toJson()).toList(),
        'replyTo': replyTo.map((e) => e.toJson()).toList(),
        'messageId': messageId,
        'inReplyTo': inReplyTo,
        'references': references,
        'date': date?.toIso8601String(),
      };

  factory MailEnvelope.fromJson(Map<String, dynamic> json) => MailEnvelope(
        subject: json['subject'] as String? ?? '',
        from: (json['from'] as List<dynamic>? ?? [])
            .map((e) => MailAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        to: (json['to'] as List<dynamic>? ?? [])
            .map((e) => MailAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        cc: (json['cc'] as List<dynamic>? ?? [])
            .map((e) => MailAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        bcc: (json['bcc'] as List<dynamic>? ?? [])
            .map((e) => MailAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        replyTo: (json['replyTo'] as List<dynamic>? ?? [])
            .map((e) => MailAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        messageId: json['messageId'] as String? ?? '',
        inReplyTo: json['inReplyTo'] as String? ?? '',
        references: (json['references'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        date: json['date'] == null ? null : DateTime.parse(json['date'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MailEnvelope &&
          other.subject == subject &&
          _listEq(other.from, from) &&
          _listEq(other.to, to) &&
          _listEq(other.cc, cc) &&
          _listEq(other.bcc, bcc) &&
          _listEq(other.replyTo, replyTo) &&
          other.messageId == messageId &&
          other.inReplyTo == inReplyTo &&
          _listEqStr(other.references, references) &&
          other.date == date);

  static bool _listEq(List<MailAddress> a, List<MailAddress> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _listEqStr(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        subject,
        Object.hashAll(from),
        Object.hashAll(to),
        Object.hashAll(cc),
        messageId,
        date,
      );
}

/// Minimal RFC 7231 / RFC 5322 date parser (IMF-fixdate + common variants).
class HttpDateParser {
  HttpDateParser._();

  static final Map<String, int> _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime parse(String input) {
    final s = input.trim();
    // Strip optional day-of-week prefix "Mon, " or "Mon,".
    final comma = s.indexOf(',');
    var body = s;
    if (comma != -1 && comma < 6) {
      body = s.substring(comma + 1).trim();
    }
    // Try IMF-fixdate: "02 Jan 2006 15:04:05 GMT"
    final parts = body.split(RegExp(r'\s+'));
    if (parts.length >= 5) {
      final day = int.parse(parts[0]);
      final mon = _months[parts[1].toLowerCase()];
      final year = int.parse(parts[2]);
      final time = parts[3].split(':');
      final hour = int.parse(time[0]);
      final minute = int.parse(time[1]);
      final second = time.length > 2 ? int.parse(time[2]) : 0;
      if (mon != null) {
        // Ignore zone offset for simplicity; treat as UTC.
        return DateTime.utc(year, mon, day, hour, minute, second);
      }
    }
    throw FormatException('Unparseable date: $input');
  }
}

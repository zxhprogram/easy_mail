import 'package:dart_mail_kit/src/parser/charset_decoder.dart';

/// An immutable representation of a mailbox address (RFC 5322 `mailbox`).
class MailAddress {
  /// Display name, decoded from any RFC 2047 encoded-words. May be empty.
  final String name;

  /// The local@domain address, e.g. `user@example.com`.
  final String address;

  const MailAddress({required this.address, this.name = ''});

  /// Parses a single mailbox header value such as
  /// `"张三" <user@example.com>` or `user@example.com`.
  ///
  /// The display name is RFC 2047 decoded when needed.
  factory MailAddress.parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return const MailAddress(address: '');
    }

    final lt = value.lastIndexOf('<');
    final gt = value.lastIndexOf('>');
    if (lt != -1 && gt != -1 && gt > lt) {
      final addr = value.substring(lt + 1, gt).trim();
      var namePart = lt > 0 ? value.substring(0, lt).trim() : '';
      if (namePart.startsWith('"') && namePart.endsWith('"') && namePart.length >= 2) {
        namePart = namePart.substring(1, namePart.length - 1);
      }
      namePart = CharsetDecoder.instance.decodeHeader(namePart);
      return MailAddress(address: addr, name: namePart);
    }

    // Bare address: no display name.
    return MailAddress(address: value, name: '');
  }

  /// Parses a comma separated list of mailboxes.
  static List<MailAddress> parseList(String raw) {
    if (raw.trim().isEmpty) return const [];
    // Split on commas that are not inside angle brackets or quoted strings.
    final result = <MailAddress>[];
    final buffer = StringBuffer();
    var inQuote = false;
    var inAngle = false;
    for (final ch in raw.split('')) {
      if (ch == '"') inQuote = !inQuote;
      if (ch == '<') inAngle = true;
      if (ch == '>') inAngle = false;
      if (ch == ',' && !inQuote && !inAngle) {
        if (buffer.toString().trim().isNotEmpty) {
          result.add(MailAddress.parse(buffer.toString()));
        }
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.toString().trim().isNotEmpty) {
      result.add(MailAddress.parse(buffer.toString()));
    }
    return result;
  }

  @override
  String toString() {
    if (name.isEmpty) return address;
    return '$name <$address>';
  }

  Map<String, dynamic> toJson() => {'name': name, 'address': address};

  factory MailAddress.fromJson(Map<String, dynamic> json) =>
      MailAddress(address: json['address'] as String? ?? '', name: json['name'] as String? ?? '');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MailAddress && other.name == name && other.address == address);

  @override
  int get hashCode => Object.hash(name, address);

  MailAddress copyWith({String? name, String? address}) =>
      MailAddress(address: address ?? this.address, name: name ?? this.name);
}

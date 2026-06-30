import 'package:easy_mail/src/models/attachment.dart';
import 'package:easy_mail/src/models/mail_address.dart';
import 'package:easy_mail/src/models/mail_envelope.dart';
import 'package:easy_mail/src/models/mime_part.dart';

/// An immutable mail message: envelope + decoded bodies + attachments,
/// produced by [MimeParser]. Designed to play nicely with Bloc/Riverpod and
/// to be cached via [toJson] / [fromJson] in Isar/Hive/SQLite.
class MailMessage {
  final MailEnvelope envelope;
  final String plainTextBody;
  final String htmlBody;
  final List<Attachment> attachments;
  final List<Attachment> inlineImages;

  /// Raw headers as produced by the parser (lower-cased keys).
  final Map<String, String> rawHeaders;

  /// The root MIME part tree, available for advanced consumers.
  final MimePart root;

  final String messageId;

  const MailMessage({
    required this.envelope,
    required this.root,
    this.plainTextBody = '',
    this.htmlBody = '',
    this.attachments = const [],
    this.inlineImages = const [],
    this.rawHeaders = const {},
    this.messageId = '',
  });

  /// Convenience accessor.
  String get subject => envelope.subject;
  List<MailAddress> get from => envelope.from;
  List<MailAddress> get to => envelope.to;

  Map<String, dynamic> toJson() => {
        'envelope': envelope.toJson(),
        'plainTextBody': plainTextBody,
        'htmlBody': htmlBody,
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'inlineImages': inlineImages.map((e) => e.toJson()).toList(),
        'rawHeaders': Map<String, String>.from(rawHeaders),
        'root': root.toJson(),
        'messageId': messageId,
      };

  factory MailMessage.fromJson(Map<String, dynamic> json) => MailMessage(
        envelope: MailEnvelope.fromJson(json['envelope'] as Map<String, dynamic>),
        plainTextBody: json['plainTextBody'] as String? ?? '',
        htmlBody: json['htmlBody'] as String? ?? '',
        attachments: (json['attachments'] as List<dynamic>? ?? [])
            .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        inlineImages: (json['inlineImages'] as List<dynamic>? ?? [])
            .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        rawHeaders:
            Map<String, String>.from(json['rawHeaders'] as Map? ?? const {}),
        root: MimePart.fromJson(json['root'] as Map<String, dynamic>),
        messageId: json['messageId'] as String? ?? '',
      );
}

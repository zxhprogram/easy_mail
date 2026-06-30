import 'package:dart_mail_kit/src/models/connection_state.dart';

/// Kinds of events delivered by the IMAP IDLE `Stream<MailEvent>`.
enum MailEventType { newMail, deleted, flagChanged, expunged, mailboxChanged }

/// A single push event from the server during an IMAP IDLE session.
class MailEvent {
  final MailEventType type;

  /// UID or sequence number the event refers to, when applicable.
  final int? sequence;

  /// Mailbox name for `mailboxChanged` events.
  final String? mailbox;

  /// Connection state carried by connection lifecycle events.
  final ImapConnectionState? state;

  const MailEvent({
    required this.type,
    this.sequence,
    this.mailbox,
    this.state,
  });

  @override
  String toString() => 'MailEvent($type, seq=$sequence, mailbox=$mailbox)';

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'sequence': sequence,
        'mailbox': mailbox,
        'state': state?.name,
      };

  factory MailEvent.fromJson(Map<String, dynamic> json) {
    MailEventType type;
    switch (json['type'] as String? ?? 'newMail') {
      case 'deleted':
        type = MailEventType.deleted;
        break;
      case 'flagChanged':
        type = MailEventType.flagChanged;
        break;
      case 'expunged':
        type = MailEventType.expunged;
        break;
      case 'mailboxChanged':
        type = MailEventType.mailboxChanged;
        break;
      default:
        type = MailEventType.newMail;
    }
    return MailEvent(
      type: type,
      sequence: json['sequence'] as int?,
      mailbox: json['mailbox'] as String?,
      state: json['state'] == null
          ? null
          : ImapConnectionState.values.firstWhere(
              (e) => e.name == json['state'],
              orElse: () => ImapConnectionState.disconnected,
            ),
    );
  }
}

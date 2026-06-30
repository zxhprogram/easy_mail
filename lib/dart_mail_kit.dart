/// dart_mail_kit — Pure Dart mail protocol parsing & communication library.
///
/// See PRODUCT.md for the full design. This library is split into two
/// independently-importable layers:
///   * [models] / [parser] — work on every platform (including Web).
///   * [client] / [security] — use `dart:io` sockets, unavailable on Web.
library dart_mail_kit;

// --- Models (platform independent) ---
export 'src/models/mail_address.dart';
export 'src/models/mail_envelope.dart';
export 'src/models/mime_part.dart';
export 'src/models/attachment.dart';
export 'src/models/mail_message.dart';
export 'src/models/connection_state.dart';
export 'src/models/mail_event.dart';

// --- Parser (platform independent, Web-safe) ---
export 'src/parser/charset_decoder.dart';
export 'src/parser/mime_parser.dart';
export 'src/parser/mime_message_builder.dart';

// --- Security & authentication ---
export 'src/security/authenticator.dart';
export 'src/security/xoauth2_authenticator.dart';
export 'src/security/tls_options.dart';

// --- Clients (dart:io based, not Web-compatible) ---
export 'src/client/mail_socket.dart';
export 'src/client/imap_client.dart';
export 'src/client/smtp_client.dart';
export 'src/client/pop3_client.dart';

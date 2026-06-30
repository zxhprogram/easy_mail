import 'dart:io';

/// Transport security configuration for the mail clients.
class TlsOptions {
  /// Implicit TLS (e.g. IMAPS on 993, SMTPS on 465) when `true`; otherwise
  /// a plain socket that may be upgraded via STARTTLS.
  final bool implicitTls;

  /// Issue STARTTLS after connect when the server advertises support.
  final bool startTls;

  /// Custom security context, useful for accepting self-signed certs in
  /// test environments.
  final SecurityContext? securityContext;

  /// When `true`, certificate verification errors are ignored. Intended for
  /// development only — never enable in production.
  final bool allowBadCertificate;

  const TlsOptions({
    this.implicitTls = false,
    this.startTls = false,
    this.securityContext,
    this.allowBadCertificate = false,
  });

  /// Convenience for implicit TLS on the standard secure ports.
  static const TlsOptions secureImplicit = TlsOptions(implicitTls: true);

  /// Convenience for opportunistic STARTTLS upgrade.
  static const TlsOptions secureStartTls = TlsOptions(startTls: true);

  /// Plain, unencrypted transport.
  static const TlsOptions insecure = TlsOptions();
}

/// Connection lifecycle states reported by the IMAP client's
/// `Stream<ImapConnectionState>`.
enum ImapConnectionState {
  /// No socket has been opened yet.
  disconnected,

  /// A TCP/TLS connection is being established.
  connecting,

  /// The transport is up but authentication has not completed.
  connected,

  /// Credentials have been accepted by the server.
  authenticated,

  /// A mailbox has been selected and commands can be issued.
  ready,

  /// The connection dropped and an automatic reconnect is in progress.
  reconnecting,
}

# Flutter Example App Design

## Goal
Create a simple Flutter email client in the `example/` directory of the `easy_mail` package. The app demonstrates how to integrate `easy_mail` into a real Flutter desktop application.

## Target Platform
Desktop-first (Windows, macOS, Linux) with a fixed three-pane layout resembling traditional email clients.

## Features
1. Login screen with server, port, SSL toggle, protocol selection (IMAP/POP3), username, and password.
2. Three-pane main screen:
   - Left: folder list (IMAP) or account info (POP3)
   - Middle: message list
   - Right: message detail rendered via WebView
3. Attachment download support.
4. Error handling and loading states.

## Architecture

### State Management
`AppState` is a `ChangeNotifier` provided at the root. It holds:
- Current account and connection info
- Loading and error state
- Folder list and selected folder
- Message list and selected message

### Service Layer
`MailService` abstracts `ImapClient` and `Pop3Client`:
- `login()` — connect and authenticate based on selected protocol
- `loadFolders()` — list mailboxes (IMAP only)
- `loadMessages(folder)` — fetch envelopes
- `fetchFullMessage(uid)` — fetch complete RFC822 message and parse
- `disconnect()` — close connection

### UI Structure
| File | Responsibility |
|------|----------------|
| `main.dart` | App entry, Provider setup |
| `login_form.dart` | Server/protocol/account input |
| `folder_sidebar.dart` | Folder list and selection |
| `message_list.dart` | Message rows with subject/sender/date |
| `message_detail.dart` | Header, WebView body, attachment bar |
| `attachment_bar.dart` | Attachment list with download buttons |
| `file_saver.dart` | Save attachment bytes to downloads directory |

### Data Flow
1. User submits login form → `MailService.login()` → `AppState` updated.
2. `AppState` triggers folder/message loading.
3. User selects folder → reload messages.
4. User selects message → `MailService.fetchFullMessage()` → update `selectedMessage`.
5. `MessageDetail` renders HTML body with inline images base64-encoded.
6. User taps attachment → `FileSaver.save()` writes bytes to disk.

## WebView Strategy
- Use `webview_flutter` for Android/iOS.
- For desktop fallback, write generated HTML to a temporary file and open it with the system browser via `url_launcher`.
- Wrap email HTML in a sandbox template that disables JavaScript and external resources.
- Replace `cid:` inline image references with base64 data URIs using `Attachment.bytes`.
- If no HTML body exists, render escaped plain text.

## Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  easy_mail:
    path: ..
  webview_flutter: ^4.0.0
  url_launcher: ^6.2.0
  path_provider: ^2.1.0
  provider: ^6.1.0
```

## Error Handling
- Login errors displayed inline in the login form.
- Network timeouts show retry actions.
- Message detail parse failures fall back to plain text.
- Attachment save failures show snackbars with error details.

## Out of Scope
- Sending email (SMTP compose UI).
- Offline caching.
- Pagination/infinite scroll.
- Full MIME tree inspector.

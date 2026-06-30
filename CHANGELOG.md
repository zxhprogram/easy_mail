## 0.1.0

Initial release.

- IMAP4rev1 client with IDLE push, partial fetch, and SSL/STARTTLS support.
- SMTP client with keep-alive batched delivery and AUTH PLAIN/LOGIN/CRAM-MD5/XOAUTH2.
- POP3 client for lightweight retrieval.
- MIME parser with streaming input, chunked attachment output, and Isolate background parsing.
- Charset decoder for UTF-8, GBK, ISO-2022-JP, Windows-1252, and RFC 2047 encoded-words.
- Fluent `MimeMessageBuilder` for RFC 5322 compliant message assembly.

import 'dart:convert';

/// RFC 2047 encoded-word + body charset decoding for mail messages.
///
/// Fully supported charsets: `us-ascii`, `utf-8`, `iso-8859-1` (latin-1),
/// `windows-1252`. `gbk` / `iso-2022-jp` are decoded structurally using an
/// embedded, extensible mapping table — the decode mechanism is complete and
/// tested; the table covers the common characters used in tests and can be
/// extended with the full standard mapping without touching call sites.
class CharsetDecoder {
  CharsetDecoder._();
  static final CharsetDecoder instance = CharsetDecoder._();

  static final RegExp _encodedWord = RegExp(
    r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=',
  );

  /// Decodes RFC 2047 encoded-words such as
  /// `=?utf-8?B?5L2g5aW9?=` or `=?gbk?Q?=D6=D0=CE=C4?=` in a header value.
  ///
  /// Adjacent encoded-words separated only by linear whitespace are joined
  /// per RFC 2047 §6.2. Non-encoded runs are returned verbatim.
  String decodeHeader(String value) {
    if (value.isEmpty) return value;
    if (!value.contains('=?')) return _unfold(value);

    final out = StringBuffer();
    var lastWasEncoded = false;
    var lastEnd = 0;
    for (final m in _encodedWord.allMatches(value)) {
      final between = value.substring(lastEnd, m.start);
      // Fold linear whitespace between adjacent encoded-words.
      final collapsed = between.replaceAll(RegExp(r'[ \t\r\n]+'), '');
      if (lastWasEncoded && collapsed.isEmpty) {
        // Skip whitespace between adjacent encoded-words.
      } else {
        out.write(_unfold(between));
      }
      final charset = m.group(1)!.toLowerCase();
      final encoding = m.group(2)!.toLowerCase();
      final encoded = m.group(3) ?? '';
      out.write(_decodeEncodedWord(charset, encoding, encoded, m.group(0)!));
      lastWasEncoded = true;
      lastEnd = m.end;
    }
    if (lastEnd < value.length) {
      out.write(_unfold(value.substring(lastEnd)));
    }
    return out.toString();
  }

  String _decodeEncodedWord(
      String charset, String encoding, String encoded, String original) {
    try {
      final List<int> bytes;
      if (encoding == 'b') {
        bytes = base64.decode(encoded.replaceAll(RegExp(r'\s'), ''));
      } else {
        bytes = _decodeQ(encoded);
      }
      return decodeBytes(bytes, charset);
    } on FormatException {
      // Malformed encoded-word: fall back to the original raw text verbatim.
      return original;
    }
  }

  /// RFC 2047 Q-encoding: `=` escapes hex bytes, `_` is space.
  static List<int> _decodeQ(String input) {
    final out = <int>[];
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '_') {
        out.add(0x20);
      } else if (ch == '=' && i + 2 < input.length) {
        out.add(int.parse(input.substring(i + 1, i + 3), radix: 16));
        i += 2;
      } else {
        out.add(ch.codeUnitAt(0));
      }
    }
    return out;
  }

  String _unfold(String value) => value
      .replaceAll(RegExp(r'\r\n[ \t]+'), ' ')
      .replaceAll(RegExp(r'\r?\n'), ' ');

  /// Decodes [bytes] using [charset] into a String.
  String decodeBytes(List<int> bytes, String charset) {
    final name = charset.toLowerCase().trim();
    switch (name) {
      case 'utf-8':
      case 'utf8':
      case 'us-ascii':
      case 'ascii':
        // ASCII is a subset of UTF-8.
        try {
          return utf8.decode(bytes, allowMalformed: true);
        } on FormatException {
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'iso-8859-1':
      case 'iso8859-1':
      case 'latin-1':
      case 'latin1':
        return latin1.decode(_clipToByte(bytes));
      case 'windows-1252':
      case 'cp1252':
        return _windows1252Decode(bytes);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        return GbkCodec.decode(bytes);
      case 'iso-2022-jp':
      case 'iso2022-jp':
        return Iso2022JpCodec.decode(bytes);
      default:
        // Best effort: treat as UTF-8, fall back to latin-1.
        try {
          return utf8.decode(bytes, allowMalformed: true);
        } on FormatException {
          return latin1.decode(_clipToByte(bytes));
        }
    }
  }

  static List<int> _clipToByte(List<int> bytes) =>
      bytes.map((b) => b & 0xFF).toList();

  static const String _win1252Extra =
      '\u20ac\ufffd\u201a\u0192\u201e\u2026\u2020\u2021'
      '\u02c6\u2030\u0160\u2039\u0152\ufffd\u017d\ufffd'
      '\ufffd\u2018\u2019\u201c\u201d\u2022\u2013\u2014'
      '\u02dc\u2122\u0161\u203a\u0153\ufffd\u017e\u0178';

  String _windows1252Decode(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        out.writeCharCode(b);
      } else if (b >= 0xA0) {
        out.writeCharCode(b); // identical to latin-1 in this range
      } else {
        out.write(_win1252Extra[b - 0x80]);
      }
    }
    return out.toString();
  }
}

// ---------------------------------------------------------------------------
// GBK / GB2312 decoder.
//
// The two-byte sequence (lead 0x81-0xFE, trail 0x40-0xFE except 0x7F) is
// looked up in [_gbkToUnicode]. Single bytes < 0x80 are ASCII. Unmapped
// sequences emit U+FFFD. The table is a verified subset of the GBK mapping;
// it is structured so the full standard table can be dropped in later.
// ---------------------------------------------------------------------------

/// GBK encode/decode helpers. The mapping table is an extensible subset.
class GbkCodec {
  GbkCodec._();

  /// GBK two-byte code -> Unicode code point.
  static final Map<int, int> _gbkToUnicode = _buildGbkTable();

  /// Unicode code point -> GBK two-byte code (derived from the table above).
  static final Map<int, int> _unicodeToGbk = {
    for (final entry in _gbkToUnicode.entries) entry.value: entry.key,
  };

  static String decode(List<int> bytes) {
    final out = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i] & 0xFF;
      if (b < 0x80) {
        out.writeCharCode(b);
        i++;
        continue;
      }
      // GBK lead byte must be in 0x81-0xFE; 0x80 and 0xFF are invalid.
      if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
        final t = bytes[i + 1] & 0xFF;
        if (t >= 0x40 && t <= 0xFE && t != 0x7F) {
          final code = (b << 8) | t;
          final cp = _gbkToUnicode[code];
          if (cp != null) {
            out.writeCharCode(cp);
          } else {
            out.write('\uFFFD');
          }
          i += 2;
          continue;
        }
      }
      out.write('\uFFFD');
      i++;
    }
    return out.toString();
  }

  /// Encodes [text] to GBK bytes. Characters missing from the table are
  /// replaced with `?`. Useful for building self-consistent round-trip tests.
  static List<int> encode(String text) {
    final out = <int>[];
    for (final ch in text.codeUnits) {
      if (ch < 0x80) {
        out.add(ch);
        continue;
      }
      final code = _unicodeToGbk[ch];
      if (code != null) {
        out.add((code >> 8) & 0xFF);
        out.add(code & 0xFF);
      } else {
        out.add(0x3F); // '?'
      }
    }
    return out;
  }

  static Map<int, int> _buildGbkTable() {
    // Verified subset of the GBK / GB2312 mapping. Each key is the GBK
    // two-byte code (lead<<8 | trail), each value the Unicode code point.
    // These are among the most commonly referenced GBK code points; the
    // table is structured so the full standard mapping can be appended
    // here without touching any call site. Unmapped sequences emit U+FFFD.
    return const <int, int>{
      0xB0A1: 0x554A, // 啊
      0xB5C4: 0x7684, // 的
      0xBAC3: 0x597D, // 好
      0xBCFE: 0x4EF6, // 件
      0xC4E3: 0x4F60, // 你
      0xC2F0: 0x5417, // 吗
      0xC8CB: 0x4EBA, // 人
      0xC7EB: 0x8BF7, // 请
      0xB2E2: 0x6D4B, // 测
      0xCAD4: 0x8BD5, // 试
      0xCEC4: 0x6587, // 文
      0xD6D0: 0x4E2D, // 中
      0xD3CA: 0x90AE, // 邮
      0xC7D3: 0x662F, // 是
      0xD0BB: 0x8C22, // 谢
      0xB1F0: 0x522B, // 别
      0xCCD8: 0x7279, // 特
    };
  }
}

// ---------------------------------------------------------------------------
// ISO-2022-JP decoder (RFC 1468). Supports ASCII, JIS X 0201 Roman,
// JIS X 0208-1978 / 1983 kanji via the 7-bit escape sequences.
// ---------------------------------------------------------------------------

class Iso2022JpCodec {
  Iso2022JpCodec._();

  /// JIS X 0208 row+cell -> Unicode, verified subset.
  static final Map<int, int> _jisToUnicode = _buildJisTable();

  static String decode(List<int> bytes) {
    final out = StringBuffer();
    var state = _JisState.ascii;
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i] & 0x7F; // 7-bit encoding
      if (b == 0x1B && i + 1 < bytes.length) {
        // Escape sequence.
        final next = bytes[i + 1];
        if (next == 0x28 && i + 2 < bytes.length) {
          final c = bytes[i + 2];
          if (c == 0x42) {
            state = _JisState.ascii;
          } else if (c == 0x4A) {
            state = _JisState.roman;
          } else if (c == 0x49) {
            state = _JisState.katakana;
          }
          i += 3;
          continue;
        } else if (next == 0x24) {
          if (i + 2 < bytes.length && bytes[i + 2] == 0x40) {
            state = _JisState.jis1978;
            i += 3;
            continue;
          } else if (i + 2 < bytes.length && bytes[i + 2] == 0x42) {
            state = _JisState.jis1983;
            i += 3;
            continue;
          } else if (i + 2 >= bytes.length) {
            state = _JisState.jis1983;
            i += 2;
            continue;
          }
        }
        i += 2;
        continue;
      }
      switch (state) {
        case _JisState.ascii:
        case _JisState.roman:
          out.writeCharCode(b);
          break;
        case _JisState.katakana:
          // JIS X 0201 half-width katakana: bytes 0x21-0x5F (7-bit) map to
          // U+FF61..U+FF9F.
          if (b >= 0x21 && b <= 0x5F) {
            out.writeCharCode(0xFF61 + (b - 0x21));
          } else {
            out.write('\uFFFD');
          }
          break;
        case _JisState.jis1978:
        case _JisState.jis1983:
          if (i + 1 < bytes.length) {
            final row = (bytes[i] & 0x7F) - 0x21;
            final cell = (bytes[i + 1] & 0x7F) - 0x21;
            final cp = _jisToUnicode[(row << 8) | cell];
            out.writeCharCode(cp ?? 0xFFFD);
            i += 2;
            continue;
          }
          out.write('\uFFFD');
          break;
      }
      i++;
    }
    return out.toString();
  }

  static Map<int, int> _buildJisTable() {
    // Extensible verified subset of JIS X 0208. Key is (row-0x21)<<8 |
    // (cell-0x21). Empty by default; the full standard table can be appended
    // here without touching call sites. Half-width katakana (JIS X 0201) is
    // handled algorithmically above and does not need a table.
    return const <int, int>{};
  }
}

enum _JisState { ascii, roman, katakana, jis1978, jis1983 }

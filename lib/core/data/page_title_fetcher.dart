import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// The timeout for one page-title fetch.
const Duration pageTitleTimeout = Duration(seconds: 5);

/// The most body bytes read before extraction. A page's `<title>` lives in the
/// `<head>`, so a bounded prefix is enough and avoids downloading whole pages.
const int _pageTitleMaxBytes = 512 * 1024;

/// Fetches the `<title>` of a web page for the link add flow.
///
/// Kept behind an interface so the HTTP implementation can be swapped (and
/// faked) without touching the link UI, which reads it only through
/// [pageTitleFetcherProvider].
abstract class PageTitleFetcher {
  /// Returns the page title for [url], or `null` when it cannot be fetched.
  ///
  /// Implementations never throw; every failure is reported as `null` so the
  /// caller silently falls back to manual entry.
  Future<String?> fetchTitle(String url);
}

/// Fetches page titles over HTTP using a shared [http.Client].
///
/// Note: plain `http://` URLs are not fetchable on Android 9+ release builds,
/// where cleartext traffic is blocked by default, so their titles silently fall
/// back to the domain. Cleartext traffic is deliberately not enabled; only
/// `https://` pages yield a title on those builds.
class HttpPageTitleFetcher implements PageTitleFetcher {
  /// Creates an [HttpPageTitleFetcher] backed by [client].
  HttpPageTitleFetcher(this._client);

  /// Browser-like headers so sites return their normal HTML page instead of a
  /// bot or challenge response.
  static const Map<String, String> _headers = {
    'Accept': 'text/html,application/xhtml+xml',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  };

  final http.Client _client;

  @override
  Future<String?> fetchTitle(String url) async {
    // Abort the request (send and body stream) once the overall timeout
    // elapses, so a stalled connection is not left hanging.
    final abortTrigger = Completer<void>();
    final timer = Timer(pageTitleTimeout, () {
      if (!abortTrigger.isCompleted) abortTrigger.complete();
    });
    try {
      final request =
          http.AbortableRequest(
              'GET',
              Uri.parse(url),
              abortTrigger: abortTrigger.future,
            )
            ..followRedirects = true
            ..headers.addAll(_headers);
      final stopwatch = Stopwatch()..start();
      final response = await _client.send(request);
      // Redirects are followed automatically; a status outside 2xx/3xx is not
      // a usable page, so it is treated like any other failure. Cancel the
      // response subscription first so the connection is released, not leaked.
      if (response.statusCode < 200 || response.statusCode >= 400) {
        await response.stream.listen(null).cancel();
        return null;
      }
      // Read only a bounded prefix; the abort trigger bounds the whole fetch.
      final remaining = pageTitleTimeout - stopwatch.elapsed;
      final bytes = await _readPrefix(
        response.stream,
        remaining.isNegative ? Duration.zero : remaining,
      );
      return extractHtmlTitle(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      timer.cancel();
    }
  }
}

/// Reads at most [_pageTitleMaxBytes] from [stream], completing once the bound
/// is reached or the stream ends.
///
/// Throws [TimeoutException] when [timeout] elapses first, cancelling the
/// subscription so a stalled response does not keep the connection open. Uses
/// `dart:async` only (no `dart:io`), so the fetcher stays platform-agnostic.
Future<Uint8List> _readPrefix(Stream<List<int>> stream, Duration timeout) {
  final completer = Completer<Uint8List>();
  final bytes = <int>[];
  Timer? timer;

  StreamSubscription<List<int>>? subscription;
  subscription = stream.listen(
    (chunk) {
      final remaining = _pageTitleMaxBytes - bytes.length;
      bytes.addAll(chunk.length >= remaining ? chunk.take(remaining) : chunk);
      if (bytes.length >= _pageTitleMaxBytes) {
        subscription?.cancel();
        timer?.cancel();
        if (!completer.isCompleted) {
          completer.complete(Uint8List.fromList(bytes));
        }
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      timer?.cancel();
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    },
    onDone: () {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.complete(Uint8List.fromList(bytes));
      }
    },
    cancelOnError: true,
  );

  timer = Timer(timeout, () {
    subscription?.cancel();
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('Page title fetch timed out'));
    }
  });
  if (completer.isCompleted) timer.cancel();

  return completer.future;
}

/// The [PageTitleFetcher] used by the link add flow.
final pageTitleFetcherProvider = Provider<PageTitleFetcher>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HttpPageTitleFetcher(client);
});

/// Matches the first `<title>...</title>` pair, case-insensitively and across
/// newlines.
final RegExp _titlePattern = RegExp(
  r'<title[^>]*>(.*?)</title>',
  caseSensitive: false,
  dotAll: true,
);

/// A run of one or more whitespace characters.
final RegExp _whitespacePattern = RegExp(r'\s+');

/// Matches one named or numeric (decimal/hex) HTML entity.
final RegExp _entityPattern = RegExp(
  r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);',
);

/// Named HTML entities commonly found in page titles.
///
/// Replacements stay ASCII-only so decoded titles render identically on every
/// platform and font.
const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ndash': '-',
  'mdash': '-',
  'horbar': '-',
  'hellip': '...',
  'middot': '*',
  'bull': '*',
  'copy': '(c)',
  'reg': '(r)',
  'trade': '(tm)',
  'times': 'x',
};

/// Extracts the first `<title>` from [html], collapsed and entity-decoded.
///
/// Returns `null` when there is no non-empty title. Pure and total: malformed
/// markup yields `null` instead of throwing.
String? extractHtmlTitle(String html) {
  final raw = _titlePattern.firstMatch(html)?.group(1);
  if (raw == null) return null;
  // Collapse whitespace, decode entities, then trim: an entity such as
  // `&nbsp;` can decode to whitespace, so trimming must come after decoding.
  final collapsed = raw.replaceAll(_whitespacePattern, ' ');
  final decoded = decodeHtmlEntities(collapsed).trim();
  if (decoded.isEmpty) return null;
  return decoded;
}

/// Decodes common named and numeric HTML entities in [input].
///
/// Unknown entities are left untouched so visible text is never corrupted.
String decodeHtmlEntities(String input) =>
    input.replaceAllMapped(_entityPattern, (match) {
      final entity = match.group(1)!;
      if (entity.startsWith('#')) {
        return _decodeNumericEntity(entity) ?? match.group(0)!;
      }
      return _namedEntities[entity.toLowerCase()] ?? match.group(0)!;
    });

/// Decodes one numeric entity body (including the leading `#`), or returns
/// `null` when it is out of range.
String? _decodeNumericEntity(String entity) {
  final isHex = entity.length > 1 && (entity[1] == 'x' || entity[1] == 'X');
  final digits = entity.substring(isHex ? 2 : 1);
  final code = int.tryParse(digits, radix: isHex ? 16 : 10);
  // Reject NUL, anything outside the Unicode range, and lone surrogates.
  if (code == null || code <= 0 || code > 0x10FFFF) return null;
  if (code >= 0xD800 && code <= 0xDFFF) return null;
  return String.fromCharCode(code);
}

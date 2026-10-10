import 'dart:convert';

import 'package:http/http.dart' as http;

/// Raised when the Turso HTTP API rejects a request or returns a pipeline
/// error result.
class TursoException implements Exception {
  /// Creates a [TursoException] with [message].
  const TursoException(this.message);

  /// The human-readable failure detail.
  final String message;

  @override
  String toString() => 'TursoException: $message';
}

/// Raised when a remote operation is attempted without Turso credentials.
///
/// The sync engine treats this as "offline / not configured" so a delete can be
/// queued locally and retried after the device is set up.
class TursoNotConfiguredException extends TursoException {
  /// Creates a [TursoNotConfiguredException].
  const TursoNotConfiguredException() : super('Turso is not configured');
}

/// One statement in a [TursoClient.executeBatch] request.
class TursoStatement {
  /// Creates a [TursoStatement] running [sql] with positional [args].
  const TursoStatement(this.sql, [this.args = const []]);

  /// The SQL text.
  final String sql;

  /// The positional `?` parameters.
  final List<Object?> args;
}

/// Minimal libSQL HTTP API client for Turso.
///
/// Mirrors `../personal-os/src/lib/turso.ts`: a `POST {url}/v2/pipeline`
/// request carrying one or more `execute` requests plus `close`, an
/// `Authorization: Bearer` header, and value encoding/decoding for `text` /
/// `integer` / `real` / `null`. The `libsql://` scheme is rewritten to
/// `https://` because the HTTP API only speaks HTTPS.
class TursoClient {
  /// Creates a client for [url] and [token] over [httpClient].
  ///
  /// [httpClient] is injected so one instance (and its connection pool) is
  /// shared across every client and sync; see the caller for its lifetime.
  TursoClient({
    required String url,
    required String token,
    required http.Client httpClient,
  }) : this._(normalizeTursoUrl(url), token, httpClient);

  TursoClient._(this._url, this._token, this._http);

  final String _url;
  final String _token;

  /// The shared HTTP client every request goes through.
  ///
  /// Owned by the caller, which keeps one instance alive for the app's lifetime
  /// so the underlying connection (and its TLS session) is reused across the
  /// many statements of a sync and across syncs. The top-level `http.post`
  /// helper builds and closes a fresh client per call, forcing a new TCP + TLS
  /// handshake for every statement; the desktop's webview `fetch` reuses one
  /// connection, which is why it syncs much faster.
  final http.Client _http;

  /// Normalizes [url] to the `https://` scheme the HTTP API needs.
  ///
  /// `libsql://` and `http://` are rewritten to `https://` so the Bearer token
  /// is never sent over cleartext, `https://` is left as-is, and a URL with no
  /// scheme gets `https://` prepended.
  static String normalizeTursoUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('https://')) return trimmed;
    if (trimmed.startsWith('libsql://')) {
      return 'https://${trimmed.substring('libsql://'.length)}';
    }
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }
    return 'https://$trimmed';
  }

  /// Runs [sql] against the remote and returns the rows, keyed by column name.
  ///
  /// Values are decoded to `String`, `int`, `double`, or `null`, matching the
  /// reference `parseValue`.
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final results = await _pipeline([TursoStatement(sql, args)]);
    final result = _statementResult(results.first);
    final rawCols = result['cols'];
    final rawRows = result['rows'];
    if (rawCols is! List || rawRows is! List) return const [];

    final names = [
      for (final col in rawCols)
        (col as Map<String, Object?>)['name'] as String? ?? '',
    ];

    return [
      for (final row in rawRows)
        {
          for (var i = 0; i < names.length; i++)
            names[i]: _parseValue((row as List)[i]),
        },
    ];
  }

  /// Runs a write [sql] against the remote, ignoring the (empty) result rows.
  Future<void> execute(String sql, [List<Object?> args = const []]) async {
    final results = await _pipeline([TursoStatement(sql, args)]);
    _statementResult(results.first);
  }

  /// Runs [statements] in a single `/v2/pipeline` request.
  ///
  /// Returns one entry per statement, in order: the failure message when it
  /// errored, or `null` on success. The server always executes every request,
  /// even when some fail (see the libSQL HTTP v2 spec), so a batch never stops
  /// early; only a transport-level failure throws [TursoException].
  Future<List<String?>> executeBatch(List<TursoStatement> statements) async {
    final results = await _pipeline(statements);
    if (results.length < statements.length) {
      throw const TursoException(
        'Turso returned fewer results than the batch had statements',
      );
    }
    return [
      for (var i = 0; i < statements.length; i++) _statementError(results[i]),
    ];
  }

  /// Sends [statements] as one pipeline (with a trailing `close`) and returns
  /// the raw per-request `results`.
  Future<List<Map<String, Object?>>> _pipeline(
    List<TursoStatement> statements,
  ) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$_url/v2/pipeline'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'requests': [
                for (final statement in statements)
                  {
                    'type': 'execute',
                    'stmt': {
                      'sql': statement.sql,
                      'args': [for (final arg in statement.args) _toArg(arg)],
                    },
                  },
                {'type': 'close'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on TursoException {
      rethrow;
    } catch (error) {
      throw TursoException('Could not reach Turso: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TursoException(
        'Turso HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw TursoException('Turso returned invalid JSON: $error');
    }

    final results = (decoded as Map<String, Object?>?)?['results'];
    if (results is! List || results.isEmpty) {
      throw const TursoException('Turso returned an empty result set');
    }
    return [for (final result in results) result as Map<String, Object?>];
  }

  /// Extracts a statement result, throwing [TursoException] when it errored.
  static Map<String, Object?> _statementResult(
    Map<String, Object?> streamResult,
  ) {
    if (streamResult['type'] == 'error') {
      throw TursoException('Turso: ${_errorMessage(streamResult)}');
    }
    final result =
        (streamResult['response'] as Map<String, Object?>?)?['result'];
    return result is Map<String, Object?> ? result : const {};
  }

  /// The failure message of [streamResult], or `null` when it succeeded.
  static String? _statementError(Map<String, Object?> streamResult) =>
      streamResult['type'] == 'error' ? _errorMessage(streamResult) : null;

  /// The `error.message` of an error stream result.
  static String _errorMessage(Map<String, Object?> streamResult) {
    final error = streamResult['error'] as Map<String, Object?>?;
    return error?['message']?.toString() ?? 'unknown error';
  }

  /// Encodes one argument into the Turso value envelope, mirroring `toArg`.
  static Map<String, Object?> _toArg(Object? value) {
    if (value == null) return const {'type': 'null'};
    if (value is int) return {'type': 'integer', 'value': '$value'};
    if (value is double) return {'type': 'real', 'value': '$value'};
    if (value is num) return {'type': 'real', 'value': '$value'};
    return {'type': 'text', 'value': '$value'};
  }

  /// Decodes one value envelope, mirroring `parseValue`.
  static Object? _parseValue(Object? value) {
    if (value == null) return null;
    if (value is! Map) return value;

    final type = value['type'];
    if (type == 'null') return null;
    if (type == 'integer') return _asInt(value['value']);
    if (type == 'real') return _asDouble(value['value']);
    return value['value'];
  }

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.parse(value?.toString() ?? '0');
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.parse(value?.toString() ?? '0');
  }
}

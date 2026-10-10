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

/// Minimal libSQL HTTP API client for Turso.
///
/// Mirrors `../personal-os/src/lib/turso.ts`: a single `POST {url}/v2/pipeline`
/// request per statement carrying `[execute, close]`, an `Authorization: Bearer`
/// header, and value encoding/decoding for `text` / `integer` / `real` / `null`.
/// The `libsql://` scheme is rewritten to `https://` because the HTTP API only
/// speaks HTTPS.
class TursoClient {
  /// Creates a client for [url] and [token].
  TursoClient({required String url, required String token})
    : this._(normalizeTursoUrl(url), token);

  TursoClient._(this._url, this._token);

  final String _url;
  final String _token;

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
    final result = await _pipeline(sql, args);
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
    await _pipeline(sql, args);
  }

  /// Sends one `execute` + `close` pipeline and returns the execute result.
  Future<Map<String, Object?>> _pipeline(String sql, List<Object?> args) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_url/v2/pipeline'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'requests': [
                {
                  'type': 'execute',
                  'stmt': {
                    'sql': sql,
                    'args': [for (final arg in args) _toArg(arg)],
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

    final first = results.first as Map<String, Object?>;
    if (first['type'] == 'error') {
      final error = first['error'] as Map<String, Object?>?;
      throw TursoException('Turso: ${error?['message'] ?? 'unknown error'}');
    }

    final result = (first['response'] as Map<String, Object?>?)?['result'];
    return result is Map<String, Object?> ? result : const {};
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

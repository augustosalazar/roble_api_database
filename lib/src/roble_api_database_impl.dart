import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'roble_api_config.dart';
import 'roble_api_exception.dart';
import 'roble_models.dart';
import 'roble_storage.dart';

part 'roble_realtime.dart';

/// Cliente HTTP robusto para interactuar con la API Roble.
///
/// - Soporta inyección de `http.Client` para facilitar tests.
/// - Maneja timeouts, errores de red y parsing.
/// - Expone métodos CRUD y auth adaptados al backend Roble.
class RobleApiDataBase {
  final RobleApiConfig config;
  final http.Client client;

  String? _accessToken;
  String? _refreshToken;

  /// Callback opcional invocado cada vez que cambia el access token:
  /// login, refresco automático o logout. Útil para persistir la sesión.
  void Function(String? token)? onTokenUpdate;

  RobleRealtime? _realtime;

  /// Acceso al servicio Realtime: árbol JSON al estilo Firebase.
  RobleRealtime get realtime => _realtime ??= RobleRealtime._(this);

  /// Dónde persistir la sesión. Si es `null`, los tokens viven solo en
  /// memoria y se pierden al reiniciar la app.
  final RobleTokenStorage? storage;

  late final String _storageKey =
      'roble.session.${config.authUrl.split('/').last}';

  RobleApiDataBase({
    required this.config,
    http.Client? client,
    this.storage,
  }) : client = client ?? http.Client();

  // ============================================================
  // ============= TOKENS =======================================
  // ============================================================

  /// Access token actual, o `null` si no hay sesión activa.
  String? get accessToken => _accessToken;

  /// Refresh token actual, o `null` si no hay sesión activa.
  String? get refreshToken => _refreshToken;

  /// Restaura una sesión previamente persistida.
  void setTokens({required String accessToken, required String refreshToken}) {
    _refreshToken = refreshToken;
    _updateAccessToken(accessToken);
  }

  /// Descarta la sesión en memoria.
  void clearTokens() {
    _refreshToken = null;
    _updateAccessToken(null);
  }

  void _updateAccessToken(String? token) {
    _accessToken = token;
    onTokenUpdate?.call(token);
    // Único punto por el que pasan login, refresco, setTokens y clearTokens.
    unawaited(_persistSession());
  }

  /// Restaura la sesión guardada, si la hay.
  ///
  /// Llámalo al arrancar la app, antes de pintar pantallas protegidas.
  /// Devuelve `true` si había una sesión que restaurar.
  ///
  /// ```dart
  /// if (await db.restoreSession()) {
  ///   // sesión activa; el access token se renovará solo si hace falta
  /// }
  /// ```
  Future<bool> restoreSession() async {
    final store = storage;
    if (store == null) return false;

    try {
      final raw = await store.getItem(_storageKey);
      if (raw == null || raw.isEmpty) return false;

      final data = jsonDecode(raw);
      if (data is! Map) return false;

      final access = data['accessToken'] as String?;
      final refresh = data['refreshToken'] as String?;
      if (access == null || refresh == null) return false;

      _refreshToken = refresh;
      _updateAccessToken(access);
      return true;
    } catch (_) {
      // Sesión corrupta o almacenamiento no disponible: se empieza de cero.
      return false;
    }
  }

  /// Guarda o borra la sesión. Nunca hace fallar la petición en curso.
  Future<void> _persistSession() async {
    final store = storage;
    if (store == null) return;

    try {
      final access = _accessToken;
      final refresh = _refreshToken;

      if (access != null && refresh != null) {
        await store.setItem(
          _storageKey,
          jsonEncode({'accessToken': access, 'refreshToken': refresh}),
        );
      } else {
        await store.removeItem(_storageKey);
      }
    } catch (_) {
      // Almacenamiento lleno o sin permisos: la sesión sigue en memoria.
    }
  }

  // ============================================================
  // ============= MÉTODOS INTERNOS =============================
  // ============================================================

  Uri _buildUri(String baseUrl, String endpoint,
      [Map<String, String>? queryParams]) {
    return Uri.parse('$baseUrl/$endpoint')
        .replace(queryParameters: queryParams);
  }

  Map<String, String> _buildHeaders({bool skipAuth = false}) {
    final headers = <String, String>{'Content-Type': 'application/json'};

    // ✅ Si hay token, lo agrega automáticamente como header
    if (!skipAuth && _accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    return headers;
  }

  /// Ejecuta una solicitud HTTP genérica.
  ///
  /// [skipAuth] omite el header `Authorization`, necesario para endpoints
  /// públicos como `/public-read`.
  Future<dynamic> _makeRequest(
    String method,
    String endpoint, {
    Object? body,
    Map<String, String>? queryParams,
    bool isAuthRequest = false,
    bool skipAuth = false,
    String? baseUrlOverride,
  }) async {
    final baseUrl =
        baseUrlOverride ?? (isAuthRequest ? config.authUrl : config.dataUrl);
    final uri = _buildUri(baseUrl, endpoint, queryParams);
    final headers = _buildHeaders(skipAuth: skipAuth);

    try {
      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response =
              await client.get(uri, headers: headers).timeout(config.timeout);
          break;
        case 'POST':
          response = await client
              .post(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(config.timeout);
          break;
        case 'PUT':
          response = await client
              .put(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(config.timeout);
          break;
        case 'PATCH':
          response = await client
              .patch(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(config.timeout);
          break;
        case 'DELETE':
          response = await client
              .delete(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(config.timeout);
          break;
        default:
          throw RobleApiException('HTTP method $method no soportado');
      }

      // Respuesta exitosa
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return null;
        try {
          return jsonDecode(response.body);
        } catch (_) {
          return response.body;
        }
      }

      // Manejo de errores HTTP
      if (response.statusCode == 401 &&
          _refreshToken != null &&
          !isAuthRequest &&
          !skipAuth) {
        // 🔁 Intentamos refrescar el token automáticamente
        try {
          await _refreshAccessToken();
        } catch (e) {
          throw RobleApiAuthException(
              'Token expirado y no se pudo refrescar: $e');
        }
        // Reintentamos la misma solicitud una sola vez
        return await _makeRequest(
          method,
          endpoint,
          body: body,
          queryParams: queryParams,
          isAuthRequest: isAuthRequest,
          skipAuth: skipAuth,
          baseUrlOverride: baseUrlOverride,
        );
      }

      String msg;
      if (response.body.isEmpty) {
        msg = 'El servidor respondió sin cuerpo';
      } else {
        try {
          final decoded = jsonDecode(response.body);
          final detail = (decoded is Map)
              ? (decoded['message'] ?? decoded['error'])
              : null;
          msg = detail != null ? '$detail' : response.body;
        } catch (_) {
          msg = response.body;
        }
      }
      throw RobleApiHttpException(response.statusCode, msg);
    } on RobleApiException {
      // Ya es una excepción del paquete: la propagamos sin envolverla.
      rethrow;
    } on SocketException {
      throw const RobleApiNetworkException('Sin conexión a internet');
    } on TimeoutException {
      throw const RobleApiTimeoutException('Tiempo de espera agotado');
    } on FormatException {
      throw const RobleApiFormatException('Respuesta con formato inválido');
    } catch (e) {
      throw RobleApiException('Error inesperado: $e');
    }
  }

  // ============================================================
  // ============= MÉTODOS DE AUTENTICACIÓN =====================
  // ============================================================

  /// Registra un usuario sin verificación por correo.
  ///
  /// [extra] son campos adicionales opcionales que el backend guarda junto al
  /// usuario; se envían tal cual en el campo `extra` del cuerpo.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    Map<String, dynamic>? extra,
  }) async {
    final res = await _makeRequest(
      'POST',
      'signup-direct',
      body: {
        'email': email,
        'password': password,
        'name': name,
        if (extra != null) 'extra': extra,
      },
      isAuthRequest: true,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Registra un usuario y envía un código de verificación por correo.
  ///
  /// El registro no queda activo hasta llamar a [verifyEmail] con el código.
  ///
  /// [extra] son campos adicionales opcionales que el backend guarda junto al
  /// usuario; se envían tal cual en el campo `extra` del cuerpo.
  Future<Map<String, dynamic>> registerWithVerification({
    required String email,
    required String password,
    required String name,
    Map<String, dynamic>? extra,
  }) async {
    final res = await _makeRequest(
      'POST',
      'signup',
      body: {
        'email': email,
        'password': password,
        'name': name,
        if (extra != null) 'extra': extra,
      },
      isAuthRequest: true,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Confirma el correo con el código de 6 dígitos recibido.
  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final res = await _makeRequest(
      'POST',
      'verify-email',
      body: {'email': email, 'code': code},
      isAuthRequest: true,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Reenvía el código de verificación.
  Future<Map<String, dynamic>> resendCode({required String email}) async {
    final res = await _makeRequest(
      'POST',
      'resend-code',
      body: {'email': email},
      isAuthRequest: true,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Inicia sesión y almacena los tokens internamente.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _makeRequest(
      'POST',
      'login',
      body: {'email': email, 'password': password},
      isAuthRequest: true,
    );

    if (res is Map) {
      _refreshToken = res['refreshToken'] as String?;
      _updateAccessToken(res['accessToken'] as String?);
    }

    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Cierra la sesión en el servidor y descarta los tokens locales.
  Future<void> logout() async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw const RobleApiAuthException(
          'No hay token activo para cerrar sesión.');
    }

    await _makeRequest('POST', 'logout', isAuthRequest: true);
    clearTokens();
  }

  /// Devuelve los datos del usuario autenticado (`sub`, `email`, `dbName`,
  /// `sessionId`). Es el único endpoint que expone la identidad del usuario.
  ///
  /// Lanza [RobleApiHttpException] con `401` si el token no es válido.
  Future<Map<String, dynamic>> currentUser() async {
    final res = await _makeRequest('GET', 'verify-token', isAuthRequest: true);

    if (res is Map && res['user'] is Map) {
      return Map<String, dynamic>.from(res['user'] as Map);
    }
    throw const RobleApiFormatException(
        'Respuesta inesperada al verificar el token.');
  }

  /// Envía un correo con el enlace de restablecimiento de contraseña.
  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final res = await _makeRequest(
      'POST',
      'forgot-password',
      body: {'email': email},
      isAuthRequest: true,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Restablece la contraseña con el token recibido por correo.
  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final res = await _makeRequest(
      'POST',
      'reset-password',
      body: {'token': token, 'newPassword': newPassword},
      isAuthRequest: true,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Elimina permanentemente la cuenta autenticada y limpia la sesión local.
  ///
  /// La operación no se puede deshacer: pide confirmación al usuario antes
  /// de llamarla.
  Future<void> deleteAccount() async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw const RobleApiAuthException(
          'No hay sesión activa para eliminar la cuenta.');
    }

    await _makeRequest('DELETE', 'account', isAuthRequest: true);
    clearTokens();
  }

  /// Refresca el access token con el refresh token almacenado.
  ///
  /// Es interno a propósito: se invoca automáticamente cuando una petición
  /// de datos responde `401`. No forma parte de la API pública.
  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) {
      throw const RobleApiAuthException('No hay refresh token disponible.');
    }

    final res = await _makeRequest(
      'POST',
      'refresh-token',
      body: {'refreshToken': _refreshToken},
      isAuthRequest: true,
    );

    if (res is Map && res.containsKey('accessToken')) {
      // Hoy el servidor solo devuelve accessToken, pero si algún día rota el
      // refresh token no hay que perderlo.
      final rotated = res['refreshToken'] as String?;
      if (rotated != null) _refreshToken = rotated;

      _updateAccessToken(res['accessToken'] as String?);
    } else {
      throw const RobleApiAuthException(
          'Respuesta inválida al refrescar el token.');
    }
  }

  // ============================================================
  // ============= MÉTODOS DE TABLAS / CRUD =====================
  // ============================================================

  Future<void> createTable(
      String tableName, List<Map<String, dynamic>> columns) async {
    await _makeRequest(
      'POST',
      'create-table',
      body: {
        'tableName': tableName,
        'description': 'Tabla $tableName creada desde cliente móvil',
        'columns': columns,
      },
    );
  }

  Future<dynamic> getTableData(String tableName) async {
    return await _makeRequest(
      'GET',
      'table-data',
      queryParams: {'schema': 'public', 'table': tableName},
    );
  }

  /// Clona la estructura de columnas de una tabla existente.
  ///
  /// Es el único mecanismo de creación de tablas documentado por la API, y
  /// requiere que [templateTableName] ya exista. No copia los datos.
  Future<Map<String, dynamic>> createTableFromTemplate({
    required String tableName,
    required String templateTableName,
  }) async {
    final res = await _makeRequest(
      'POST',
      'create-table-from-template',
      body: {
        'tableName': tableName,
        'templateTableName': templateTableName,
      },
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Inserta un registro y devuelve la fila creada, con su `_id`.
  ///
  /// Usa `/insert-one`, que devuelve el registro directamente. Si el servidor
  /// rechaza la fila, responde con un error HTTP en lugar de un `200` vacío.
  Future<Map<String, dynamic>> create(
      String tableName, Map<String, dynamic> data) async {
    final res = await _makeRequest(
      'POST',
      'insert-one',
      body: {'tableName': tableName, 'record': data},
    );

    if (res is Map) return Map<String, dynamic>.from(res);
    throw const RobleApiFormatException('No se pudo insertar el registro');
  }

  /// Inserta varios registros.
  ///
  /// El servidor responde `200` aunque rechace parte de los registros, así que
  /// el resultado expone [RobleInsertResult.skipped]. Revísalo siempre:
  ///
  /// ```dart
  /// final res = await db.createMany('usuarios', registros);
  /// if (res.hasSkipped) {
  ///   for (final s in res.skipped) {
  ///     print('Fila ${s.index} rechazada: ${s.reason}');
  ///   }
  /// }
  /// ```
  Future<RobleInsertResult> createMany(
      String tableName, List<Map<String, dynamic>> records) async {
    final res = await _makeRequest(
      'POST',
      'insert',
      body: {'tableName': tableName, 'records': records},
    );

    if (res is Map) return RobleInsertResult.fromJson(res);
    throw const RobleApiFormatException(
        'Respuesta inesperada al insertar registros');
  }

  Future<List<Map<String, dynamic>>> read(String tableName,
      {Map<String, dynamic>? filters}) async {
    final queryParams = <String, String>{'tableName': tableName};
    if (filters != null) {
      filters.forEach((k, v) => queryParams[k] = v.toString());
    }

    final res = await _makeRequest('GET', 'read', queryParams: queryParams);
    if (res is List) return List<Map<String, dynamic>>.from(res);
    if (res is Map && res.containsKey('data')) {
      return List<Map<String, dynamic>>.from(res['data']);
    }
    return [];
  }

  Future<Map<String, dynamic>> update(
      String tableName, dynamic id, Map<String, dynamic> data) async {
    final updateData = Map<String, dynamic>.from(data)
      ..remove('_id')
      ..remove('id');

    final res = await _makeRequest(
      'PUT',
      'update',
      body: {
        'tableName': tableName,
        'idColumn': '_id',
        'idValue': id,
        'updates': updateData,
      },
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  Future<Map<String, dynamic>> delete(String tableName, dynamic id) async {
    final res = await _makeRequest(
      'DELETE',
      'delete',
      body: {
        'tableName': tableName,
        'idColumn': '_id',
        'idValue': id,
      },
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Lee una tabla marcada como pública, sin autenticación.
  ///
  /// Un `403` significa que la tabla no está configurada como pública en la
  /// consola de Roble, no que el token sea inválido.
  Future<List<Map<String, dynamic>>> publicRead(String tableName,
      {Map<String, dynamic>? filters}) async {
    final queryParams = <String, String>{'tableName': tableName};
    if (filters != null) {
      filters.forEach((k, v) => queryParams[k] = v.toString());
    }

    final res = await _makeRequest(
      'GET',
      'public-read',
      queryParams: queryParams,
      skipAuth: true,
    );

    if (res is List) return List<Map<String, dynamic>>.from(res);
    if (res is Map && res['data'] is List) {
      return List<Map<String, dynamic>>.from(res['data'] as List);
    }
    return [];
  }

  /// Ejecuta una consulta guardada previamente en la consola de Roble.
  ///
  /// Es la vía para joins, agregados, ordenamiento y paginación: [read] solo
  /// admite filtros de igualdad. [id] es el UUID de la consulta guardada.
  Future<RobleQueryResult> executeQuery(String id,
      {List<dynamic>? params}) async {
    final res = await _makeRequest(
      'POST',
      'execute-query',
      body: {
        'id': id,
        if (params != null) 'params': params,
      },
    );

    if (res is Map) return RobleQueryResult.fromJson(res);
    throw const RobleApiFormatException(
        'Respuesta inesperada al ejecutar la consulta');
  }

  // ============================================================
  // ============= MÉTODOS DE CONVENIENCIA ======================
  // ============================================================

  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    return await read(tableName);
  }

  Future<Map<String, dynamic>?> getById(String tableName, dynamic id) async {
    final results = await read(tableName, filters: {'_id': id});
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getWhere(
      String tableName, String column, dynamic value) async {
    return await read(tableName, filters: {column: value});
  }
}

part of 'roble_api_database_impl.dart';

/// Operación que originó un evento Realtime.
enum RobleRealtimeOperation { insert, update, delete, unknown }

/// Estado de la conexión WebSocket de Realtime.
enum RobleRealtimeStatus { disconnected, connecting, connected, error }

/// Cambio recibido por el WebSocket de Realtime.
///
/// Ojo con la asimetría del servidor: en `INSERT`, [path] apunta al **padre**
/// y el id del nuevo hijo es la clave dentro de [newValue]. En `UPDATE` y
/// `DELETE`, [path] apunta al nodo afectado.
class RobleRealtimeEvent {
  /// Identificador único del evento.
  final String eventId;

  /// Id de la suscripción que lo originó.
  final String subscriptionId;

  /// Colección (primer segmento de la ruta).
  final String table;

  /// Ruta como lista de segmentos, p. ej. `['messages','general']`.
  final List<String> path;

  final RobleRealtimeOperation operation;

  /// Valor anterior. `null` en `INSERT`.
  final dynamic oldValue;

  /// Valor nuevo. `null` en `DELETE`. En `UPDATE` es **parcial**: solo los
  /// campos enviados, tanto en `PATCH` como en `PUT`.
  final dynamic newValue;

  final String commitTimestamp;

  /// Payload crudo tal cual lo envió el servidor.
  final Map<String, dynamic> raw;

  const RobleRealtimeEvent({
    required this.eventId,
    required this.subscriptionId,
    required this.table,
    required this.path,
    required this.operation,
    required this.oldValue,
    required this.newValue,
    required this.commitTimestamp,
    required this.raw,
  });

  /// Ruta como string, p. ej. `'messages/general'`.
  String get pathString => path.join('/');

  factory RobleRealtimeEvent.fromJson(Map<dynamic, dynamic> json) {
    final rawPath = json['path'];
    final path = rawPath is List
        ? rawPath.map((e) => '$e').toList()
        : <String>[];

    return RobleRealtimeEvent(
      eventId: '${json['eventId'] ?? ''}',
      subscriptionId: '${json['subscriptionId'] ?? ''}',
      table: '${json['table'] ?? (path.isNotEmpty ? path.first : '')}',
      path: path,
      operation: _parseOperation('${json['operation']}'),
      oldValue: json['old'],
      newValue: json['new'],
      commitTimestamp: '${json['commitTimestamp'] ?? ''}',
      raw: Map<String, dynamic>.from(json),
    );
  }

  static RobleRealtimeOperation _parseOperation(String value) {
    switch (value.toUpperCase()) {
      case 'INSERT':
        return RobleRealtimeOperation.insert;
      case 'UPDATE':
        return RobleRealtimeOperation.update;
      case 'DELETE':
        return RobleRealtimeOperation.delete;
      default:
        return RobleRealtimeOperation.unknown;
    }
  }

  @override
  String toString() =>
      'RobleRealtimeEvent(${operation.name} $pathString, new: $newValue)';
}

/// Una escucha registrada sobre una ruta.
class _RealtimeListener {
  final List<String> segments;
  final String collection;
  final RobleRealtimeRef ref;
  final void Function(RobleRealtimeEvent)? onEvent;
  final void Function(dynamic)? onValue;
  final void Function(Object)? onError;

  _RealtimeListener({
    required this.segments,
    required this.collection,
    required this.ref,
    this.onEvent,
    this.onValue,
    this.onError,
  });
}

/// Punto de entrada al servicio Realtime de Roble: un árbol JSON por proyecto,
/// con una API al estilo de Firebase Realtime Database.
///
/// ```dart
/// final mensajes = db.realtime.ref('messages/general');
/// final id = await mensajes.push({'texto': 'Hola'});
/// mensajes.onValue.listen((valor) => print(valor));
/// ```
class RobleRealtime {
  final RobleApiDataBase _db;

  sio.Socket? _socket;
  String? _socketToken;
  final Set<_RealtimeListener> _listeners = {};

  /// colección -> subscriptionId devuelto por el servidor.
  final Map<String, String> _subscriptions = {};

  RobleRealtimeStatus _status = RobleRealtimeStatus.disconnected;

  /// Se invoca en cada cambio de estado de la conexión.
  void Function(RobleRealtimeStatus)? onStatusChange;

  RobleRealtime._(this._db);

  /// Estado actual de la conexión WebSocket.
  RobleRealtimeStatus get status => _status;

  String get _baseUrl {
    final url = _db.config.realtimeUrl;
    if (url == null || url.isEmpty) {
      throw const RobleApiException(
        'No hay realtimeUrl configurada. Usa RobleApiConfig.fromContract() o '
        'pasa realtimeUrl al constructor.',
      );
    }
    return url;
  }

  /// `{host}/realtime/{contractId}` -> `{host}`
  String get _host {
    final i = _baseUrl.lastIndexOf('/realtime/');
    return i >= 0 ? _baseUrl.substring(0, i) : _baseUrl;
  }

  /// `{host}/realtime/{contractId}` -> `{contractId}`
  String get _contractId => _baseUrl.split('/').last;

  /// Referencia a una ruta del árbol. El primer segmento es la colección.
  ///
  /// Sin argumentos apunta a la raíz del proyecto.
  RobleRealtimeRef ref([String path = '']) =>
      RobleRealtimeRef._(this, _normalize(path));

  /// Nombres de las colecciones del proyecto.
  Future<List<String>> collections() async {
    final res = await _db._makeRequest('GET', '', baseUrlOverride: _baseUrl);
    if (res is List) return res.map((e) => '$e').toList();
    return const [];
  }

  /// Estado del servicio Realtime (PostgreSQL, event bus y CDC).
  ///
  /// No requiere autenticación y no depende del proyecto.
  Future<Map<String, dynamic>> health() async {
    final res = await _db._makeRequest(
      'GET',
      'health',
      baseUrlOverride: '$_host/realtime',
      skipAuth: true,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Cierra el WebSocket y cancela todas las escuchas.
  ///
  /// El socket se vuelve a abrir solo si se registra una escucha nueva.
  void close() {
    _listeners.clear();
    _subscriptions.clear();
    _socket?.dispose();
    _socket = null;
    _socketToken = null;
    _setStatus(RobleRealtimeStatus.disconnected);
  }

  // ---- internos ----

  static String _normalize(String path) =>
      path.split('/').where((s) => s.isNotEmpty).join('/');

  /// ¿Una ruta es prefijo de la otra? Cubre ancestros y descendientes.
  static bool _overlap(List<String> a, List<String> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _setStatus(RobleRealtimeStatus status) {
    if (_status == status) return;
    _status = status;
    onStatusChange?.call(status);
  }

  sio.Socket _ensureSocket() {
    final token = _db.accessToken;
    if (token == null || token.isEmpty) {
      throw const RobleApiAuthException(
        'No hay sesión activa para abrir el WebSocket de Realtime.',
      );
    }

    // Si el token cambió, hay que rehacer el handshake.
    if (_socket != null && _socketToken != token) {
      _socket?.dispose();
      _socket = null;
      _subscriptions.clear();
    }

    final existing = _socket;
    if (existing != null) return existing;

    final wsUrl =
        '$_host/stream'.replaceFirst(RegExp(r'^http'), 'ws');

    _setStatus(RobleRealtimeStatus.connecting);

    final socket = sio.io(
      wsUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'token': token, 'dbName': _contractId})
          .build(),
    );

    socket.onConnect((_) {
      _setStatus(RobleRealtimeStatus.connected);
      // Al reconectar hay que rehacer todas las suscripciones.
      _subscriptions.clear();
      for (final collection in _activeCollections()) {
        _subscribeCollection(collection);
      }
    });

    socket.onDisconnect((_) {
      _subscriptions.clear();
      _setStatus(RobleRealtimeStatus.disconnected);
    });

    socket.onConnectError((_) => _setStatus(RobleRealtimeStatus.error));

    socket.on('data_change', (payload) {
      final items = payload is List ? payload : [payload];
      for (final raw in items) {
        if (raw is Map) _dispatch(raw);
      }
    });

    _socket = socket;
    _socketToken = token;
    return socket;
  }

  Set<String> _activeCollections() =>
      _listeners.map((l) => l.collection).where((c) => c.isNotEmpty).toSet();

  void _subscribeCollection(String collection) {
    final socket = _socket;
    if (socket == null ||
        !socket.connected ||
        _subscriptions.containsKey(collection)) {
      return;
    }

    socket.emitWithAck(
      'subscribe',
      {
        'type': 'subscribe',
        'requestId': '$collection-${DateTime.now().millisecondsSinceEpoch}',
        'table': collection,
        'events': ['INSERT', 'UPDATE', 'DELETE'],
      },
      ack: (dynamic response) {
        if (response is Map && response['subscriptionId'] != null) {
          _subscriptions[collection] = '${response['subscriptionId']}';
        }
      },
    );
  }

  void _unsubscribeCollection(String collection) {
    final subscriptionId = _subscriptions.remove(collection);
    if (subscriptionId == null) return;
    _socket?.emit('unsubscribe', {
      'type': 'unsubscribe',
      'subscriptionId': subscriptionId,
    });
  }

  void _dispatch(Map<dynamic, dynamic> raw) {
    final event = RobleRealtimeEvent.fromJson(raw);

    for (final l in _listeners.toList()) {
      if (l.collection != event.table) continue;
      if (!_overlap(l.segments, event.path)) continue;

      if (l.onEvent != null) {
        try {
          l.onEvent!(event);
        } catch (e) {
          l.onError?.call(e);
        }
      }

      if (l.onValue != null) _emitValue(l);
    }
  }

  Future<void> _emitValue(_RealtimeListener l) async {
    // `new` es parcial y no distingue PATCH de PUT, así que releemos el nodo.
    try {
      l.onValue?.call(await l.ref.get());
    } catch (e) {
      l.onError?.call(e);
    }
  }

  void Function() _addListener(_RealtimeListener listener) {
    _listeners.add(listener);
    _ensureSocket();
    _subscribeCollection(listener.collection);

    if (listener.onValue != null) _emitValue(listener);

    var cancelled = false;
    return () {
      if (cancelled) return;
      cancelled = true;
      _listeners.remove(listener);

      // Si ya nadie escucha esa colección, se cancela en el servidor.
      final stillUsed =
          _listeners.any((l) => l.collection == listener.collection);
      if (!stillUsed) _unsubscribeCollection(listener.collection);
    };
  }
}

/// Referencia a una ruta concreta del árbol Realtime.
///
/// Es inmutable: [child] devuelve una referencia nueva.
class RobleRealtimeRef {
  final RobleRealtime _realtime;

  /// Ruta normalizada, sin barras iniciales ni finales. Vacía en la raíz.
  final String path;

  RobleRealtimeRef._(this._realtime, this.path);

  List<String> get _segments => path.isEmpty ? const [] : path.split('/');

  /// Nombre del último segmento, o `null` en la raíz.
  String? get key {
    if (path.isEmpty) return null;
    return path.split('/').last;
  }

  /// Referencia al hijo indicado. Admite rutas con varios segmentos.
  RobleRealtimeRef child(String childPath) {
    final sub = RobleRealtime._normalize(childPath);
    if (sub.isEmpty) return this;
    return RobleRealtimeRef._(_realtime, path.isEmpty ? sub : '$path/$sub');
  }

  /// Referencia al padre, o `null` si ya es la raíz.
  RobleRealtimeRef? get parent {
    if (path.isEmpty) return null;
    final segments = path.split('/')..removeLast();
    return RobleRealtimeRef._(_realtime, segments.join('/'));
  }

  /// Lee el valor JSON en esta ruta.
  ///
  /// Con [shallow] en `true` devuelve solo las claves inmediatas: las hojas
  /// conservan su valor y los hijos objeto/array se marcan con `$$kind`.
  Future<dynamic> get({bool shallow = false}) async {
    return await _realtime._db._makeRequest(
      'GET',
      path,
      queryParams: shallow ? const {'shallow': 'true'} : null,
      baseUrlOverride: _realtime._baseUrl,
    );
  }

  /// Sobrescribe el valor en esta ruta. Crea la colección si no existe.
  Future<dynamic> set(Object? value) async {
    return await _realtime._db._makeRequest(
      'PUT',
      path,
      body: value,
      baseUrlOverride: _realtime._baseUrl,
    );
  }

  /// Fusiona los campos indicados con el objeto existente en esta ruta.
  Future<Map<String, dynamic>> update(Map<String, dynamic> fields) async {
    final res = await _realtime._db._makeRequest(
      'PATCH',
      path,
      body: fields,
      baseUrlOverride: _realtime._baseUrl,
    );
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }

  /// Agrega un hijo con ID autogenerado, como `push()` de Firebase.
  ///
  /// Devuelve el ID generado.
  Future<String> push(Object? value) async {
    final res = await _realtime._db._makeRequest(
      'POST',
      path,
      body: value,
      baseUrlOverride: _realtime._baseUrl,
    );

    if (res is Map && res['name'] != null) return '${res['name']}';
    throw const RobleApiFormatException(
        'El servidor no devolvió el ID generado.');
  }

  /// Elimina el valor en esta ruta. Si la ruta es solo la colección, la
  /// elimina completa.
  Future<void> remove() async {
    await _realtime._db._makeRequest(
      'DELETE',
      path,
      baseUrlOverride: _realtime._baseUrl,
    );
  }

  void _requireSubscribable() {
    if (path.isEmpty) {
      throw const RobleApiException(
        'No se puede escuchar la raíz del proyecto: indica al menos la '
        'colección.',
      );
    }
  }

  /// Cambios en esta ruta y en sus descendientes, tal cual los envía el
  /// servidor y sin releer nada.
  ///
  /// ```dart
  /// final sub = ref.onEvent.listen((e) {
  ///   print('${e.operation.name} en ${e.pathString}: ${e.newValue}');
  /// });
  /// await sub.cancel();
  /// ```
  Stream<RobleRealtimeEvent> get onEvent {
    _requireSubscribable();

    late StreamController<RobleRealtimeEvent> controller;
    void Function()? off;

    controller = StreamController<RobleRealtimeEvent>(
      onListen: () {
        off = _realtime._addListener(_RealtimeListener(
          segments: _segments,
          collection: _segments.first,
          ref: this,
          onEvent: controller.add,
          onError: controller.addError,
        ));
      },
      onCancel: () {
        off?.call();
        off = null;
      },
    );

    return controller.stream;
  }

  /// Valor de esta ruta, al estilo `onValue` de Firebase.
  ///
  /// Emite el valor actual al suscribirse y vuelve a emitirlo tras cada
  /// cambio. Relee el nodo por REST en cada evento porque el `new` del
  /// servidor es parcial y no distingue `PATCH` de `PUT`.
  Stream<dynamic> get onValue {
    _requireSubscribable();

    late StreamController<dynamic> controller;
    void Function()? off;

    controller = StreamController<dynamic>(
      onListen: () {
        off = _realtime._addListener(_RealtimeListener(
          segments: _segments,
          collection: _segments.first,
          ref: this,
          onValue: controller.add,
          onError: controller.addError,
        ));
      },
      onCancel: () {
        off?.call();
        off = null;
      },
    );

    return controller.stream;
  }

  @override
  String toString() => 'RobleRealtimeRef(/$path)';
}

/// Almacenamiento donde persistir la sesión entre reinicios.
///
/// El paquete no elige por ti: en Flutter cada opción es un paquete distinto
/// y en móvil conviene un almacén seguro (Keychain/Keystore), porque el
/// refresh token es la credencial de larga duración.
///
/// Implementarlo sobre `flutter_secure_storage` son tres líneas:
///
/// ```dart
/// class SecureRobleStorage implements RobleTokenStorage {
///   final _storage = const FlutterSecureStorage();
///
///   @override
///   Future<String?> getItem(String key) => _storage.read(key: key);
///
///   @override
///   Future<void> setItem(String key, String value) =>
///       _storage.write(key: key, value: value);
///
///   @override
///   Future<void> removeItem(String key) => _storage.delete(key: key);
/// }
/// ```
abstract class RobleTokenStorage {
  /// Devuelve el valor guardado, o `null` si no existe.
  Future<String?> getItem(String key);

  /// Guarda un valor.
  Future<void> setItem(String key, String value);

  /// Borra un valor.
  Future<void> removeItem(String key);
}

/// Implementación en memoria, útil para pruebas.
///
/// No sobrevive a un reinicio: sirve para verificar la lógica de sesión sin
/// depender de un almacén real.
class RobleMemoryStorage implements RobleTokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem(String key) async => _values[key];

  @override
  Future<void> setItem(String key, String value) async => _values[key] = value;

  @override
  Future<void> removeItem(String key) async => _values.remove(key);
}

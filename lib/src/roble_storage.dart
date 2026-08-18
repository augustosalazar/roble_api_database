import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacenamiento donde persistir la sesión entre reinicios.
///
/// **No hace falta implementarlo**: el paquete usa [RobleSecureStorage] por
/// defecto. Esta interfaz existe para poder sustituirlo en pruebas
/// ([RobleMemoryStorage]) o por otro almacén propio.
abstract class RobleTokenStorage {
  /// Devuelve el valor guardado, o `null` si no existe.
  Future<String?> getItem(String key);

  /// Guarda un valor.
  Future<void> setItem(String key, String value);

  /// Borra un valor.
  Future<void> removeItem(String key);
}

/// Almacén por defecto: Keychain en iOS/macOS, Keystore en Android,
/// almacenamiento cifrado en web y el gestor de secretos del sistema en
/// escritorio.
///
/// Es el que usa [RobleApiDataBase] si no se le pasa ningún `storage`, así
/// que normalmente no hay que instanciarlo a mano. El refresh token es la
/// credencial de larga duración, por eso el paquete lo guarda aquí y no en
/// `SharedPreferences`.
///
/// Si el almacén no está disponible (por ejemplo al ejecutar en un test de
/// Dart puro, sin plataforma), las operaciones fallan en silencio y la sesión
/// simplemente no se persiste.
class RobleSecureStorage implements RobleTokenStorage {
  final FlutterSecureStorage _storage;

  /// [options] permite ajustar el comportamiento en Android
  /// (por ejemplo `AndroidOptions(encryptedSharedPreferences: true)`).
  RobleSecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> getItem(String key) => _storage.read(key: key);

  @override
  Future<void> setItem(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> removeItem(String key) => _storage.delete(key: key);
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

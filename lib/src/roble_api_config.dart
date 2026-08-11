/// Configuración principal para el cliente Roble API.
///
/// Define las URLs base usadas por [RobleApiDataBase]. Esta clase es
/// inmutable y apta para inyección en entornos de producción y prueba.
///
/// Ejemplo de uso:
/// ```dart
/// final config = RobleApiConfig.fromContract(
///   baseUrl: 'https://roble.test-openlab.uninorte.edu.co',
///   contractId: 'token_contract_xyz',
/// );
/// ```
class RobleApiConfig {
  /// URL base para endpoints de autenticación (login, signup, refresh, etc.).
  final String authUrl;

  /// URL base para endpoints de datos (CRUD, tablas, etc.).
  final String dataUrl;

  /// URL base del servicio Realtime (`{host}/realtime/{contractId}`).
  ///
  /// Es `null` si la configuración se creó con URLs explícitas y no se indicó;
  /// en ese caso, usar [RobleApiDataBase.realtime] lanza un error claro.
  final String? realtimeUrl;

  /// Tiempo máximo de espera por petición. Por defecto 30 segundos.
  final Duration timeout;

  /// Timeout usado cuando no se especifica ninguno.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Constructor principal.
  const RobleApiConfig({
    required this.authUrl,
    required this.dataUrl,
    this.realtimeUrl,
    this.timeout = defaultTimeout,
  });

  /// Crea una configuración básica a partir de URLs simples.
  factory RobleApiConfig.fromStrings({
    required String baseAuthUrl,
    required String baseDataUrl,
    Duration timeout = defaultTimeout,
  }) {
    return RobleApiConfig(
      authUrl: baseAuthUrl,
      dataUrl: baseDataUrl,
      timeout: timeout,
    );
  }

  /// Crea una configuración a partir del host de Roble y el identificador
  /// del contrato, componiendo las rutas `/auth/...` y `/database/...`.
  ///
  /// ```dart
  /// final config = RobleApiConfig.fromContract(
  ///   baseUrl: 'https://roble.test-openlab.uninorte.edu.co',
  ///   contractId: 'token_contract_xyz',
  /// );
  /// // authUrl: https://roble.test-openlab.uninorte.edu.co/auth/token_contract_xyz
  /// // dataUrl: https://roble.test-openlab.uninorte.edu.co/database/token_contract_xyz
  /// ```
  ///
  /// En Roble el servicio de realtime suele vivir en su propio host; pásalo
  /// en [realtimeBaseUrl]. El WebSocket solo funciona contra ese host.
  ///
  /// Si el contrato de autenticación y el proyecto de datos usan
  /// identificadores distintos, usa el constructor principal con `authUrl` y
  /// `dataUrl` completas.
  factory RobleApiConfig.fromContract({
    required String baseUrl,
    required String contractId,
    String? realtimeBaseUrl,
    Duration timeout = defaultTimeout,
  }) {
    String trim(String url) =>
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    final host = trim(baseUrl);
    final realtimeHost = trim(realtimeBaseUrl ?? baseUrl);

    return RobleApiConfig(
      authUrl: '$host/auth/$contractId',
      dataUrl: '$host/database/$contractId',
      realtimeUrl: '$realtimeHost/realtime/$contractId',
      timeout: timeout,
    );
  }

  /// Clona la configuración actual, reemplazando solo los valores provistos.
  RobleApiConfig copyWith({
    String? authUrl,
    String? dataUrl,
    String? realtimeUrl,
    Duration? timeout,
  }) {
    return RobleApiConfig(
      authUrl: authUrl ?? this.authUrl,
      dataUrl: dataUrl ?? this.dataUrl,
      realtimeUrl: realtimeUrl ?? this.realtimeUrl,
      timeout: timeout ?? this.timeout,
    );
  }

  /// Valida que las URLs sean correctas.
  void validate() {
    if (!authUrl.startsWith('http')) {
      throw ArgumentError('authUrl inválida: $authUrl');
    }
    if (!dataUrl.startsWith('http')) {
      throw ArgumentError('dataUrl inválida: $dataUrl');
    }
  }

  @override
  String toString() =>
      'RobleApiConfig(authUrl: $authUrl, dataUrl: $dataUrl, timeout: $timeout)';
}

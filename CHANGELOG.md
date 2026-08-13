# Changelog

## 1.0.0

Primera versión publicada bajo el nombre `roble`. Sustituye al paquete
`roble_api_database`, cuya API se mantiene salvo por los cambios listados abajo.

### Añadido

- `RobleApiConfig.fromContract({baseUrl, contractId})`: compone las rutas
  `/auth/...` y `/database/...` a partir del identificador del contrato.
- Getters públicos `accessToken` y `refreshToken`.
- Callback `onTokenUpdate`, invocado en cada cambio del access token.
- `RobleApiConfig.timeout` configurable (30 s por defecto).
- Documentación de todos los métodos públicos en el README.
- Cobertura completa de la API documentada de ROBLE (19 endpoints):
  `registerWithVerification()`, `verifyEmail()`, `resendCode()`, `currentUser()`
  (`/verify-token`, el único endpoint que devuelve la identidad del usuario),
  `forgotPassword()`, `resetPassword()`, `deleteAccount()`, `createMany()`,
  `executeQuery()`, `createTableFromTemplate()` y `publicRead()`.
- Modelos `RobleInsertResult`, `RobleSkippedRecord` y `RobleQueryResult`.
- **Servicio Realtime** (`db.realtime`): árbol JSON por proyecto con API al
  estilo Firebase — `ref()`, `child()`, `parent`, `key`, `get(shallow:)`,
  `set()`, `update()`, `push()`, `remove()`, más `collections()` y `health()`.
- **Suscripciones en tiempo real**: `ref.onValue` y `ref.onEvent` sobre
  WebSocket, con `RobleRealtimeEvent`, `status`, `onStatusChange` y `close()`.
  Un solo socket compartido, resuscripción automática al reconectar y
  cancelación por colección cuando no quedan escuchas. Añade la dependencia
  `socket_io_client`.
- **Persistencia de sesión opcional**: `RobleTokenStorage` + el parámetro
  `storage` y `restoreSession()`. El cliente guarda la sesión en cada login y
  refresco y la borra al cerrar sesión. Incluye `RobleMemoryStorage` para
  pruebas. Sin `storage`, los tokens siguen viviendo solo en memoria.
- Si el servidor rotara el refresh token al refrescar, ahora se conserva en
  lugar de descartarse.
- `register()` y `registerWithVerification()` aceptan un `extra` opcional
  (`Map<String, dynamic>`) con campos adicionales que el backend guarda junto
  al usuario. Se envía en el campo `extra` del cuerpo, y se omite si es nulo.

### Eliminado

- `authHeaders` y `dataHeaders` de `RobleApiConfig`, junto con
  `withBearerToken()` y el getter muerto `defaultHeaders`. La API solo necesita
  `Content-Type` y `Authorization`, y ambos los pone el cliente. Si necesitas
  cabeceras propias, inyecta un `http.Client` que las añada.

### Corregido

- **`PATCH` se enviaba como `PUT`.** El `switch` de `_makeRequest` agrupaba
  ambos métodos en `client.put()`, así que `realtime.ref().update()`
  sobrescribía el nodo en lugar de fusionar los campos. Ahora usa
  `client.patch()`.
- **`create()` podía informar éxito sobre una fila rechazada.** Enviaba el
  registro a `/insert`, que responde `200` con `{inserted: [], skipped: [...]}`
  cuando el servidor lo rechaza; al no haber nada en `inserted`, el método
  devolvía ese objeto como si fuera la fila creada, sin `_id` y sin error.
  Ahora usa `/insert-one`, que devuelve la fila directamente y falla con un
  error HTTP si la rechaza. Para varios registros, `createMany()` expone
  `skipped` en lugar de descartarlo.

### Cambiado

- Las excepciones que lanza el cliente ahora son las subclases exportadas del
  paquete: `RobleApiNetworkException`, `RobleApiTimeoutException`,
  `RobleApiFormatException`, `RobleApiHttpException` (con `statusCode`) y
  `RobleApiAuthException`. Antes se lanzaba una clase interna homónima que
  nunca coincidía con la exportada, por lo que `on RobleApiException catch`
  jamás capturaba nada.
- `logout()` ya no recibe `accessToken`: usa el token almacenado y limpia la
  sesión al terminar.
- El punto de entrada de la librería pasa a ser `package:roble/roble.dart`.
- Un error HTTP ya no se envuelve como `Error inesperado: ...`; se propaga como
  `RobleApiHttpException` con el mensaje del servidor.
- Tras un `401`, solo el fallo del refresco produce `RobleApiAuthException`; si
  el reintento falla, se reporta el error real de esa petición.

### Eliminado

- `refreshAccessToken()` y `refreshToken({refreshToken})` públicos. El refresco
  del token es interno y automático ante un `401`.
- `simulateGet()`, que no hacía nada.
- `RobleApiDataBase.timeoutDuration`, reemplazado por `RobleApiConfig.timeout`.

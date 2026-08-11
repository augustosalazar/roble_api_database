# 📦 roble

Paquete para Flutter que facilita la comunicación con la plataforma Roble API.
https://roble.openlab.uninorte.edu.co/

Este paquete provee una capa ligera para autenticación y operaciones CRUD sobre las bases de datos expuestas por Roble, manteniendo una interfaz simple y adecuada para aplicaciones móviles y de escritorio con Flutter.

https://github.com/augustosalazar/roble_api_database

## 🚀 Instalación

Agrega la dependencia en tu proyecto Flutter:

```bash
flutter pub add roble
```

Importa el paquete donde lo necesites:

```dart
import 'package:roble/roble.dart';
```

---

## 🧭 Quick start

Ejemplo mínimo de uso (async/await):

```dart
final db = RobleApiDataBase(
	config: RobleApiConfig.fromContract(
		baseUrl: 'https://tu-api.com',
		contractId: 'tu-contrato',
	),
);

// Registrar usuario
final user = await db.register(
	email: 'usuario@email.com',
	password: 'Password123!',
	name: 'Nombre Usuario',
);

// Iniciar sesión (guarda los tokens internamente)
await db.login(
	email: 'usuario@email.com',
	password: 'Password123!',
);

// Cerrar sesión (limpia los tokens)
await db.logout();

// CREATE - Crear registro
final nuevoUsuario = await db.create('usuarios', {
	'nombre': 'Ana García',
	'email': 'ana@email.com',
	'edad': 28,
});

// READ - Leer todos los registros
final usuarios = await db.read('usuarios');

// UPDATE - Actualizar registro
final actualizado = await db.update('usuarios', usuarioId, {
	'edad': 29,
});

// DELETE - Eliminar registro
final eliminado = await db.delete('usuarios', usuarioId);
```

> Nota: todos los métodos son asíncronos y lanzan alguna subclase de `RobleApiException` en caso de error de red o respuesta no esperada. Usa `try/catch` alrededor de tus llamadas.

> 🔁 Este paquete tiene un equivalente en JavaScript/TypeScript, [`roble-client`](https://github.com/augustosalazar/roble-api-database-ReNa), que **expone exactamente los mismos métodos** con las mismas excepciones.

---

## ⚙️ Configuración (`RobleApiConfig`)

`RobleApiConfig` es inmutable. Lo habitual es componerla desde el host y el identificador del contrato:

```dart
final config = RobleApiConfig.fromContract(
	baseUrl: 'https://roble.test-openlab.uninorte.edu.co',
	contractId: 'token_contract_xyz',
	timeout: Duration(seconds: 30), // opcional, 30 s por defecto
);
// authUrl: https://roble.test-openlab.uninorte.edu.co/auth/token_contract_xyz
// dataUrl: https://roble.test-openlab.uninorte.edu.co/database/token_contract_xyz
```

Una barra final en `baseUrl` se ignora. Eso es toda la configuración: `Content-Type: application/json` y `Authorization: Bearer …` los gestiona el cliente por su cuenta.

Roble expone dos hosts, uno para autenticación y otro para datos. Si por algún motivo usan identificadores distintos, pasa las URLs completas al constructor principal:

```dart
const config = RobleApiConfig(
	authUrl: 'https://roble-api.openlab.uninorte.edu.co/auth/tu_contrato',
	dataUrl: 'https://roble-api.openlab.uninorte.edu.co/database/tu_proyecto',
);
```

### Otros miembros

| Miembro | Descripción |
| --- | --- |
| `RobleApiConfig.fromStrings({baseAuthUrl, baseDataUrl, timeout})` | Constructor abreviado a partir de dos URLs. |
| `copyWith({authUrl, dataUrl, timeout})` | Clona la configuración reemplazando solo lo indicado. |
| `validate()` | Lanza `ArgumentError` si alguna URL no empieza por `http`. |

---

## 🔐 Manejo de tokens

Tras un `login()` exitoso el cliente guarda internamente el `accessToken` y el `refreshToken`, y los adjunta como `Authorization: Bearer …` en todas las peticiones siguientes. No necesitas pasar el token manualmente en cada llamada.

```dart
db.accessToken;  // String?
db.refreshToken; // String?

// Restaurar una sesión persistida (por ejemplo, desde SharedPreferences)
db.setTokens(accessToken: guardado.access, refreshToken: guardado.refresh);

// Descartar la sesión en memoria
db.clearTokens();

// Reaccionar a cada cambio del access token
db.onTokenUpdate = (token) => persistir(token);
```

**Refresco automático:** si una petición de datos responde `401` y hay un `refreshToken` disponible, el cliente llama a `refresh-token`, actualiza el `accessToken` y reintenta la petición **una sola vez**. Esto ocurre de forma interna: no existe un método público para refrescar a mano. Si el refresco falla, lanza `RobleApiAuthException` con el detalle.

El timeout por petición se configura en `RobleApiConfig.timeout` (30 segundos por defecto).

---

## 📚 Referencia de métodos

### Autenticación

| Método | Endpoint | Descripción |
| --- | --- | --- |
| `register({email, password, name, extra})` | `POST /signup-direct` | Registra un usuario sin verificación por correo. Devuelve el usuario creado. |
| `registerWithVerification({email, password, name, extra})` | `POST /signup` | Registra y envía un código de 6 dígitos por correo. |
| `verifyEmail({email, code})` | `POST /verify-email` | Confirma el correo con el código recibido. |
| `resendCode({email})` | `POST /resend-code` | Reenvía el código de verificación. |
| `login({email, password})` | `POST /login` | Inicia sesión y **almacena los tokens internamente**. Devuelve `{accessToken, refreshToken}`. |
| `currentUser()` | `GET /verify-token` | Datos del usuario autenticado (`sub`, `email`, `dbName`, `sessionId`). Único endpoint que expone la identidad. |
| `forgotPassword({email})` | `POST /forgot-password` | Envía el correo de restablecimiento. |
| `resetPassword({token, newPassword})` | `POST /reset-password` | Restablece la contraseña con el token del correo. |
| `logout()` | `POST /logout` | Cierra la sesión y limpia los tokens. Lanza `RobleApiAuthException` si no hay sesión activa. |
| `deleteAccount()` | `DELETE /account` | Elimina la cuenta permanentemente y limpia la sesión. Irreversible. |

El refresco del token es interno (ver [Manejo de tokens](#-manejo-de-tokens)); no se expone ningún método público para invocarlo.

Ambos métodos de registro aceptan un `extra` opcional con campos adicionales que el backend guarda junto al usuario:

```dart
await db.register(
	email: 'ana@mail.com',
	password: 'MiClave!1',
	name: 'Ana García',
	extra: {'rol': 'admin', 'programa': 'Ingeniería de Sistemas'},
);
```

```dart
await db.login(email: 'ana@mail.com', password: 'Password123!');
// db ya está autenticado a partir de aquí

await db.logout(); // cierra sesión y limpia los tokens
```

### Tablas

| Método | Endpoint | Descripción |
| --- | --- | --- |
| `createTable(tableName, columns)` | `POST /create-table` | Crea una tabla con las columnas indicadas. ⚠️ Endpoint no documentado por la API. |
| `createTableFromTemplate({tableName, templateTableName})` | `POST /create-table-from-template` | Clona la estructura de columnas de una tabla existente. Único mecanismo documentado para crear tablas. |
| `getTableData(tableName)` | `GET /table-data?schema=public&table=…` | Devuelve los datos de la tabla en el esquema `public`. ⚠️ Endpoint no documentado por la API. |

```dart
await db.createTable('usuarios_test', [
	{'name': 'nombre', 'type': 'text'},
	{'name': 'rol', 'type': 'text'},
]);

final filas = await db.getTableData('usuarios_test');
```

Cada columna es un mapa con al menos `name` y `type`. La descripción de la tabla se envía automáticamente.

### CRUD

| Método | Endpoint | Descripción |
| --- | --- | --- |
| `create(tableName, data)` | `POST /insert-one` | Inserta un registro y devuelve la fila creada, con su `_id`. |
| `createMany(tableName, records)` | `POST /insert` | Inserta varios registros. Devuelve `RobleInsertResult` con `inserted` y `skipped`. |
| `read(tableName, {filters})` | `GET /read` | Lee registros. Cada entrada de `filters` se envía como query param. Solo igualdad. |
| `publicRead(tableName, {filters})` | `GET /public-read` | Lee una tabla pública **sin autenticación**. Un `403` indica que la tabla no está marcada como pública. |
| `update(tableName, id, data)` | `PUT /update` | Actualiza por `_id`. Las claves `_id` e `id` se eliminan del cuerpo automáticamente. |
| `delete(tableName, id)` | `DELETE /delete` | Elimina el registro cuyo `_id` coincida. |
| `executeQuery(id, {params})` | `POST /execute-query` | Ejecuta una consulta guardada en la consola. Vía para joins, orden y paginación. |

> ⚠️ **`createMany` puede tener éxito parcial.** `/insert` responde `200` aunque rechace registros. Revisa siempre `skipped`:
>
> ```dart
> final res = await db.createMany('usuarios', registros);
> if (res.hasSkipped) {
>   for (final s in res.skipped) {
>     print('Fila ${s.index} rechazada: ${s.reason}');
>   }
> }
> ```

```dart
final creado = await db.create('usuarios', {'nombre': 'Juan', 'rol': 'admin'});

final admins = await db.read('usuarios', filters: {'rol': 'admin'});

await db.update('usuarios', creado['_id'], {'rol': 'editor'});
await db.delete('usuarios', creado['_id']);
```

`update` y `delete` identifican el registro siempre por la columna `_id`; no es configurable desde el paquete.

### Conveniencia

| Método | Equivale a | Descripción |
| --- | --- | --- |
| `getAll(tableName)` | `read(tableName)` | Todos los registros de la tabla. |
| `getById(tableName, id)` | `read(…, filters: {'_id': id})` | Un registro o `null` si no existe. |
| `getWhere(tableName, column, value)` | `read(…, filters: {column: value})` | Registros que coinciden con una columna. |

```dart
final todos = await db.getAll('usuarios');
final uno = await db.getById('usuarios', 'customid1234');
final editores = await db.getWhere('usuarios', 'rol', 'editor');
```

---

## ⚡ Realtime

El servicio Realtime es un árbol JSON por proyecto, con una API al estilo de Firebase Realtime Database. El primer segmento de la ruta es la colección.

```dart
final mensajes = db.realtime.ref('messages/general');

final id = await mensajes.push({'texto': 'Hola', 'autor': 'ana'});
await mensajes.child(id).update({'status': 'read'});

final todos = await mensajes.get();
final soloClaves = await mensajes.get(shallow: true);

await mensajes.child(id).remove();
```

| Método | HTTP | Descripción |
| --- | --- | --- |
| `db.realtime.ref([path])` | — | Referencia a una ruta. Sin argumentos, la raíz del proyecto. |
| `db.realtime.collections()` | `GET /realtime/{db}` | Nombres de las colecciones. |
| `db.realtime.health()` | `GET /realtime/health` | Estado de PostgreSQL, event bus y CDC. Sin autenticación. |
| `ref.get({shallow})` | `GET` | Valor JSON en la ruta. Con `shallow`, solo las claves inmediatas. |
| `ref.set(value)` | `PUT` | Sobrescribe. Crea la colección si no existe. |
| `ref.update(fields)` | `PATCH` | Fusiona campos con el objeto existente. |
| `ref.push(value)` | `POST` | Agrega un hijo con ID autogenerado. Devuelve el ID. |
| `ref.remove()` | `DELETE` | Elimina la ruta. Si es solo la colección, la elimina completa. |

Las referencias son inmutables y navegables: `ref.child('a/b')`, `ref.parent`, `ref.key`, `ref.path`.

Requiere que la configuración tenga `realtimeUrl`, que `RobleApiConfig.fromContract()` compone automáticamente.

### Suscripciones en tiempo real

Escuchar cambios abre un WebSocket contra el host de realtime. Ambas escuchas son `Stream`, así que se cancelan con `cancel()`.

```dart
// Valor del nodo: emite al suscribirse y tras cada cambio.
final sub = db.realtime.ref('messages/general').onValue.listen((valor) {
	setState(() => mensajes = valor);
});

await sub.cancel();
```

Para el evento crudo, sin releer nada:

```dart
final sub = db.realtime.ref('messages/general').onEvent.listen((e) {
	print('${e.operation.name} en ${e.pathString}: ${e.newValue}');
});
```

| Miembro | Descripción |
| --- | --- |
| `ref.onValue` | `Stream` con el valor actual del nodo al suscribirse y tras cada cambio. |
| `ref.onEvent` | `Stream<RobleRealtimeEvent>`: `operation`, `path`, `pathString`, `oldValue`, `newValue`, `raw`. |
| `db.realtime.status` | `RobleRealtimeStatus.disconnected/connecting/connected/error`. |
| `db.realtime.onStatusChange` | Callback en cada cambio de estado. |
| `db.realtime.close()` | Cierra el socket y cancela todas las escuchas. |

Una escucha recibe los cambios de su ruta **y de sus descendientes**. El socket se abre solo cuando hay al menos una escucha, se comparte entre todas, se resuscribe al reconectar y se cierra cuando no queda ninguna.

**`onValue` relee el nodo por REST tras cada evento.** El `newValue` del servidor es parcial y no distingue `PATCH` (fusiona) de `PUT` (sobrescribe), así que reconstruirlo en el cliente daría resultados incorrectos tras un `set()`. Si solo necesitas el evento, `onEvent` no hace ninguna petición extra.

> ⚠️ **`set()` solo acepta objetos y mapas/listas.** A diferencia de Firebase, el servidor rechaza un escalar como cuerpo: `set(0)`, `set(false)` y `set('texto')` devuelven `400`. Para guardar un valor suelto, envuélvelo: `ref.set({'valor': 0})`.

## ❌ Manejo de errores

Todas las llamadas lanzan una excepción que hereda de `RobleApiException`, así que puedes capturar el tipo concreto para reaccionar de forma distinta a cada fallo:

| Excepción | Cuándo se lanza | Mensaje |
| --- | --- | --- |
| `RobleApiNetworkException` | Sin red o DNS no resuelto | `Sin conexión a internet` |
| `RobleApiTimeoutException` | La petición supera los 30 s | `Tiempo de espera agotado` |
| `RobleApiFormatException` | La respuesta no se puede parsear | `Respuesta con formato inválido` |
| `RobleApiHttpException` | El servidor responde con un código fuera de 2xx | El `message` del servidor (o el cuerpo crudo). Expone además `statusCode`. |
| `RobleApiAuthException` | No hay refresh token, el refresco falla o su respuesta es inválida | `Token expirado y no se pudo refrescar: …` |
| `RobleApiException` | Cualquier otro error inesperado | `Error inesperado: …` |

```dart
try {
	final usuarios = await db.read('usuarios');
} on RobleApiHttpException catch (e) {
	debugPrint('El servidor respondió ${e.statusCode}: ${e.message}');
} on RobleApiAuthException catch (e) {
	debugPrint('Sesión expirada: ${e.message}');
	// redirigir al login…
} on RobleApiNetworkException {
	debugPrint('Revisa tu conexión.');
} on RobleApiException catch (e) {
	debugPrint('Fallo la lectura: ${e.message}');
}
```

Captura siempre `RobleApiException` al final como red de seguridad: es la clase base de todas las anteriores.

---

## 🧪 Testing

El constructor acepta un `http.Client` inyectado, lo que permite probar sin red:

```dart
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

final db = RobleApiDataBase(
	config: RobleApiConfig.fromStrings(
		baseAuthUrl: 'https://fake/auth/proj',
		baseDataUrl: 'https://fake/database/proj',
	),
	client: MockClient((request) async {
		return http.Response('[{"_id":"1","nombre":"Ana"}]', 200);
	}),
);

final usuarios = await db.read('usuarios');
```

---

## 📱 Ejemplo completo

El directorio [`example/`](example/) contiene una app Flutter que ejercita registro, login, logout, creación de tabla e inserción, y el ciclo CRUD completo, mostrando un log de cada operación.

```bash
cd example
flutter run
```

---
## 🛠️ Contribuciones

Las contribuciones son bienvenidas. Si encuentras un bug o quieres proponer una mejora:


## Resumen

`roble` es un cliente ligero para Flutter que simplifica las peticiones HTTPS hacia la plataforma Roble. No abstrae la lógica de negocio del backend: su objetivo es facilitar el consumo de endpoints estandarizados (auth + CRUD) con manejo consistente de errores y facilidad para testing.

¡Las contribuciones y mejoras son muy bienvenidas! 🚀

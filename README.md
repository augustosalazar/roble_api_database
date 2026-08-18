# 📦 roble

Cliente Flutter para la plataforma [ROBLE](https://roble.openlab.uninorte.edu.co/) de Uninorte OpenLab: autenticación y CRUD sobre PostgreSQL.

https://github.com/augustosalazar/roble_api_database

> 🔁 Existe un equivalente en JavaScript/TypeScript, [`roble-client`](https://github.com/augustosalazar/roble-api-database-ReNa), con los mismos métodos y las mismas excepciones.

## 🚀 Instalación

```bash
flutter pub add roble
```

```dart
import 'package:roble/roble.dart';
```

---

## 🧭 Quick start

```dart
final db = RobleApiDataBase(
	config: RobleApiConfig.fromContract(
		baseUrl: 'https://roble-api.test-openlab.uninorte.edu.co',
		contractId: 'tu_contrato',
	),
);

// 1. Registro
await db.register(
	email: 'ana@correo.com',
	password: 'MiClave!1',
	name: 'Ana García',
	extra: {'programa': 'Sistemas'},
);

// 2. Login: devuelve el perfil
final user = await db.login(email: 'ana@correo.com', password: 'MiClave!1');
print('Hola ${user['name']} (${user['userId']})');

// 3. CRUD
final creado = await db.create('usuarios', {'nombre': 'Ana', 'edad': 28});
final todos = await db.read('usuarios');
await db.update('usuarios', creado['_id'], {'edad': 29});
await db.delete('usuarios', creado['_id']);

// 4. Cerrar sesión
await db.logout();
```

Todos los métodos son asíncronos y lanzan alguna subclase de `RobleApiException`. Ver [Manejo de errores](#-manejo-de-errores).

---

## ⚙️ Configuración

`RobleApiConfig` es inmutable. Lo habitual es componerla desde el host y el identificador del contrato:

```dart
final config = RobleApiConfig.fromContract(
	baseUrl: 'https://roble-api.test-openlab.uninorte.edu.co',
	contractId: 'tu_contrato',
	timeout: Duration(seconds: 30),
);
```

| Parámetro | Tipo | Obligatorio | Descripción |
| --- | --- | --- | --- |
| `baseUrl` | `String` | sí | Host de la API. Una barra final se ignora. |
| `contractId` | `String` | sí | Identificador del contrato, con el que se componen las rutas de auth y de datos. |
| `timeout` | `Duration` | no | Tiempo máximo por petición. Por defecto 30 s. |

`Content-Type: application/json` y `Authorization: Bearer …` los gestiona el cliente; no hay que declararlos.

`fromContract` es la única forma de crear la configuración: las URLs se componen siempre a partir del host y del contrato.

### Constructor del cliente

```dart
RobleApiDataBase({
	required RobleApiConfig config,
	http.Client? client,          // solo para tests
	RobleTokenStorage? storage,   // solo para tests
})
```

Los tokens **no se exponen**. El paquete los guarda en el almacén seguro del sistema, los adjunta a cada petición, los renueva ante un `401` y los borra al cerrar sesión. Lo único que se consulta desde fuera es `db.isLoggedIn`.

---

## 🔐 Sesión

### `bool get isLoggedIn`

`true` si este cliente tiene una sesión iniciada. No consulta al servidor.

```dart
if (db.isLoggedIn) mostrarPerfil();
```

### `Future<bool> restoreSession({bool verify = true})`

Restaura la sesión guardada y **comprueba contra el servidor que siga viva**. Llámalo al arrancar la app.

| Parámetro | Tipo | Por defecto | Descripción |
| --- | --- | --- | --- |
| `verify` | `bool` | `true` | Si es `true`, renueva el access token contra el servidor. Con `false` solo lee el almacenamiento (más rápido, pero la sesión puede estar caducada). |

**Devuelve** `true` si la sesión sirve; `false` si no había sesión guardada o el refresh token ya no vale (en ese caso limpia la sesión).

**Errores**

| Excepción | Cuándo |
| --- | --- |
| `RobleApiNetworkException` | Sin conexión. **No borra la sesión**: distínguelo de "sesión caducada" y reintenta. |
| `RobleApiTimeoutException` | El servidor no respondió a tiempo. Tampoco borra la sesión. |

```dart
try {
	if (await db.restoreSession()) {
		irAlInicio();
	} else {
		irAlLogin();
	}
} on RobleApiNetworkException {
	mostrarPantallaSinConexion();
}
```

### Persistencia entre reinicios

**No hay que configurar nada.** El paquete guarda la sesión en el almacén seguro del sistema (Keychain en iOS/macOS, Keystore en Android, almacenamiento cifrado en web, gestor de secretos en escritorio) mediante `flutter_secure_storage`. El refresh token es la credencial de larga duración, así que no va a `SharedPreferences`.

El ciclo completo es:

```dart
final db = RobleApiDataBase(config: config);   // sin storage

await db.login(email: …, password: …);          // se guarda sola
// … la app se cierra y se vuelve a abrir …
await db.restoreSession();                      // vuelve la sesión
await db.logout();                              // se borra
```

En pruebas puedes sustituirlo por `RobleMemoryStorage`, que guarda en un `Map`:

```dart
final db = RobleApiDataBase(config: config, storage: RobleMemoryStorage());
```

Si el almacén no está disponible (por ejemplo en un test de Dart puro, sin plataforma), las operaciones fallan en silencio: la sesión sigue viva en memoria pero no se persiste.

---

## 🔑 Autenticación

### `register`

```dart
Future<Map<String, dynamic>> register({
	required String email,
	required String password,
	required String name,
	Map<String, dynamic>? extra,
	bool autoLogin = false,
	bool persistSession = true,
})
```

Registra un usuario **sin verificación por correo**. La cuenta queda activa de inmediato. `POST /signup-direct`.

| Parámetro | Tipo | Por defecto | Descripción |
| --- | --- | --- | --- |
| `email` | `String` | — | Correo del usuario. |
| `password` | `String` | — | Mínimo 8 caracteres, con mayúscula, minúscula, número y un símbolo de `! @ # $ _ - .` |
| `name` | `String` | — | Nombre visible. |
| `extra` | `Map<String, dynamic>?` | `null` | Campos adicionales que el backend guarda con el usuario y devuelve en `login` y `currentUser`. |
| `autoLogin` | `bool` | `false` | Si es `true`, inicia sesión al terminar el registro. |
| `persistSession` | `bool` | `true` | Solo se aplica con `autoLogin: true`. Igual que en [`login`](#login). |

**Devuelve** depende de `autoLogin`:

| `autoLogin` | Devuelve |
| --- | --- |
| `false` | El mensaje del servidor: `{'message': 'Usuario registrado correctamente.'}` |
| `true` | El perfil del usuario, lo mismo que [`login`](#login) |

Si el registro funciona pero el login automático falla, **la cuenta ya está creada**: el error se propaga y `db.isLoggedIn` sigue en `false`, así que basta con reintentar `login()` sin volver a registrar.

> `registerWithVerification` no tiene `autoLogin`: hasta validar el código del correo la cuenta no puede iniciar sesión.

**Errores**

| Excepción | Mensaje típico |
| --- | --- |
| `RobleApiHttpException` (400) | `El email ya está registrado` · contraseña que no cumple las reglas |
| `RobleApiHttpException` (500) | `Error interno al registrar el usuario.` |

```dart
// Registro y a la pantalla principal en un solo paso
final user = await db.register(
	email: 'ana@correo.com',
	password: 'MiClave!1',
	name: 'Ana García',
	extra: {'rol': 'estudiante', 'programa': 'Sistemas'},
	autoLogin: true,
);
print(user['userId']);
```

### `registerWithVerification`

Misma firma que [`register`], pero envía un código de 6 dígitos por correo. `POST /signup`. El usuario no queda activo hasta llamar a `verifyEmail`.

```dart
await db.registerWithVerification(
	email: 'ana@correo.com',
	password: 'MiClave!1',
	name: 'Ana García',
);
```

### `verifyEmail`

```dart
Future<Map<String, dynamic>> verifyEmail({
	required String email,
	required String code,
})
```

Confirma el correo con el código recibido. `POST /verify-email`.

**Errores**: `RobleApiHttpException` (400) si el código es inválido o expiró.

```dart
await db.verifyEmail(email: 'ana@correo.com', code: '123456');
```

### `resendCode`

```dart
Future<Map<String, dynamic>> resendCode({required String email})
```

Reenvía el código de verificación. `POST /resend-code`.

### `login`

```dart
Future<Map<String, dynamic>> login({
	required String email,
	required String password,
	bool persistSession = true,
})
```

Inicia sesión y **devuelve el perfil del usuario**. Hace `POST /login` y, con el token ya guardado, `GET /me`.

| Parámetro | Tipo | Por defecto | Descripción |
| --- | --- | --- | --- |
| `email` | `String` | — | Correo. |
| `password` | `String` | — | Contraseña. |
| `persistSession` | `bool` | `true` | Si la sesión debe sobrevivir al cierre de la app. Es el clásico "recordarme". |

Con `persistSession: false` la sesión vive **solo en memoria**: todo funciona igual mientras la app esté abierta, pero al reiniciar habrá que volver a entrar. Además **borra cualquier sesión guardada antes**, para que no quede una sesión anterior recuperable en el dispositivo.

```dart
await db.login(
	email: email,
	password: password,
	persistSession: recordarme, // p. ej. el valor de un checkbox
);
```

**Devuelve**

| Campo | Tipo | Descripción |
| --- | --- | --- |
| `userId` | `String` | Id del usuario. Es con lo que se comparan campos como `autorId`. |
| `email` | `String` | Correo. |
| `name` | `String` | Nombre. |
| `extra` | `Map?` | Lo enviado en `register`, o `null`. |
| `id` | `String` | Id del registro de perfil. |
| `createdAt` / `updatedAt` | `String` | Fechas ISO-8601. |

**Errores**

| Excepción | Cuándo |
| --- | --- |
| `RobleApiHttpException` (401) | Credenciales incorrectas. |
| `RobleApiNetworkException` | Sin conexión. |

Si `POST /login` funciona pero `GET /me` falla, **la sesión queda activa** y la excepción se propaga. `db.isLoggedIn` distingue los dos casos:

```dart
try {
	final user = await db.login(email: email, password: password);
	irAlInicio(user);
} catch (e) {
	if (db.isLoggedIn) {
		irAlInicio(await db.currentUser()); // credenciales OK, falló el perfil
	} else {
		mostrarError('Correo o contraseña incorrectos');
	}
}
```

### `currentUser`

```dart
Future<Map<String, dynamic>> currentUser()
```

Perfil del usuario autenticado. `GET /me`. Mismo mapa que devuelve `login`.

**Errores**: `RobleApiHttpException` (401) si no hay sesión válida.

### `logout`

```dart
Future<void> logout()
```

Cierra la sesión en el servidor y borra los tokens locales y del almacenamiento. `POST /logout`.

**Errores**: `RobleApiAuthException` — `No hay token activo para cerrar sesión.`

### `forgotPassword`

```dart
Future<Map<String, dynamic>> forgotPassword({required String email})
```

Envía el correo de restablecimiento. `POST /forgot-password`.

**Errores**: `RobleApiHttpException` (400) si el correo no está registrado.

### `resetPassword`

```dart
Future<Map<String, dynamic>> resetPassword({
	required String token,
	required String newPassword,
})
```

Restablece la contraseña con el token que llega en el enlace del correo. `POST /reset-password`.

**Errores**: `RobleApiHttpException` (400) si el token es inválido o expiró.

### `deleteAccount`

```dart
Future<void> deleteAccount()
```

Elimina la cuenta autenticada de forma permanente y limpia la sesión. `DELETE /account`. **No se puede deshacer**: pide confirmación antes de llamarla.

**Errores**: `RobleApiAuthException` — `No hay sesión activa para eliminar la cuenta.`

---

## 🗄️ Datos

### `create`

```dart
Future<Map<String, dynamic>> create(String tableName, Map<String, dynamic> data)
```

Inserta un registro y devuelve la fila creada, con su `_id`. `POST /insert-one`.

**Errores**: `RobleApiHttpException` (400) `Columnas inválidas: …` si algún campo no existe en la tabla; (500) si la tabla no existe.

```dart
final creado = await db.create('usuarios', {'nombre': 'Ana', 'edad': 28});
print(creado['_id']);
```

### `createMany`

```dart
Future<RobleInsertResult> createMany(
	String tableName,
	List<Map<String, dynamic>> records, {
	bool strict = false,
})
```

Inserta varios registros. `POST /insert`.

**Devuelve** `RobleInsertResult`:

| Campo | Tipo | Descripción |
| --- | --- | --- |
| `inserted` | `List<Map<String, dynamic>>` | Filas insertadas, con su `_id`. |
| `skipped` | `List<RobleSkippedRecord>` | Rechazadas: `index` y `reason`. |
| `hasSkipped` | `bool` | `true` si hubo rechazos. |

> ⚠️ El servidor responde `200` aunque rechace registros. **Revisa siempre `skipped`**, o usa `strict: true` para que no se te olvide.

Con `strict: true` un rechazo parcial deja de ser algo que haya que recordar mirar y pasa a ser un error:

```dart
try {
	await db.createMany('usuarios', registros, strict: true);
} on RoblePartialInsertException catch (e) {
	// e.result.inserted -> lo que SÍ se escribió (útil para deshacer)
	// e.result.skipped  -> qué se rechazó y por qué
	print(e.message);
}
```

Sin `strict` hay que comprobarlo a mano:

```dart
final res = await db.createMany('usuarios', registros);
if (res.hasSkipped) {
	for (final s in res.skipped) {
		print('Fila ${s.index} rechazada: ${s.reason}');
	}
}
```

### `read`

```dart
Future<List<Map<String, dynamic>>> read(
	String tableName, {
	Map<String, dynamic>? filters,
})
```

Lee registros. `GET /read`. Cada entrada de `filters` viaja como query param y **solo admite igualdad**: no hay `LIKE`, rangos, orden ni paginación. Para eso está [`executeQuery`](#executequery).

```dart
final admins = await db.read('usuarios', filters: {'rol': 'admin'});
```

**Errores**: `RobleApiHttpException` (400) si la tabla o una columna no existen.

### `update`

```dart
Future<Map<String, dynamic>> update(
	String tableName,
	dynamic id,
	Map<String, dynamic> data,
)
```

Actualiza el registro cuyo `_id` coincida. `PUT /update`. Las claves `_id` e `id` se eliminan del cuerpo automáticamente.

**Errores**: `RobleApiHttpException` (404) si el registro no existe.

### `delete`

```dart
Future<Map<String, dynamic>> delete(String tableName, dynamic id)
```

Elimina el registro cuyo `_id` coincida. `DELETE /delete`.

### `publicRead`

```dart
Future<List<Map<String, dynamic>>> publicRead(
	String tableName, {
	Map<String, dynamic>? filters,
})
```

Lee una tabla marcada como pública, **sin autenticación**. `GET /public-read`.

**Errores**: `RobleApiHttpException` (403) — `Esta tabla no está configurada para acceso público`. Es configuración de la tabla en la consola, no un problema de token.

### `executeQuery`

```dart
Future<RobleQueryResult> executeQuery(String id, {List<dynamic>? params})
```

Ejecuta una consulta guardada en la consola de Roble. `POST /execute-query`. Es la vía para joins, agregados, orden y paginación.

**Devuelve** `RobleQueryResult` con `success`, `command`, `rowCount`, `rows` y `fields`.

```dart
final res = await db.executeQuery(
	'ca7fe9c1-e740-4e50-82ba-bec89a0eec98',
	params: ['activo'],
);
print('${res.rowCount} filas');
```

---

## ❌ Manejo de errores

Todo lo que lanza el paquete hereda de `RobleApiException`, así que puedes capturar el tipo concreto:

| Excepción | Cuándo | Mensaje |
| --- | --- | --- |
| `RobleApiNetworkException` | Sin red o DNS no resuelto | `Sin conexión a internet` |
| `RobleApiTimeoutException` | Se supera `config.timeout` | `Tiempo de espera agotado` |
| `RobleApiFormatException` | Respuesta con forma inesperada | `Respuesta con formato inválido` · `No se pudo insertar el registro` · `El servidor no devolvió el ID generado.` |
| `RobleApiHttpException` | Código fuera de 2xx | El `message` del servidor. Expone además `statusCode`. |
| `RobleApiAuthException` | Problemas de sesión | `Token expirado y no se pudo refrescar: …` · `No hay token activo para cerrar sesión.` · `No hay refresh token disponible.` |
| `RoblePartialInsertException` | `createMany(strict: true)` con filas rechazadas | `El servidor rechazó 1 de 3 registros: fila 2 (…)`. Expone `result`. |
| `RobleApiException` | Cualquier otro | `Error inesperado: …` |

`RobleApiConfig.fromContract` lanza `ArgumentError` (no `RobleApiException`) si `baseUrl` no es una URL o si el `contractId` está vacío o sigue siendo un valor de ejemplo: es un fallo de programación, no del servidor.

Además, un `500` en autenticación es lo que devuelve Roble cuando **el contrato no existe**, así que a ese mensaje se le añade una pista:

```
Error inesperado al autenticar — revisa que el contractId sea correcto (mi_contrato_mal)
```

```dart
try {
	final usuarios = await db.read('usuarios');
} on RobleApiHttpException catch (e) {
	debugPrint('El servidor respondió ${e.statusCode}: ${e.message}');
} on RobleApiAuthException {
	irAlLogin();
} on RobleApiNetworkException {
	mostrarPantallaSinConexion();
} on RobleApiException catch (e) {
	debugPrint(e.message);
}
```

Captura siempre `RobleApiException` al final: es la clase base de todas.

**Refresco automático.** Si una petición de datos responde `401` y hay refresh token, el cliente renueva el access token y reintenta **una sola vez**. Es interno: no hay método público para refrescar a mano.

---

## 🧪 Testing

El constructor acepta un `http.Client` inyectado, así que se puede probar sin red:

```dart
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

final db = RobleApiDataBase(
	config: RobleApiConfig.fromContract(
		baseUrl: 'https://fake.test',
		contractId: 'proj',
	),
	storage: RobleMemoryStorage(), // evita tocar el almacén del sistema
	client: MockClient((request) async {
		return http.Response('[{"_id":"1","nombre":"Ana"}]', 200);
	}),
);

final usuarios = await db.read('usuarios');
```

---

## 📱 Ejemplo completo

[`example/`](example/) es una app Flutter que ejercita registro con `autoLogin`, login con "recordarme", restauración de sesión al arrancar, `currentUser`, el CRUD completo e inserción múltiple con registros rechazados, con un log de cada operación.

```bash
cd example
flutter run
```

---

## 👥 Autoría

Creado originalmente por [Arias3](https://github.com/Arias3).
Mantenido actualmente por **Augusto Salazar**
(<augustosalazar@uninorte.edu.co>), Universidad del Norte, como líder de
desarrollo.

---

## 🛠️ Contribuciones

Las contribuciones son bienvenidas. Abre un issue si encuentras un bug o quieres proponer una mejora.

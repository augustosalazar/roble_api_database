import 'package:flutter/material.dart';
import 'package:roble/roble.dart';

void main() {
  runApp(const RobleExampleApp());
}

class RobleExampleApp extends StatefulWidget {
  const RobleExampleApp({super.key});

  @override
  State<RobleExampleApp> createState() => _RobleExampleAppState();
}

/// 👇 Cámbialo por el identificador de tu proyecto en la consola de Roble.
const kContractId = 'tu_contrato';
const kBaseUrl = 'https://roble-api.test-openlab.uninorte.edu.co';

class _RobleExampleAppState extends State<RobleExampleApp> {
  RobleApiDataBase? _db;
  String? _errorConfig;

  String? _lastEmail;
  String _log = '';
  bool _recordarme = true;

  static const _tabla = 'usuarios_test';

  RobleApiDataBase get db => _db!;

  @override
  void initState() {
    super.initState();

    // fromContract avisa si el contrato no está configurado.
    try {
      _db = RobleApiDataBase(
        config: RobleApiConfig.fromContract(
          baseUrl: kBaseUrl,
          contractId: kContractId,
        ),
      );
    } on ArgumentError catch (e) {
      _errorConfig = '${e.message}\n\nEdita kContractId en example/lib/main.dart';
      return;
    }

    _restaurarSesion();
  }

  /// Al arrancar: si hay sesión guardada y sigue siendo válida, se reutiliza.
  Future<void> _restaurarSesion() async {
    try {
      final activa = await db.restoreSession();
      _appendLog(activa
          ? 'Sesión restaurada: ${(await db.currentUser())['email']}'
          : 'No hay sesión guardada.');
    } on RobleApiNetworkException {
      _appendLog('Sin conexión: no se pudo verificar la sesión.');
    }
  }

  void _appendLog(String text) {
    if (!mounted) return;
    setState(() => _log = '$_log$text\n');
  }

  // === AUTENTICACIÓN ===

  Future<void> _registrar() async {
    final email = 'test_${DateTime.now().millisecondsSinceEpoch}@mail.com';
    _appendLog('Registrando $email…');

    try {
      // autoLogin deja la sesión iniciada y devuelve el perfil.
      final user = await db.register(
        email: email,
        password: 'Password123!',
        name: 'Usuario Prueba',
        extra: {'origen': 'ejemplo-flutter'},
        autoLogin: true,
        persistSession: _recordarme,
      );
      _lastEmail = email;
      _appendLog('Registrado y dentro: ${user['name']} (${user['userId']})');
    } catch (e) {
      _appendLog('Error registrando: $e');
    }
  }

  Future<void> _login() async {
    if (_lastEmail == null) {
      _appendLog('Primero crea un usuario.');
      return;
    }

    try {
      final user = await db.login(
        email: _lastEmail!,
        password: 'Password123!',
        persistSession: _recordarme,
      );
      _appendLog('Sesión iniciada como ${user['name']}');
    } catch (e) {
      if (db.isLoggedIn) {
        _appendLog('Sesión iniciada, pero falló el perfil: $e');
      } else {
        _appendLog('Credenciales incorrectas: $e');
      }
    }
  }

  Future<void> _logout() async {
    if (!db.isLoggedIn) {
      _appendLog('No hay sesión activa.');
      return;
    }
    try {
      await db.logout();
      _appendLog('Sesión cerrada.');
    } catch (e) {
      _appendLog('Error cerrando sesión: $e');
    }
  }

  Future<void> _quienSoy() async {
    try {
      final user = await db.currentUser();
      _appendLog('${user['name']} · ${user['email']} · extra: ${user['extra']}');
    } catch (e) {
      _appendLog('Error: $e');
    }
  }

  // === DATOS ===

  Future<void> _probarCrud() async {
    if (!db.isLoggedIn) {
      _appendLog('Inicia sesión antes de probar el CRUD.');
      return;
    }

    try {
      final creado = await db.create(_tabla, {'nombre': 'Ana', 'rol': 'admin'});
      _appendLog('Creado: ${creado['_id']}');

      final todos = await db.read(_tabla);
      _appendLog('Leídos: ${todos.length} registros');

      await db.update(_tabla, creado['_id'], {'rol': 'editor'});
      _appendLog('Actualizado.');

      final uno = await db.getById(_tabla, creado['_id']);
      _appendLog('getById: ${uno?['rol']}');

      await db.delete(_tabla, creado['_id']);
      _appendLog('Eliminado.');
    } catch (e) {
      _appendLog('Error en CRUD: $e');
    }
  }

  Future<void> _insertarVarios() async {
    if (!db.isLoggedIn) {
      _appendLog('Inicia sesión antes de insertar.');
      return;
    }

    try {
      final res = await db.createMany(_tabla, [
        {'nombre': 'Uno', 'rol': 'admin'},
        {'nombre': 'Dos', 'columna_inexistente': 1},
      ]);

      _appendLog('Insertados: ${res.inserted.length}');
      if (res.hasSkipped) {
        for (final s in res.skipped) {
          _appendLog('  Fila ${s.index} rechazada: ${s.reason}');
        }
      }
    } catch (e) {
      _appendLog('Error insertando: $e');
    }
  }

  // === UI ===

  @override
  Widget build(BuildContext context) {
    if (_errorConfig != null) {
      return MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Roble · configuración')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(_errorConfig!)),
          ),
        ),
      );
    }

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Roble · ejemplo')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton(
                    onPressed: _registrar,
                    child: const Text('Registrar + entrar'),
                  ),
                  ElevatedButton(
                    onPressed: _login,
                    child: const Text('Iniciar sesión'),
                  ),
                  ElevatedButton(
                    onPressed: _quienSoy,
                    child: const Text('¿Quién soy?'),
                  ),
                  ElevatedButton(
                    onPressed: _logout,
                    child: const Text('Cerrar sesión'),
                  ),
                  ElevatedButton(
                    onPressed: _probarCrud,
                    child: const Text('Probar CRUD'),
                  ),
                  ElevatedButton(
                    onPressed: _insertarVarios,
                    child: const Text('Insertar varios'),
                  ),
                ],
              ),
              CheckboxListTile(
                value: _recordarme,
                onChanged: (v) => setState(() => _recordarme = v ?? true),
                title: const Text('Recordarme (persistSession)'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const Text('Log de operaciones:'),
              const SizedBox(height: 5),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(_log, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

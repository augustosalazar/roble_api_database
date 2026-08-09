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

class _RobleExampleAppState extends State<RobleExampleApp> {
  late RobleApiDataBase db;
  String? _accessToken;
  String? _lastEmail;
  String _log = '';

  @override
  void initState() {
    super.initState();
    db = RobleApiDataBase(
      config: RobleApiConfig.fromContract(
        baseUrl: 'https://roble-api.openlab.uninorte.edu.co',
        contractId: 'robleapidatabase_e13b5d56c6',
      ),
    );

    // El cliente avisa cada vez que cambia el access token.
    db.onTokenUpdate = (token) => setState(() => _accessToken = token);
  }

  void _appendLog(String text) {
    setState(() => _log = '$_log$text\n');
  }

  Future<void> _createUser() async {
    try {
      final email =
          'test_user_${DateTime.now().millisecondsSinceEpoch}@mail.com';
      _appendLog('Creando usuario: $email');
      final res = await db.register(
        email: email,
        password: 'Password123!',
        name: 'Usuario Prueba',
      );
      _lastEmail = email;
      _appendLog('Usuario creado correctamente: ${res['email']}');
    } catch (e) {
      _appendLog('Error creando usuario: $e');
    }
  }

  Future<void> _loginUser() async {
    if (_lastEmail == null) {
      _appendLog('Primero crea un usuario antes de iniciar sesión.');
      return;
    }

    try {
      _appendLog('Iniciando sesión con $_lastEmail...');
      await db.login(email: _lastEmail!, password: 'Password123!');
      _appendLog(
        ' Sesión iniciada. Token: ${_accessToken?.substring(0, 25)}...',
      );
    } catch (e) {
      _appendLog('Error al iniciar sesión: $e');
    }
  }

  Future<void> _logoutUser() async {
    if (_accessToken == null) {
      _appendLog('No hay sesión activa para cerrar.');
      return;
    }

    try {
      _appendLog('Cerrando sesión...');
      await db.logout();
      _appendLog(' Sesión cerrada correctamente.');
    } catch (e) {
      _appendLog('Error al cerrar sesión: $e');
    }
  }

  Future<void> _createTestTable() async {
    if (_accessToken == null) {
      _appendLog('Debes iniciar sesión antes de crear tablas.');
      return;
    }

    try {
      _appendLog('Creando tabla "usuarios_test"...');
      await db.createTable('usuarios_test', [
        {'name': 'nombre', 'type': 'text'},
        {'name': 'rol', 'type': 'text'},
      ]);
      _appendLog(' Tabla creada correctamente.');
    } catch (e) {
      _appendLog('Error creando tabla: $e');
    }
  }

  Future<void> _insertIntoTestTable() async {
    if (_accessToken == null) {
      _appendLog('Debes iniciar sesión antes de agregar datos.');
      return;
    }

    try {
      _appendLog('Insertando registro en "usuarios_test"...');
      final created = await db.create('usuarios_test', {
        'nombre': 'Carlos',
        'rol': 'tester',
      });
      _appendLog(' Registro agregado: $created');
    } catch (e) {
      _appendLog('Error insertando registro: $e');
    }
  }

  Future<void> _testCrud() async {
    if (_accessToken == null) {
      _appendLog('Debes iniciar sesión antes de probar CRUD.');
      return;
    }

    try {
      _appendLog('Creando registro...');
      final created = await db.create('usuarios_test', {
        'nombre': 'Juan',
        'rol': 'admin',
      });
      _appendLog(' Registro creado: $created');

      _appendLog('Leyendo registros...');
      final data = await db.read('usuarios_test');
      _appendLog(' Datos obtenidos: ${data.length} registros');

      _appendLog('Actualizando registro...');
      final updated = await db.update('usuarios_test', created['_id'], {
        'rol': 'editor',
      });
      _appendLog(' Registro actualizado: $updated');

      _appendLog('Eliminando registro...');
      final deleted = await db.delete('usuarios_test', created['_id']);
      _appendLog(' Registro eliminado: $deleted');
    } catch (e) {
      _appendLog('Error en CRUD: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Roble API Tester')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton(
                    onPressed: _createUser,
                    child: const Text('Crear usuario'),
                  ),
                  ElevatedButton(
                    onPressed: _loginUser,
                    child: const Text('Iniciar sesión'),
                  ),
                  ElevatedButton(
                    onPressed: _logoutUser,
                    child: const Text('Cerrar sesión'),
                  ),
                  ElevatedButton(
                    onPressed: _createTestTable,
                    child: const Text('Crear tabla de prueba'),
                  ),
                  ElevatedButton(
                    onPressed: _insertIntoTestTable,
                    child: const Text('Agregar dato a tabla'),
                  ),
                  ElevatedButton(
                    onPressed: _testCrud,
                    child: const Text('Probar CRUD'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Log de operaciones:'),
              ),
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

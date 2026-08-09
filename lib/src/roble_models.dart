/// Modelos de respuesta del paquete `roble`.

/// Registro que el servidor rechazó durante un `POST /insert`.
class RobleSkippedRecord {
  /// Posición del registro en la lista enviada.
  final int index;

  /// Motivo indicado por el servidor.
  final String reason;

  const RobleSkippedRecord({required this.index, required this.reason});

  factory RobleSkippedRecord.fromJson(Map<dynamic, dynamic> json) {
    return RobleSkippedRecord(
      index: json['index'] is int
          ? json['index'] as int
          : int.tryParse('${json['index']}') ?? -1,
      reason: '${json['reason'] ?? 'sin motivo'}',
    );
  }

  @override
  String toString() => 'RobleSkippedRecord(index: $index, reason: $reason)';
}

/// Resultado de insertar varios registros con [RobleApiDataBase.createMany].
///
/// El endpoint `/insert` responde `200` aunque haya rechazado registros, así
/// que siempre conviene revisar [skipped] antes de dar la escritura por buena.
class RobleInsertResult {
  /// Registros efectivamente insertados, con su `_id` generado.
  final List<Map<String, dynamic>> inserted;

  /// Registros rechazados, con su posición y motivo.
  final List<RobleSkippedRecord> skipped;

  const RobleInsertResult({required this.inserted, required this.skipped});

  /// `true` si el servidor rechazó al menos un registro.
  bool get hasSkipped => skipped.isNotEmpty;

  factory RobleInsertResult.fromJson(Map<dynamic, dynamic> json) {
    final rawInserted = json['inserted'];
    final rawSkipped = json['skipped'];

    return RobleInsertResult(
      inserted: rawInserted is List
          ? rawInserted
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[],
      skipped: rawSkipped is List
          ? rawSkipped
              .whereType<Map>()
              .map(RobleSkippedRecord.fromJson)
              .toList()
          : <RobleSkippedRecord>[],
    );
  }

  @override
  String toString() =>
      'RobleInsertResult(inserted: ${inserted.length}, skipped: ${skipped.length})';
}

/// Resultado de `POST /execute-query`.
class RobleQueryResult {
  final bool success;
  final String? command;
  final int rowCount;
  final List<dynamic> rows;
  final List<Map<String, dynamic>> fields;

  const RobleQueryResult({
    required this.success,
    required this.command,
    required this.rowCount,
    required this.rows,
    required this.fields,
  });

  factory RobleQueryResult.fromJson(Map<dynamic, dynamic> json) {
    final rawRows = json['rows'];
    final rawFields = json['fields'];

    return RobleQueryResult(
      success: json['success'] == true,
      command: json['command'] as String?,
      rowCount: json['rowCount'] is int
          ? json['rowCount'] as int
          : int.tryParse('${json['rowCount']}') ?? 0,
      rows: rawRows is List ? List<dynamic>.from(rawRows) : const [],
      fields: rawFields is List
          ? rawFields
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[],
    );
  }

  @override
  String toString() =>
      'RobleQueryResult(command: $command, rowCount: $rowCount)';
}

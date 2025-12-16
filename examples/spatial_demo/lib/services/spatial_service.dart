
import 'dart:io';
import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class SpatialService {
  static final SpatialService _instance = SpatialService._internal();

  factory SpatialService() {
    return _instance;
  }

  SpatialService._internal();

  Database? _db;
  Connection? _connection;

  Future<void> initialize() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDocDir.path, 'demo.duckdb');
    
    // Check if we need to copy a pre-populated DB from assets
    // NOTE: For this demo, we assume the user might manually push the DB
    // or we create a fresh one. The node script prepares it.
    // If you bundle it in assets, uncomment below:
    /*
    if (!await File(dbPath).exists()) {
      try {
        final byteData = await rootBundle.load('assets/demo.duckdb');
        final file = File(dbPath);
        await file.writeAsBytes(byteData.buffer.asUint8List());
      } catch (e) {
        print('No asset DB found, starting fresh: $e');
      }
    }
    */

    // Use the global `duckdb` getter to open a database
    _db = await duckdb.open(dbPath);
    _connection = await duckdb.connect(_db!);
    
    // Initialize spatial extension
    try {
      await _connection!.execute("INSTALL spatial;");
      await _connection!.execute("LOAD spatial;");
      print("Spatial extension loaded successfully.");
    } catch (e) {
      print("Error loading spatial extension: $e");
    }
    // Initialize user tables
    await _initTables();
  }

  Future<void> _initTables() async {
    await _connection!.execute("""
      CREATE TABLE IF NOT EXISTS user_drawings (
        id INTEGER PRIMARY KEY,
        name VARCHAR,
        type VARCHAR,
        geom GEOMETRY,
        created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
      );
      CREATE SEQUENCE IF NOT EXISTS user_drawings_id_seq START 1;
    """);
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      // Check if tables exist first
      // In a real scenario, we might query information_schema, but for now we try/catch
      int countries = 0;
      int cities = 0;
      
      try {
        final r1 = await query("SELECT count(*) as c FROM ne_admin_0_countries");
        if (r1.isNotEmpty) countries = r1.first['c'] as int;
      } catch (_) {} 

      try {
        final r2 = await query("SELECT count(*) as c FROM ne_populated_places");
        if (r2.isNotEmpty) cities = r2.first['c'] as int;
      } catch (_) {}

      final versionResult = await query("SELECT ST_AsText(ST_Point(0,0))");
      final loaded = versionResult.isNotEmpty;

      return {
        'countries': countries,
        'cities': cities,
        'version': {'loaded': loaded, 'version': '1.0.0'} // Mock version for now
      };
    } catch (e) {
      print("Stats error: $e");
      return {'countries': 0, 'cities': 0, 'version': {'loaded': false}};
    }
  }

  Future<void> saveDrawing(String name, String type, String wkt) async {
    // Generate ID manually or let sequence handle it if supported properly
    // Using simple parameterized query if supported, else string interpolation (careful with SQL injection in demo)
    await query("INSERT INTO user_drawings (id, name, type, geom) VALUES (nextval('user_drawings_id_seq'), '$name', '$type', ST_GeomFromText('$wkt'))");
  }

  Future<List<Map<String, dynamic>>> getDrawings() async {
    return await query("SELECT id, name, type, ST_AsText(geom) as wkt FROM user_drawings ORDER BY created_at DESC");
  }
  
  Future<void> deleteDrawing(int id) async {
    await query("DELETE FROM user_drawings WHERE id = $id");
  }
  
  Future<List<Map<String, dynamic>>> getLayerData(String table) async {
    // Limit to 500 for demo performance on mobile
    return await query("SELECT *, ST_AsText(geom) as wkt FROM $table LIMIT 500");
  }

  Connection get connection {
    if (_connection == null) {
      throw Exception("SpatialService not initialized. Call initialize() first.");
    }
    return _connection!;
  }
  
  void dispose() {
    _connection?.dispose();
    _db?.dispose();
  }

  Future<List<Map<String, dynamic>>> query(String sql) async {
    try {
      final result = await _connection!.query(sql);
      final rows = <Map<String, dynamic>>[];
      final columns = result.columnNames;
      
      // Fetch all data as List<List<Object?>>
      final allRows = result.fetchAll();
      
      for (final rowValues in allRows) {
         final rowMap = <String, dynamic>{};
         for (int i = 0; i < columns.length; i++) {
           if (i < rowValues.length) {
             rowMap[columns[i]] = rowValues[i];
           }
         }
         rows.add(rowMap);
      }
      return rows;
    } catch (e) {
      print("Query error: $e");
      rethrow;
    }
  }
}

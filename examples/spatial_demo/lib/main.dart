
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/spatial_service.dart';
import 'widgets/stats_bar.dart';
import 'widgets/drawing_toolbar.dart';
import 'widgets/layer_sheet.dart';
import 'widgets/function_demos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpatialDemoApp());
}

class SpatialDemoApp extends StatelessWidget {
  const SpatialDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spatial Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SpatialHomePage(),
    );
  }
}

class SpatialHomePage extends StatefulWidget {
  const SpatialHomePage({super.key});

  @override
  State<SpatialHomePage> createState() => _SpatialHomePageState();
}

class _SpatialHomePageState extends State<SpatialHomePage> {
  final SpatialService _spatialService = SpatialService();
  final MapController _mapController = MapController();
  
  // State
  Map<String, dynamic>? _stats;
  DrawingMode _drawingMode = DrawingMode.none;
  final Map<String, bool> _layerVisibility = {
    'Countries': false,
    'Cities': false,
    'User Drawings': true,
  };
  
  // Data
  final List<Marker> _markers = [];
  final List<Polyline> _polylines = [];
  final List<Polygon> _polygons = [];

  @override
  void initState() {
    super.initState();
    _initDuckDB();
  }

  Future<void> _initDuckDB() async {
    await _spatialService.initialize();
    await _refreshStats();
    await _loadUserDrawings();
  }

  Future<void> _refreshStats() async {
    final s = await _spatialService.getStats();
    setState(() => _stats = s);
  }

  Future<void> _loadUserDrawings() async {
    if (!_layerVisibility['User Drawings']!) {
      setState(() {
         // Clear only user markers if we tracked sources, but for simple demo we just clear/redraw logic
         // For now, simpler to just reload what's needed.
         // A robust app would keep separate lists per layer.
      });
      return; 
    }
    
    final drawings = await _spatialService.getDrawings();
    _parseAndAddGeometries(drawings, color: Colors.red);
  }
  
  Future<void> _loadTableLayer(String layerName, String tableName, Color color) async {
    if (!_layerVisibility[layerName]!) return;
    
    final data = await _spatialService.getLayerData(tableName);
    _parseAndAddGeometries(data, color: color);
  }

  void _parseAndAddGeometries(List<Map<String, dynamic>> rows, {required Color color}) {
    for (final row in rows) {
      final wkt = row['wkt'] as String?;
      if (wkt == null) continue;
      
      try {
        if (wkt.startsWith('POINT')) {
          final pt = _parsePoint(wkt);
          _markers.add(Marker(
            point: pt,
            width: 40,
            height: 40,
            child: Icon(Icons.location_on, color: color),
            // In a real app we'd add interaction here
          ));
        } else if (wkt.startsWith('LINESTRING')) {
           // Basic parsing for demo
        } else if (wkt.startsWith('POLYGON')) {
           // Basic parsing for demo
        }
      } catch (e) {
        print("Error parsing WKT: $e");
      }
    }
    setState(() {});
  }
  
  LatLng _parsePoint(String wkt) {
    // POINT (x y)  -> remove POINT (, remove ), split space
    final content = wkt.substring(7, wkt.length - 1);
    final parts = content.split(' ');
    // WKT is Long Lat (X Y), LatLng is Lat Long
    return LatLng(double.parse(parts[1]), double.parse(parts[0]));
  }

  Future<void> _handleMapTap(TapPosition tapPos, LatLng point) async {
    if (_drawingMode == DrawingMode.point) {
      // Save point
      final wkt = "POINT(${point.longitude} ${point.latitude})";
      await _spatialService.saveDrawing("Point ${DateTime.now()}", "point", wkt);
      await _refreshStats();
      
      setState(() {
        _markers.add(Marker(
            point: point,
            width: 40,
            height: 40,
            child: const Icon(Icons.location_on, color: Colors.blue),
        ));
      });
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Point Saved!")));
    }
  }

  Future<void> _onRunQuery(String sql) async {
    Navigator.pop(context); // Close sheet
    try {
      final res = await _spatialService.query(sql);
      // If result has geometry, show it. If scalar, show toast.
      if (res.isNotEmpty && res.first.containsKey('result')) {
         final val = res.first['result'].toString();
         if (val.startsWith('POINT') || val.startsWith('LINE') || val.startsWith('POLY')) {
            // Visualize
            _markers.clear(); // Reset for demo clarity
            _parseAndAddGeometries([{'wkt': val}], color: Colors.green);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Result: $val (Visualized)")));
         } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Result: $val")));
         }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(0, 0),
              initialZoom: 2.0,
              onTap: _handleMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.spatial_demo',
              ),
              PolygonLayer(polygons: _polygons),
              PolylineLayer(polylines: _polylines),
              MarkerLayer(markers: _markers),
            ],
          ),
          
          // Stats Bar at top
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: StatsBar(stats: _stats),
          ),

          // Drawing Toolbar at bottom center
          Positioned(
            bottom: 30,
            left: 20,
            right: 80, // Leave room for FAB
            child: Center(
              child: DrawingToolbar(
                currentMode: _drawingMode,
                onModeChange: (m) => setState(() => _drawingMode = m),
                onClear: () {
                  setState(() {
                    _markers.clear();
                    _polylines.clear();
                    _polygons.clear();
                  });
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "layers",
            mini: true,
            child: const Icon(Icons.layers),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => LayerSheet(
                  layerVisibility: _layerVisibility,
                  onToggle: (layer, visible) {
                    setState(() => _layerVisibility[layer] = visible);
                    Navigator.pop(context);
                    // Trigger reload logic based on visibility
                    if (layer == 'Cities' && visible) _loadTableLayer('Cities', 'ne_populated_places', Colors.orange);
                    if (layer == 'Countries' && visible) _loadTableLayer('Countries', 'ne_admin_0_countries', Colors.blue); // Simplified as markers for now
                    if (layer == 'User Drawings') {
                       if (visible) _loadUserDrawings();
                       else _markers.clear(); // Naive clear
                    }
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "funcs",
            child: const Icon(Icons.functions),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => FunctionDemos(onRunQuery: _onRunQuery),
              );
            },
          ),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import '../services/spatial_service.dart';

class FunctionDemos extends StatelessWidget {
  final Function(String) onRunQuery;

  const FunctionDemos({super.key, required this.onRunQuery});

  final List<Map<String, dynamic>> categories = const [
    {
      'title': 'Constructors',
      'icon': Icons.build,
      'color': Colors.blue,
      'queries': [
        {'name': 'ST_Point', 'sql': "SELECT ST_AsText(ST_Point(10, 20)) as result"},
        {'name': 'ST_MakeLine', 'sql': "SELECT ST_AsText(ST_MakeLine(ST_Point(0,0), ST_Point(10,10))) as result"},
        {'name': 'ST_MakeEnvelope', 'sql': "SELECT ST_AsText(ST_MakeEnvelope(0,0,10,10)) as result"},
      ]
    },
    {
      'title': 'Measurements',
      'icon': Icons.straighten,
      'color': Colors.orange,
      'queries': [
        {'name': 'ST_Distance', 'sql': "SELECT ST_Distance(ST_Point(0,0), ST_Point(10,10)) as result"},
        {'name': 'ST_Area', 'sql': "SELECT ST_Area(ST_MakeEnvelope(0,0,10,10)) as result"},
        {'name': 'ST_Length', 'sql': "SELECT ST_Length(ST_MakeLine(ST_Point(0,0), ST_Point(10,0))) as result"},
      ]
    },
    {
      'title': 'Predicates',
      'icon': Icons.compare_arrows,
      'color': Colors.purple,
      'queries': [
        {'name': 'ST_Intersects', 'sql': "SELECT ST_Intersects(ST_Point(5,5), ST_MakeEnvelope(0,0,10,10)) as result"},
        {'name': 'ST_Contains', 'sql': "SELECT ST_Contains(ST_MakeEnvelope(0,0,10,10), ST_Point(5,5)) as result"},
      ]
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text("Spatial Functions", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ExpansionTile(
                    leading: Icon(cat['icon'], color: cat['color']),
                    title: Text(cat['title']),
                    children: (cat['queries'] as List).map((q) {
                      return ListTile(
                        title: Text(q['name']),
                        subtitle: Text(q['sql'], style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () => onRunQuery(q['sql']),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

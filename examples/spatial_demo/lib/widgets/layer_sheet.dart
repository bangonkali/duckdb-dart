
import 'package:flutter/material.dart';

class LayerSheet extends StatefulWidget {
  final Map<String, bool> layerVisibility;
  final Function(String, bool) onToggle;

  const LayerSheet({
    super.key,
    required this.layerVisibility,
    required this.onToggle,
  });

  @override
  State<LayerSheet> createState() => _LayerSheetState();
}

class _LayerSheetState extends State<LayerSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Map Layers", style: Theme.of(context).textTheme.titleLarge),
          const Divider(),
          ...widget.layerVisibility.entries.map((entry) {
            return SwitchListTile(
              title: Text(entry.key),
              value: entry.value,
              onChanged: (val) => widget.onToggle(entry.key, val),
              secondary: Icon(_getIconForLayer(entry.key)),
            );
          }).toList(),
          const SizedBox(height: 16),
          const Text("Data Source: Natural Earth (CC0)", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  IconData _getIconForLayer(String layer) {
    if (layer.toLowerCase().contains('country')) return Icons.public;
    if (layer.toLowerCase().contains('city')) return Icons.location_city;
    if (layer.toLowerCase().contains('user')) return Icons.edit;
    return Icons.layers;
  }
}


import 'package:flutter/material.dart';

enum DrawingMode { none, point, linestring, polygon }

class DrawingToolbar extends StatelessWidget {
  final DrawingMode currentMode;
  final Function(DrawingMode) onModeChange;
  final VoidCallback onClear;

  const DrawingToolbar({
    super.key,
    required this.currentMode,
    required this.onModeChange,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(DrawingMode.none, Icons.pan_tool, "Pan"),
            _buildButton(DrawingMode.point, Icons.place, "Point"),
            // Ideally we'd have Line/Polygon too, but 'flutter_map' simple tap interactions 
            // are best for points initially. We can add line/poly logic later.
            // _buildButton(DrawingMode.linestring, Icons.timeline, "Line"),
            // _buildButton(DrawingMode.polygon, Icons.hexagon_outlined, "Poly"),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: onClear,
              tooltip: "Clear Selection",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(DrawingMode mode, IconData icon, String tooltip) {
    final isSelected = currentMode == mode;
    return IconButton(
      icon: Icon(icon),
      color: isSelected ? Colors.blue : Colors.grey,
      tooltip: tooltip,
      onPressed: () => onModeChange(mode),
    );
  }
}

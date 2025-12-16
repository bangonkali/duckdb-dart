
import 'package:flutter/material.dart';

class StatsBar extends StatelessWidget {
  final Map<String, dynamic>? stats;

  const StatsBar({super.key, this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();

    final version = stats!['version'] is Map ? stats!['version']['version'] : 'Unknown';
    final countries = stats!['countries'] ?? 0;
    final cities = stats!['cities'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white.withOpacity(0.9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildChip(
            icon: Icons.public,
            label: "v$version",
            color: Colors.green,
          ),
          _buildChip(
            icon: Icons.map,
            label: "$countries Countries",
            color: Colors.blue,
          ),
          _buildChip(
            icon: Icons.location_city,
            label: "$cities Cities",
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildChip({required IconData icon, required String label, required Color color}) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.white),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withOpacity(0.8),
      padding: const EdgeInsets.all(0),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

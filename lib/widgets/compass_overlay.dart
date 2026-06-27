import 'package:flutter/material.dart';

class CompassOverlay extends StatelessWidget {
  final double heading;

  const CompassOverlay({super.key, required this.heading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Bearing: ${heading.toStringAsFixed(0)}°',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Icon(Icons.explore, color: Colors.white70),
        ],
      ),
    );
  }
}

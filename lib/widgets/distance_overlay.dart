import 'package:flutter/material.dart';

class DistanceOverlay extends StatelessWidget {
  final double currentDistance;
  final double targetDistance;
  final bool withinTolerance;
  final bool targetPinned;

  const DistanceOverlay({
    super.key,
    required this.currentDistance,
    required this.targetDistance,
    required this.withinTolerance,
    required this.targetPinned,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = withinTolerance ? Colors.greenAccent : Colors.redAccent;
    final measuredDistanceCm = currentDistance * 100.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Distance: ${measuredDistanceCm.toStringAsFixed(0)} cm / ${currentDistance.toStringAsFixed(2)} m  Target: ${targetDistance.toStringAsFixed(0)} cm',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            targetPinned
                ? 'Within ±10% tolerance to enable capture'
                : 'Pin a target location to enable capture',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

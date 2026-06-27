import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/captured_image.dart';

class ImageCard extends StatelessWidget {
  final CapturedImage image;
  final VoidCallback onTap;

  const ImageCard({super.key, required this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(image.imagePath),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
          ),
        ),
        title: Text('${image.latitude.toStringAsFixed(5)}, ${image.longitude.toStringAsFixed(5)}'),
        subtitle: Text(
          'Dist: ${image.distanceCm.toStringAsFixed(0)}cm • Bearing: ${image.bearingAngle.toStringAsFixed(0)}°\nHeight: ${image.heightDelta.toStringAsFixed(0)}cm\n${DateFormat('yyyy-MM-dd HH:mm').format(image.timestamp)}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.arrow_forward_ios, size: 18),
      ),
    );
  }
}

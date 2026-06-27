import 'dart:io';

import 'package:flutter/material.dart';

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
            File(image.path),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
          ),
        ),
        title: Text('${image.latitudeString}, ${image.longitudeString}'),
        subtitle: Text(
          'Album: ${image.albumName}\nDist: ${image.distanceString} • Angle: ${image.angleString}\n${image.timestamp.toLocal()}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.arrow_forward_ios, size: 18),
      ),
    );
  }
}

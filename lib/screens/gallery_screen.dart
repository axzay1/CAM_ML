import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/captured_image.dart';
import '../providers/camera_app_state.dart';
import '../widgets/image_card.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraAppState>(builder: (context, state, child) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gallery')),
        body: state.albums.isEmpty
            ? const Center(
                child: Text('No albums yet.', style: TextStyle(fontSize: 16)),
              )
            : ListView.builder(
                itemCount: state.albums.length,
                itemBuilder: (context, index) {
                  final album = state.albums[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    child: ListTile(
                      title: Text(album.name),
                      subtitle: Text('${album.captures.length} captures'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _renameAlbum(context, state, album),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
                        );
                      },
                    ),
                  );
                },
              ),
      );
    });
  }

  void _renameAlbum(BuildContext context, CameraAppState state, PinAlbum album) {
    final controller = TextEditingController(text: album.name);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename album'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Album name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                state.renameAlbum(album.id, controller.text);
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class AlbumDetailScreen extends StatelessWidget {
  final PinAlbum album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(album.name)),
      body: album.captures.isEmpty
          ? const Center(child: Text('No captures in this album yet.'))
          : ListView.builder(
              itemCount: album.captures.length,
              itemBuilder: (context, index) {
                final capture = album.captures[index];
                return ImageCard(
                  image: capture,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ImageDetailScreen(image: capture)),
                    );
                  },
                );
              },
            ),
    );
  }
}

class ImageDetailScreen extends StatelessWidget {
  final CapturedImage image;

  const ImageDetailScreen({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capture Details')),
      body: Column(
        children: [
          Expanded(
            child: Image.file(
              File(image.path),
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image, size: 64)),
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Album: ${image.albumName}', style: const TextStyle(color: Colors.white)),
                Text('Latitude: ${image.latitudeString}', style: const TextStyle(color: Colors.white)),
                Text('Longitude: ${image.longitudeString}', style: const TextStyle(color: Colors.white)),
                Text('Distance: ${image.distanceString}', style: const TextStyle(color: Colors.white)),
                Text('Angle: ${image.angleString}', style: const TextStyle(color: Colors.white)),
                Text('Timestamp: ${image.timestamp.toLocal()}', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

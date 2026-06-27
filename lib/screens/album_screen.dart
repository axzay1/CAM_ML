import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../providers/camera_provider.dart';
import '../widgets/glass_container.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('My Albums'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
      body: Consumer<CameraProvider>(
        builder: (context, provider, _) {
          if (provider.albums.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, color: Colors.white70, size: 52),
                  SizedBox(height: 8),
                  Text('No albums yet', style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 100, 12, 20),
            itemCount: provider.albums.length,
            itemBuilder: (context, index) {
              final Album album = provider.albums[index];
              final bool uploaded = provider.isAlbumUploaded(album.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      _thumbGrid(album),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _badge('${album.images.length} photos', Colors.white24),
                          const SizedBox(width: 8),
                          _badge(
                            album.isComplete ? 'Complete' : 'In Progress',
                            album.isComplete ? const Color(0xFF4CAF50) : Colors.amber,
                          ),
                          const Spacer(),
                          if (album.isComplete && !uploaded)
                            IconButton.filledTonal(
                              onPressed: () => _uploadAlbum(context, provider, album),
                              icon: const Icon(Icons.cloud_upload),
                              tooltip: 'Upload',
                            ),
                          IconButton.filledTonal(
                            onPressed: () => provider.deleteAlbum(album.id),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _thumbGrid(Album album) {
    final List<String> paths = album.images.take(4).map((e) => e.imagePath).toList();
    while (paths.length < 4) {
      paths.add('');
    }

    return SizedBox(
      height: 120,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemBuilder: (_, i) {
          if (paths[i].isEmpty) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white24,
              ),
              child: const Icon(Icons.image_outlined, color: Colors.white54),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(paths[i]),
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }

  Future<void> _uploadAlbum(BuildContext context, CameraProvider provider, Album album) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          content: Consumer<CameraProvider>(
            builder: (_, p, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('Uploading... ${p.uploadProgress.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white)),
                ],
              );
            },
          ),
        );
      },
    );

    try {
      final String link = await provider.uploadAlbum(album);
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Upload Complete'),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

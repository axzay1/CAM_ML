import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../providers/camera_provider.dart';
import '../widgets/glass_container.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key});

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(String albumId) {
    try {
      final DateTime d =
          DateTime.fromMillisecondsSinceEpoch(int.parse(albumId));
      final String h = d.hour.toString().padLeft(2, '0');
      final String m = d.minute.toString().padLeft(2, '0');
      return '${_months[d.month - 1]} ${d.day}, ${d.year}  $h:$m';
    } catch (_) {
      return albumId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Albums',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 17),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
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
                  Icon(Icons.photo_library_outlined,
                      color: Colors.white24, size: 60),
                  SizedBox(height: 14),
                  Text('No albums yet',
                      style: TextStyle(color: Colors.white38, fontSize: 15)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 72,
              left: 14,
              right: 14,
              bottom: 24,
            ),
            itemCount: provider.albums.length,
            itemBuilder: (context, index) {
              final Album album = provider.albums[index];
              final bool uploaded = provider.isAlbumUploaded(album.id);
              return _AlbumCard(
                album: album,
                uploaded: uploaded,
                dateLabel: _formatDate(album.id),
                onUpload: album.isComplete && !uploaded
                    ? () => _uploadAlbum(context, provider, album)
                    : null,
                onDelete: () => _confirmDelete(context, provider, album),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, CameraProvider provider, Album album) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Album?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently remove all captured photos.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      provider.deleteAlbum(album.id);
    }
  }

  Future<void> _uploadAlbum(
      BuildContext context, CameraProvider provider, Album album) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        content: Consumer<CameraProvider>(
          builder: (_, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                  color: Color(0xFF00BCD4)),
              const SizedBox(height: 14),
              Text(
                'Uploading ${p.uploadProgress.toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final String link = await provider.uploadAlbum(album);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Uploaded',
              style: TextStyle(color: Colors.white)),
          content: SelectableText(link,
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

// ── Album card ────────────────────────────────────────────────────────────────

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.uploaded,
    required this.dateLabel,
    required this.onUpload,
    required this.onDelete,
  });

  final Album album;
  final bool uploaded;
  final String dateLabel;
  final VoidCallback? onUpload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final double progress = album.totalPoints > 0
        ? album.images.length / album.totalPoints
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassContainer(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: date + status ──────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.photo_camera_outlined,
                    color: Colors.white38, size: 13),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dateLabel,
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                _StatusBadge(
                    isComplete: album.isComplete, uploaded: uploaded),
              ],
            ),
            const SizedBox(height: 10),

            // ── Photo strip ────────────────────────────────────────────────
            if (album.images.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: album.images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 5),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(album.images[i].imagePath),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('No photos yet',
                      style:
                          TextStyle(color: Colors.white24, fontSize: 12)),
                ),
              ),

            const SizedBox(height: 10),

            // ── Progress ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        album.isComplete
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF00BCD4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${album.images.length}/${album.totalPoints}',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Actions ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (uploaded) ...[
                  const _ActionChip(
                    icon: Icons.cloud_done_outlined,
                    label: 'Uploaded',
                    color: Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 8),
                ] else if (onUpload != null) ...[
                  _ActionChip(
                    icon: Icons.cloud_upload_outlined,
                    label: 'Upload',
                    color: const Color(0xFF00BCD4),
                    onTap: onUpload,
                  ),
                  const SizedBox(width: 8),
                ],
                _ActionChip(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: Colors.redAccent,
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isComplete, required this.uploaded});
  final bool isComplete;
  final bool uploaded;

  @override
  Widget build(BuildContext context) {
    final Color color = uploaded
        ? const Color(0xFF4CAF50)
        : isComplete
            ? const Color(0xFF00BCD4)
            : Colors.amber;
    final String label =
        uploaded ? 'Uploaded' : isComplete ? 'Complete' : 'In Progress';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

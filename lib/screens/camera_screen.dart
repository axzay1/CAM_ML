import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/camera_provider.dart';
import '../widgets/glass_container.dart';
import '../widgets/guide_arrow_3d.dart';
import 'album_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  Future<void>? _cameraInit;
  late final AnimationController _pinPulse;

  @override
  void initState() {
    super.initState();
    _pinPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _cameraInit = _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      return;
    }
    _cameraController = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
    await _cameraController!.initialize();
  }

  @override
  void dispose() {
    _pinPulse.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Color _distanceColor(CameraProvider provider) {
    final double delta = (provider.currentDistanceCm - provider.targetDistanceCm).abs();
    if (delta <= 15) {
      return const Color(0xFF4CAF50);
    }
    if (delta <= 30) {
      return Colors.amber;
    }
    return const Color(0xFFE53935);
  }

  Future<void> _runCalibrationDialog(CameraProvider provider) async {
    if (!mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sensors, color: Colors.white, size: 38),
                  const SizedBox(height: 10),
                  const Text(
                    'Calibrating sensors...',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Hold the phone still for 2 seconds',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(seconds: 2),
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00BCD4)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    await provider.setPoint(provider.currentLatitude, provider.currentLongitude, provider.currentBearing);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openTargetDistanceDialog(BuildContext context, CameraProvider provider) async {
    double tempValue = provider.targetDistanceCm;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Set Target Distance', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    Text('${tempValue.toStringAsFixed(0)} cm', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    Slider(
                      min: 50,
                      max: 500,
                      divisions: 90,
                      value: tempValue,
                      onChanged: (value) {
                        setDialogState(() {
                          tempValue = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () {
                        provider.setTargetDistance(tempValue);
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openCaptureDeckDialog(BuildContext context, CameraProvider provider) async {
    final album = provider.currentAlbum;
    if (album == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Captured Images', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 240,
                  width: 280,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: album.images.length,
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(album.images[index].imagePath),
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: album.isComplete
                          ? () async {
                              Navigator.pop(dialogContext);
                              try {
                                final link = await provider.uploadAlbum();
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded: $link')));
                              } catch (e) {
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                              }
                            }
                          : null,
                      child: const Text('Upload to Drive'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: FutureBuilder<void>(
            future: _cameraInit,
            builder: (context, snapshot) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: (_cameraController != null && _cameraController!.value.isInitialized)
                        ? CameraPreview(_cameraController!)
                        : const Center(child: CircularProgressIndicator()),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          StreamBuilder<int>(
                            stream: Stream<int>.periodic(const Duration(milliseconds: 500), (count) => count),
                            builder: (context, _) {
                              final Color distanceColor = _distanceColor(provider);
                              return GlassContainer(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'GPS ${provider.currentLatitude.toStringAsFixed(5)}, ${provider.currentLongitude.toStringAsFixed(5)}',
                                            style: const TextStyle(color: Colors.white, fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '📍 ${provider.currentDistanceCm.toStringAsFixed(0)}cm',
                                          style: TextStyle(color: distanceColor, fontSize: 12, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(width: 8),
                                        Text('Bearing: ${provider.currentBearing.toStringAsFixed(0)}°', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                        const SizedBox(width: 8),
                                        Text('Height: ${provider.currentHeightDelta >= 0 ? '+' : ''}${provider.currentHeightDelta.toStringAsFixed(0)}cm', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'IMU',
                                      style: TextStyle(color: Color(0xFF00BCD4), fontSize: 10, fontWeight: FontWeight.w700),
                                    ),
                                    if (provider.shouldShowDriftWarning)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Text(
                                          '⚠ Re-set point recommended',
                                          style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'raw accel: ${provider.rawAcceleration.x.toStringAsFixed(2)}, '
                                      '${provider.rawAcceleration.y.toStringAsFixed(2)}, '
                                      '${provider.rawAcceleration.z.toStringAsFixed(2)}',
                                      style: const TextStyle(color: Colors.white, fontSize: 10),
                                    ),
                                    Text(
                                      'gated: ${provider.gatedAcceleration.length.toStringAsFixed(2)}  '
                                      'velocity: ${provider.velocityMagnitude.toStringAsFixed(2)}  '
                                      'still count: ${provider.stillCount}  '
                                      'calib: ${provider.calibrationCount}',
                                      style: const TextStyle(color: Colors.white, fontSize: 10),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const Spacer(),
                          if (provider.appState == AppState.initial)
                            _buildInitialBar(provider)
                          else
                            _buildCaptureBar(provider),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildInitialBar(CameraProvider provider) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton.filledTonal(
            onPressed: () => _openTargetDistanceDialog(context, provider),
            icon: const Icon(Icons.straighten, color: Colors.white),
          ),
          ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _pinPulse, curve: Curves.easeInOut)),
            child: GestureDetector(
              onTap: () async {
                await _runCalibrationDialog(provider);
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00BCD4),
                ),
                child: const Icon(Icons.place, color: Colors.white, size: 34),
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlbumScreen())),
            icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureBar(CameraProvider provider) {
    final album = provider.currentAlbum;
    final images = album?.images ?? const [];

    return Stack(
      children: [
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => _openCaptureDeckDialog(context, provider),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (int i = 0; i < (images.length > 3 ? 3 : images.length); i++)
                        Positioned(
                          left: i * 8,
                          top: i * 6,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(images[i].imagePath),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      if (images.isEmpty)
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.photo_size_select_actual_outlined, color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                height: 72,
                child: ElevatedButton(
                  onPressed: (!provider.isInPosition || _cameraController == null)
                      ? null
                      : () async {
                          try {
                            await provider.captureImage(_cameraController!);
                          } catch (e) {
                            if (!mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: provider.isInPosition ? const Color(0xFF4CAF50) : Colors.grey,
                    disabledBackgroundColor: Colors.grey,
                    padding: EdgeInsets.zero,
                  ),
                  child: Icon(
                    provider.isInPosition ? Icons.check : Icons.close,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
              GuideArrow3D(
                bearingDelta: provider.bearingDelta,
                distanceDelta: provider.distanceDelta,
                heightDelta: provider.currentHeightDelta,
                targetDistanceCm: provider.targetDistanceCm,
              ),
            ],
          ),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: TextButton.icon(
            onPressed: provider.resetPosition,
            style: TextButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            icon: const Icon(Icons.restart_alt, size: 14),
            label: const Text('Reset Position', style: TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

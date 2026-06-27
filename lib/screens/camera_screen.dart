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

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  Future<void>? _cameraInit;
  late final AnimationController _pulse;
  bool _showWaitingOverlay = false;
  bool _streamActive = false;
  bool _streamOpInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _cameraInit = _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      return;
    }

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await _cameraController!.initialize();
    await _setImageStreamActive(true);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_setImageStreamActive(false));
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_setImageStreamActive(true));
    }
  }

  Future<void> _setImageStreamActive(bool shouldBeActive) async {
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (_streamOpInFlight) {
      return;
    }
    if (_streamActive == shouldBeActive) {
      return;
    }

    _streamOpInFlight = true;
    try {
      if (shouldBeActive) {
        await controller.startImageStream(_onCameraImage);
      } else if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      _streamActive = shouldBeActive;
    } finally {
      _streamOpInFlight = false;
    }
  }

  void _onCameraImage(CameraImage image) {
    final CameraController? controller = _cameraController;
    if (controller == null || !mounted) {
      return;
    }
    context.read<CameraProvider>().processCameraFrame(
      image,
      controller.description.sensorOrientation,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    if (_cameraController?.value.isStreamingImages ?? false) {
      unawaited(_setImageStreamActive(false));
    }
    _cameraController?.dispose();
    super.dispose();
  }

  Color _distanceColor(CameraProvider provider) {
    final delta = (provider.currentDistanceCm - provider.targetDistanceCm).abs();
    if (delta <= 10) {
      return const Color(0xFF4CAF50);
    }
    if (delta <= 30) {
      return Colors.amber;
    }
    return const Color(0xFFE53935);
  }

  Future<void> _capturePhoto(CameraProvider provider) async {
    if (_cameraController == null) {
      return;
    }

    try {
      await _setImageStreamActive(false);

      await provider.captureImage(_cameraController!);

      if (mounted) {
        await _setImageStreamActive(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      if (mounted) {
        await _setImageStreamActive(true);
      }
    }
  }

  void _showWaitingOverlayState(bool show) {
    if (!mounted || _showWaitingOverlay == show) {
      return;
    }
    setState(() {
      _showWaitingOverlay = show;
    });
  }

  Future<void> _handleSetPoint(CameraProvider provider) async {
    if (!provider.hasDepthFrame) {
      _showWaitingOverlayState(true);
      await provider.waitForFirstDepthFrame();
      _showWaitingOverlayState(false);
    }

    final bool success = await provider.setDepthPoint();
    if (!success) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Camera not ready. Try again.'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.red.withValues(alpha: 0.8),
        ),
      );
      return;
    }

    await provider.switchToCaptureState(
      provider.currentLatitude,
      provider.currentLongitude,
      provider.currentBearing,
    );
  }

  Future<void> _openTargetDistanceDialog(CameraProvider provider) async {
    double temp = provider.targetDistanceCm;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Set Target Distance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                    const SizedBox(height: 12),
                    Text('${temp.toStringAsFixed(0)} cm', style: const TextStyle(color: Colors.white)),
                    Slider(
                      min: 50,
                      max: 500,
                      value: temp,
                      divisions: 90,
                      onChanged: (v) => setStateDialog(() => temp = v),
                    ),
                    FilledButton(
                      onPressed: () {
                        provider.setTargetDistance(temp);
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

  Future<void> _openCaptureDeckDialog(CameraProvider provider) async {
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
                    itemBuilder: (_, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(album.images[index].imagePath), fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: album.isComplete
                          ? () async {
                              Navigator.pop(dialogContext);
                              try {
                                final link = await provider.uploadAlbum();
                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded: $link')));
                              } catch (e) {
                                if (!mounted) {
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
        final bool capture = provider.appState == AppState.capture;
        final bool firstPhotoPending = capture && !provider.showAngleHeightGuides;

        return Scaffold(
          backgroundColor: Colors.black,
          body: FutureBuilder<void>(
            future: _cameraInit,
            builder: (context, _) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: (_cameraController != null && _cameraController!.value.isInitialized)
                        ? CameraPreview(_cameraController!)
                        : const Center(child: CircularProgressIndicator()),
                  ),
                  Center(
                    child: _Crosshair(
                      pulse: provider.appState == AppState.initial ? _pulse.value : 1.0,
                      locked: capture,
                      inTolerance: provider.isInPosition,
                      label: provider.appState == AppState.initial
                          ? 'Point at object and Set Point'
                          : 'Step back to ${provider.targetDistanceCm.toStringAsFixed(0)}cm',
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          GlassContainer(
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
                                      provider.hasAnchor
                                          ? '📍 ${provider.currentDistanceCm.toStringAsFixed(0)}cm'
                                          : '📍 --',
                                      style: TextStyle(
                                        color: _distanceColor(provider),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('IMU', style: TextStyle(color: const Color(0xFF00BCD4).withValues(alpha: 0.95), fontSize: 10)),
                                  ],
                                ),
                                if (capture) ...[
                                  const SizedBox(height: 6),
                                  _ScaleBar(
                                    value: provider.scaleBarNormalized,
                                    inTolerance: (provider.currentDistanceCm - provider.targetDistanceCm).abs() <= 10,
                                  ),
                                ],
                                if (provider.trackingWarning != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    provider.trackingWarning!,
                                    style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ],
                                if (provider.isUsingFallbackTracking) ...[
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Using fallback tracking',
                                    style: TextStyle(color: Color(0xFF80DEEA), fontSize: 10),
                                  ),
                                ],
                                if (provider.showAngleHeightGuides) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text('Bearing: ${provider.currentBearing.toStringAsFixed(0)}°', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      const SizedBox(width: 12),
                                      Text('Pitch: ${provider.currentPitch.toStringAsFixed(1)}°', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (!capture)
                            _buildInitialBar(provider)
                          else
                            _buildCaptureBar(provider, firstPhotoPending),
                        ],
                      ),
                    ),
                  ),
                  if (_showWaitingOverlay)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: GlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Initializing camera...',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
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
    final bool hasFrame = provider.hasDepthFrame;
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton.filledTonal(
            onPressed: () => _openTargetDistanceDialog(provider),
            icon: const Icon(Icons.straighten, color: Colors.white),
          ),
          Tooltip(
            message: hasFrame ? 'Set Point' : 'Waiting for camera...',
            child: GestureDetector(
              onTap: hasFrame ? () => _handleSetPoint(provider) : null,
              child: Opacity(
                opacity: hasFrame ? 1.0 : 0.5,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00BCD4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.55 * _pulse.value),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: hasFrame
                      ? const Icon(Icons.place, color: Colors.white, size: 34)
                      : const Padding(
                          padding: EdgeInsets.all(26),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                ),
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

  Widget _buildCaptureBar(CameraProvider provider, bool firstPhotoPending) {
    final album = provider.currentAlbum;
    final images = album?.images ?? const [];

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () => _openCaptureDeckDialog(provider),
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
                        child: Image.file(File(images[i].imagePath), width: 44, height: 44, fit: BoxFit.cover),
                      ),
                    ),
                  if (images.isEmpty)
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
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
              onPressed: (!provider.isInPosition || _cameraController == null) ? null : () => _capturePhoto(provider),
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: provider.isInPosition ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
                disabledBackgroundColor: Colors.grey,
                padding: EdgeInsets.zero,
              ),
              child: Icon(provider.isInPosition ? Icons.check : Icons.close, size: 32, color: Colors.white),
            ),
          ),
          if (!firstPhotoPending)
            GuideArrow3D(
              bearingDelta: provider.bearingDelta,
              distanceDelta: provider.scaleDeltaPercent,
              heightDelta: provider.pitchDelta,
              targetDistanceCm: 100.0,
            )
          else
            const SizedBox(width: 132, height: 132),
        ],
      ),
    );
  }
}

class _ScaleBar extends StatelessWidget {
  const _ScaleBar({required this.value, required this.inTolerance});

  final double value;
  final bool inTolerance;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: CustomPaint(
        painter: _ScaleBarPainter(value: value, inTolerance: inTolerance),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ScaleBarPainter extends CustomPainter {
  _ScaleBarPainter({required this.value, required this.inTolerance});

  final double value;
  final bool inTolerance;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = inTolerance ? const Color(0xFF4CAF50) : Colors.white
      ..strokeWidth = 2;

    final centerX = size.width / 2;
    final y = size.height / 2;

    canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), line);
    canvas.drawLine(Offset(centerX, y - 6), Offset(centerX, y + 6), line);

    final markerX = 10 + (size.width - 20) * value;
    final markerPaint = Paint()..color = const Color(0xFF00BCD4);
    canvas.drawCircle(Offset(markerX, y), 4, markerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScaleBarPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.inTolerance != inTolerance;
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair({
    required this.pulse,
    required this.locked,
    required this.inTolerance,
    required this.label,
  });

  final double pulse;
  final bool locked;
  final bool inTolerance;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = inTolerance ? const Color(0xFF4CAF50) : Colors.white;
    final double opacity = locked ? 1.0 : (0.5 + pulse * 0.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: const Size(120, 120),
              painter: _CrosshairPainter(color: color.withValues(alpha: opacity), glow: inTolerance),
            ),
            if (locked)
              const Positioned(
                top: -8,
                left: 50,
                child: Icon(Icons.lock, color: Colors.white, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({required this.color, required this.glow});

  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final circle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;

    if (glow) {
      circle.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    }

    canvas.drawCircle(center, 30, circle);
    canvas.drawCircle(center, 3, Paint()..color = color);

    final line = Paint()
      ..strokeWidth = 1.5
      ..color = color;

    canvas.drawLine(Offset(center.dx, center.dy - 50), Offset(center.dx, center.dy - 30), line);
    canvas.drawLine(Offset(center.dx, center.dy + 30), Offset(center.dx, center.dy + 50), line);
    canvas.drawLine(Offset(center.dx - 50, center.dy), Offset(center.dx - 30, center.dy), line);
    canvas.drawLine(Offset(center.dx + 30, center.dy), Offset(center.dx + 50, center.dy), line);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.glow != glow;
  }
}

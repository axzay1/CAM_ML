import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plot_point.dart';
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

  // Auto-capture
  CameraProvider? _provider;
  bool _autoCapturing = false;
  Timer? _autoCaptureTimer;

  // Frame throttle: process 1 in every 3 frames to reduce CPU/heat
  int _frameSkipCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _cameraInit = _initializeCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = context.read<CameraProvider>();
      _provider!.addListener(_checkAutoCapture);
    });
  }

  Future<void> _initializeCamera() async {
    // Dispose any existing controller before creating a new one.
    final oldCtrl = _cameraController;
    _cameraController = null;
    _streamActive = false;
    _streamOpInFlight = false;
    if (mounted) setState(() {});
    await oldCtrl?.dispose();

    final cameras = await availableCameras();
    if (cameras.isEmpty || !mounted) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await _cameraController!.initialize();
    await _setImageStreamActive(true);
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Brief interruption (notification, call overlay) — pause stream only.
      unawaited(_setImageStreamActive(false));
    } else if (state == AppLifecycleState.paused) {
      // Screen locked or app backgrounded — fully release the camera.
      final ctrl = _cameraController;
      _cameraController = null;
      _streamActive = false;
      _streamOpInFlight = false;
      unawaited(ctrl?.dispose());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      // Screen unlocked / app foregrounded — reinitialize from scratch.
      _cameraInit = _initializeCamera();
      if (mounted) setState(() {});
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
    if (_frameSkipCount++ % 3 != 0) return;
    final CameraController? controller = _cameraController;
    if (controller == null || !mounted) return;
    context.read<CameraProvider>().processCameraFrame(
      image,
      controller.description.sensorOrientation,
    );
  }

  @override
  void dispose() {
    _provider?.removeListener(_checkAutoCapture);
    _autoCaptureTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    // Don't call setState-based helpers after dispose — release directly.
    final ctrl = _cameraController;
    _cameraController = null;
    ctrl?.dispose();
    super.dispose();
  }

  void _checkAutoCapture() {
    if (!mounted) return;
    final CameraProvider? p = _provider;
    if (p == null || p.appState != AppState.capture || _autoCapturing) {
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
      return;
    }
    if (p.isInPosition && _cameraController != null) {
      // Start hold timer only if not already running.
      _autoCaptureTimer ??= Timer(const Duration(milliseconds: 700), () {
        _autoCaptureTimer = null;
        if (!mounted || _autoCapturing) return;
        final CameraProvider? p2 = _provider;
        if (p2 == null || !p2.isInPosition || p2.appState != AppState.capture) return;
        _autoCapturing = true;
        _capturePhoto(p2).whenComplete(() {
          if (mounted) _autoCapturing = false;
        });
      });
    } else {
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Signed angle difference: positive = turn right, negative = turn left.
  double _signedAngleDiff(double current, double target) {
    return (current - target + 540) % 360 - 180;
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

    final bool success = await provider.setPoint();
    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Camera not ready. Try again.'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.red.withValues(alpha: 0.8),
        ),
      );
    }
  }

  Future<void> _openCapturedImagesDialog(CameraProvider provider) async {
    final album = provider.currentAlbum;
    if (album == null) return;

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
                const Text(
                  'Captured Images',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 240,
                  width: 280,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: album.images.length,
                    itemBuilder: (_, index) {
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
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: album.isComplete
                          ? () async {
                              Navigator.pop(dialogContext);
                              try {
                                final link = await provider.uploadAlbum();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Uploaded: $link')),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
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

  // ── Camera layer ──────────────────────────────────────────────────────────

  Widget _buildCameraLayer() {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final Size? preview = ctrl.value.previewSize;
    if (preview == null) {
      return CameraPreview(ctrl);
    }
    // previewSize is always reported in landscape (width > height).
    // Swap to get portrait dimensions, then FittedBox.cover scales to fill.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview.height,
          height: preview.width,
          child: CameraPreview(ctrl),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraProvider>(
      builder: (context, provider, _) {
        final Size screenSize = MediaQuery.of(context).size;
        final double screenW = screenSize.width;
        final double screenH = screenSize.height;

        return Scaffold(
          backgroundColor: Colors.black,
          body: FutureBuilder<void>(
            future: _cameraInit,
            builder: (context, _) {
              return Stack(
                children: [
                  // ── Layer 1: Camera preview ──────────────────────────────
                  Positioned.fill(
                    child: _buildCameraLayer(),
                  ),

                  // ── Layer 2: Center crosshair ────────────────────────────
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) =>
                        _buildCenterCrosshair(provider),
                  ),

                  // ── Layer 3: Floating point crosshairs ───────────────────
                  if (provider.appState == AppState.capture)
                    Positioned.fill(
                      child: Stack(
                        children: provider.plotPoints
                            .map((p) => _buildFloatingCrosshair(
                                provider, p, screenW, screenH))
                            .toList(),
                      ),
                    ),

                  // ── Layer 4: Top HUD ─────────────────────────────────────
                  _buildTopHud(provider),

                  // ── Layer 5: Bottom bar ──────────────────────────────────
                  _buildBottomBar(provider),

                  // ── Waiting overlay ──────────────────────────────────────
                  if (_showWaitingOverlay)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: GlassContainer(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Initializing camera...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
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

  // ── Layer 2: Center crosshair ─────────────────────────────────────────────

  Widget _buildCenterCrosshair(CameraProvider provider) {
    final AppState state = provider.appState;

    Color color;
    String label;
    bool pulsing;

    if (state == AppState.initial) {
      color = Colors.white;
      label = 'Point at object → Set Point';
      pulsing = true;
    } else if (state == AppState.p1) {
      color = const Color(0xFF4CAF50);
      label = 'Shoot P1 freely';
      pulsing = true;
    } else {
      color = provider.isInPosition
          ? const Color(0xFF4CAF50)
          : Colors.white;
      final PlotPoint? active = provider.activePlotPoint;
      label = active != null ? 'Walk to ${active.label}' : 'Complete!';
      pulsing = false;
    }

    final double opacity = pulsing ? (0.5 + _pulse.value * 0.5) : 1.0;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(120, 120),
            painter: _CrosshairPainter(
              color: color.withValues(alpha: opacity),
              glow: state == AppState.capture && provider.isInPosition,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Layer 3: Floating crosshairs ──────────────────────────────────────────

  Widget _buildFloatingCrosshair(
    CameraProvider provider,
    PlotPoint point,
    double screenW,
    double screenH,
  ) {
    final double bDelta =
        _signedAngleDiff(provider.currentBearing, point.requiredBearing);
    final double pDelta = provider.currentPitch - point.elevationDeg;

    final double screenX =
        screenW / 2 + (bDelta / 60).clamp(-1.0, 1.0) * screenW * 0.45;
    final double screenY =
        screenH / 2 + (pDelta / 40).clamp(-1.0, 1.0) * screenH * 0.3;

    final bool isActive = !point.isCaptured &&
        point.index == provider.activePlotPoint?.index;

    Widget crosshairWidget;
    double circleSize;

    if (point.isCaptured) {
      circleSize = 36;
      crosshairWidget = Opacity(
        opacity: 0.6,
        child: Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: const Color(0xFF4CAF50), width: 2),
          ),
          child: const Icon(Icons.check,
              color: Color(0xFF4CAF50), size: 20),
        ),
      );
    } else if (isActive) {
      circleSize = 44;
      crosshairWidget = Container(
        width: circleSize,
        height: circleSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: provider.isInPosition
              ? [
                  BoxShadow(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.8),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: const Center(
          child: Icon(Icons.my_location, color: Colors.white, size: 20),
        ),
      );
    } else {
      circleSize = 32;
      crosshairWidget = Opacity(
        opacity: 0.25,
        child: Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
      );
    }

    return Positioned(
      left: screenX - circleSize / 2,
      top: screenY - circleSize / 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          crosshairWidget,
          const SizedBox(height: 2),
          Text(
            point.label,
            style: TextStyle(
              color: Colors.white,
              fontSize: isActive ? 11 : 9,
              fontWeight:
                  isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            '${point.azimuthDeg.toInt()}° / ${point.elevationDeg.toInt()}°',
            style: const TextStyle(color: Colors.white70, fontSize: 8),
          ),
        ],
      ),
    );
  }

  // ── Layer 4: Top HUD ──────────────────────────────────────────────────────

  Widget _buildTopHud(CameraProvider provider) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildHudRows(provider),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHudRows(CameraProvider provider) {
    const TextStyle baseStyle =
        TextStyle(color: Colors.white, fontSize: 11);
    const TextStyle dimStyle =
        TextStyle(color: Colors.white54, fontSize: 10);

    if (provider.appState == AppState.initial) {
      return [
        Text(
          '📷 ${provider.pointsPerLayer}pts × '
          '${provider.numberOfLayers} layers = '
          '${provider.totalPoints} photos',
          style: baseStyle,
        ),
        const SizedBox(height: 2),
        const Text('Point at object → Set Point', style: dimStyle),
      ];
    }

    final String gps =
        'GPS ${provider.currentLatitude.toStringAsFixed(5)}, '
        '${provider.currentLongitude.toStringAsFixed(5)}';

    if (provider.appState == AppState.p1) {
      return [
        Text(gps, style: dimStyle, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          '📍 ${provider.currentDistanceCm.toStringAsFixed(0)}cm  '
          '🧭 ${provider.currentBearing.toStringAsFixed(0)}°  '
          '↗ ${provider.currentPitch.toStringAsFixed(1)}°',
          style: baseStyle,
        ),
        const SizedBox(height: 2),
        const Text(
          'P1 sets sphere radius R — shoot freely',
          style: TextStyle(
            color: Colors.amber,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (provider.trackingWarning != null) ...[
          const SizedBox(height: 2),
          Text(
            provider.trackingWarning!,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (provider.isUsingFallbackTracking) ...[
          const SizedBox(height: 2),
          const Text(
            'Using fallback tracking',
            style: TextStyle(color: Color(0xFF80DEEA), fontSize: 10),
          ),
        ],
      ];
    }

    // capture state
    final ps = provider.positionStatus;
    final String distStr = ps == null
        ? '↕ --'
        : ps.distanceOK
            ? '↕ ✅'
            : '↕ ${ps.distanceDelta.toStringAsFixed(0)}cm';
    final String bearStr = ps == null
        ? '🧭 --'
        : ps.bearingOK
            ? '🧭 ✅'
            : '🧭 ${ps.bearingDelta.toStringAsFixed(0)}°';
    final String pitchStr = ps == null
        ? '↗ --'
        : ps.pitchOK
            ? '↗ ✅'
            : '↗ ${ps.pitchDelta.toStringAsFixed(1)}°';

    return [
      Text(gps, style: dimStyle, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(
        '📍 ${provider.currentDistanceCm.toStringAsFixed(0)}cm  '
        '🧭 ${provider.currentBearing.toStringAsFixed(0)}°',
        style: baseStyle,
      ),
      const SizedBox(height: 2),
      Text(
        'P${provider.capturedCount + 1}/${provider.totalPoints}  |  '
        'Face: ${provider.activePlotPoint?.requiredBearing.toStringAsFixed(0) ?? '--'}°  |  '
        'R: ${provider.sphereRadiusCm?.toStringAsFixed(0) ?? '--'}cm',
        style: baseStyle,
      ),
      const SizedBox(height: 2),
      Text(
        '$distStr   $bearStr   $pitchStr',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (provider.trackingWarning != null) ...[
        const SizedBox(height: 2),
        Text(
          provider.trackingWarning!,
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      if (provider.isUsingFallbackTracking) ...[
        const SizedBox(height: 2),
        const Text(
          'Using fallback tracking',
          style: TextStyle(color: Color(0xFF80DEEA), fontSize: 10),
        ),
      ],
    ];
  }

  // ── Layer 5: Bottom bar ───────────────────────────────────────────────────

  Widget _buildBottomBar(CameraProvider provider) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: switch (provider.appState) {
            AppState.initial => _buildInitialBar(provider),
            AppState.p1 => _buildP1Bar(provider),
            AppState.capture => _buildCaptureBar(provider),
          },
        ),
      ),
    );
  }

  Widget _buildInitialBar(CameraProvider provider) {
    final bool hasFrame = provider.hasDepthFrame;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: pickers
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Points per layer',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
              const SizedBox(height: 4),
              _buildPills(
                options: const [4, 8, 12],
                selected: provider.pointsPerLayer,
                onTap: provider.setPointsPerLayer,
              ),
              const SizedBox(height: 8),
              const Text(
                'Layers',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
              const SizedBox(height: 4),
              _buildPills(
                options: const [1, 2, 3, 4],
                selected: provider.numberOfLayers,
                onTap: provider.setNumberOfLayers,
              ),
            ],
          ),

          // Center: SET POINT button
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return GestureDetector(
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
                          color: const Color(0xFF00BCD4)
                              .withValues(alpha: 0.55 * _pulse.value),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: hasFrame
                        ? const Icon(Icons.place,
                            color: Colors.white, size: 34)
                        : const Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                  ),
                ),
              );
            },
          ),

          // Right: album
          IconButton.filledTonal(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlbumScreen()),
            ),
            icon: const Icon(Icons.photo_library_outlined,
                color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildP1Bar(CameraProvider provider) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Shoot P1 from any position',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sets sphere R for all ${provider.totalPoints} photos',
            style:
                const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _cameraController != null
                ? () => _capturePhoto(provider)
                : null,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4CAF50),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4CAF50)
                        .withValues(alpha: 0.6),
                    blurRadius: 18,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: const Icon(Icons.camera_alt,
                  color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureBar(CameraProvider provider) {
    final images = provider.currentAlbum?.images ?? const [];
    final bool inPos = provider.isInPosition;
    final int captured = provider.capturedCount;
    final int total = provider.totalPoints;
    final bool done = provider.albumComplete;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: stacked thumbnails
          GestureDetector(
            onTap: () => _openCapturedImagesDialog(provider),
            child: SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int i = 0;
                      i < (images.length > 3 ? 3 : images.length);
                      i++)
                    Positioned(
                      left: i * 8.0,
                      top: i * 6.0,
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
                      child: const Icon(
                        Icons.photo_size_select_actual_outlined,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Center: counter + shutter (or Done) + status chips
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                done ? 'All done!' : 'P${captured + 1}/$total',
                style: TextStyle(
                  color: done ? const Color(0xFF4CAF50) : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 72,
                height: 72,
                child: done
                    ? ElevatedButton(
                        onPressed: () => provider.resetToInitial(),
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: const Color(0xFF00BCD4),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.done_all,
                            size: 32, color: Colors.white),
                      )
                    : ElevatedButton(
                        onPressed: (inPos && _cameraController != null)
                            ? () => _capturePhoto(provider)
                            : null,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: inPos
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFE53935),
                          disabledBackgroundColor: const Color(0xFFE53935)
                              .withValues(alpha: 0.5),
                          padding: EdgeInsets.zero,
                        ),
                        child: Icon(
                          inPos ? Icons.check : Icons.close,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
              ),
              const SizedBox(height: 5),
              if (!done) _buildStatusChips(provider),
            ],
          ),

          // Right: 3D guide arrow
          GuideArrow3D(
            bearingDelta: provider.positionStatus?.bearingDelta ?? 0,
            distanceDelta: provider.positionStatus?.distanceDelta ?? 0,
            heightDelta: provider.positionStatus?.pitchDelta ?? 0,
            targetDistanceCm: provider.sphereRadiusCm ?? 150,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChips(CameraProvider provider) {
    final ps = provider.positionStatus;
    if (ps == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip('🧭', ps.bearingOK, '${ps.bearingDelta.toStringAsFixed(0)}°'),
        const SizedBox(width: 4),
        _chip('↗', ps.pitchOK, '${ps.pitchDelta.toStringAsFixed(1)}°'),
        const SizedBox(width: 4),
        _chip('↕', ps.distanceOK, '${ps.distanceDelta.toStringAsFixed(0)}cm'),
      ],
    );
  }

  Widget _chip(String icon, bool ok, String delta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: ok
            ? const Color(0xFF4CAF50).withValues(alpha: 0.35)
            : Colors.red.withValues(alpha: 0.35),
      ),
      child: Text(
        ok ? '$icon ✓' : '$icon $delta',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPills({
    required List<int> options,
    required int selected,
    required void Function(int) onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: options.map((n) {
        final bool sel = n == selected;
        return GestureDetector(
          onTap: () => onTap(n),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel
                    ? const Color(0xFF00BCD4)
                    : Colors.white38,
              ),
            ),
            child: Text(
              '$n',
              style: TextStyle(
                color: sel ? const Color(0xFF00BCD4) : Colors.white38,
                fontSize: 13,
                fontWeight:
                    sel ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Standalone painter ─────────────────────────────────────────────────────

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({required this.color, required this.glow});

  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint circle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;

    if (glow) {
      circle.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    }

    canvas.drawCircle(center, 30, circle);
    canvas.drawCircle(center, 3, Paint()..color = color);

    final Paint line = Paint()
      ..strokeWidth = 1.5
      ..color = color;

    canvas.drawLine(Offset(center.dx, center.dy - 50),
        Offset(center.dx, center.dy - 30), line);
    canvas.drawLine(Offset(center.dx, center.dy + 30),
        Offset(center.dx, center.dy + 50), line);
    canvas.drawLine(Offset(center.dx - 50, center.dy),
        Offset(center.dx - 30, center.dy), line);
    canvas.drawLine(Offset(center.dx + 30, center.dy),
        Offset(center.dx + 50, center.dy), line);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glow != glow;
}


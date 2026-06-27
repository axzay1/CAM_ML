import 'dart:async';
import 'dart:io';

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../providers/camera_app_state.dart';
import '../services/compass_service.dart';
import '../services/location_service.dart';
import 'gallery_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const MethodChannel _arSupportChannel = MethodChannel('cam_ml/ar_support');

  ARSessionManager? _arSessionManager;
  CameraController? _cameraController;
  Future<void>? _initializeCameraFuture;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<double>? _headingSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _poseTimer;
  final TextEditingController _distanceController = TextEditingController();
  bool _arSupported = false;
  bool _arSupportChecked = false;
  bool _cameraReady = false;

  @override
  void initState() {
    super.initState();
    _distanceController.text = '150';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    await _checkArSupport();
    await _initializeSensors();
    if (!_arSupported) {
      await _initializeCameraPreview();
    }
  }

  Future<void> _checkArSupport() async {
    if (!mounted) {
      return;
    }

    if (Platform.isAndroid) {
      setState(() {
        _arSupported = true;
        _arSupportChecked = true;
      });
      return;
    }

    try {
      final supported = await _arSupportChannel.invokeMethod<bool>('isArSupported');
      if (!mounted) {
        return;
      }
      setState(() {
        _arSupported = supported ?? false;
        _arSupportChecked = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _arSupported = false;
        _arSupportChecked = true;
      });
    }
  }

  Future<void> _initializeCameraPreview() async {
    final state = context.read<CameraAppState>();
    if (state.cameras.isEmpty) {
      return;
    }

    _cameraController = CameraController(
      state.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeCameraFuture = _cameraController!.initialize();
    await _initializeCameraFuture;
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraReady = true;
    });
  }

  @override
  void dispose() {
    _poseTimer?.cancel();
    _positionSubscription?.cancel();
    _headingSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _arSessionManager?.dispose();
    _cameraController?.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  Future<void> _initializeSensors() async {
    final state = context.read<CameraAppState>();
    final permissionGranted = await LocationService.requestPermission();
    state.updatePermissions(permissionGranted);

    if (!permissionGranted) {
      return;
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen((position) {
      state.updatePosition(
        position.latitude,
        position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
      );
    });

    _headingSubscription = CompassService.headingStream().listen((heading) {
      state.updateHeading(heading);
    });

    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final accelerationMagnitude = event.x.abs() + event.y.abs() + event.z.abs();
      state.updateSensorStability(accelerationMagnitude);
    });
  }

  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    arSessionManager.onInitialize(
      showAnimatedGuide: true,
      showFeaturePoints: true,
      showPlanes: true,
      handleTaps: false,
    );
    arObjectManager.onInitialize();

    _poseTimer?.cancel();
    _poseTimer = Timer.periodic(const Duration(milliseconds: 180), (_) async {
      final pose = await _arSessionManager?.getCameraPose();
      if (!mounted || pose == null) {
        return;
      }
      context.read<CameraAppState>().updateArPose(pose);
    });
  }

  Future<void> _setPoint(CameraAppState state) async {
    if (_arSupported && _arSessionManager != null) {
      state.setArPointAndStartAlbum();
    } else {
      state.createPinAndEnterSetup();
      state.enterRunningState();
    }
    if (!mounted) {
      return;
    }
    if (state.isCaptureState) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Point set. Move to target distance and capture.')),
      );
    }
  }

  Future<void> _showTargetDistanceDialog(CameraAppState state) async {
    _distanceController.text = state.targetDistanceCm.toStringAsFixed(0);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set Target Distance (cm)'),
          content: TextField(
            controller: _distanceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '150',
              suffixText: 'cm',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(_distanceController.text.trim());
                if (parsed != null && parsed > 0) {
                  state.setTargetDistance(parsed);
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _captureFromAr(CameraAppState state) async {
    if (!state.canCaptureNow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Align distance, height and angle before capturing.')),
      );
      return;
    }

    if (_arSupported && _arSessionManager != null) {
      final snapshot = await _arSessionManager?.snapshot();
      if (snapshot is! MemoryImage) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture AR frame. Try again.')),
        );
        return;
      }

      final appDocDir = await getApplicationDocumentsDirectory();
      final tempPath = '${appDocDir.path}/ar_frame_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(tempPath);
      await file.writeAsBytes(snapshot.bytes);
      await state.addCapture(file.path);
    } else {
      if (!_cameraReady || _cameraController == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera preview is not ready yet.')),
        );
        return;
      }
      await _initializeCameraFuture;
      final image = await _cameraController!.takePicture();
      await state.addCapture(image.path);
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Capture ${state.activeAlbum?.captures.length ?? 0} saved.')),
    );
  }

  Future<void> _showCurrentAlbumDialog(CameraAppState state) async {
    final album = state.activeAlbum;
    if (album == null || album.captures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No captures yet in current album.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(album.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: album.captures.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final capture = album.captures[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(capture.path),
                          width: 84,
                          height: 84,
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
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: state.canFinishAlbum
                          ? () async {
                              Navigator.of(dialogContext).pop();
                              await state.finishActiveAlbum();
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Album exported and saved.')),
                              );
                            }
                          : null,
                      child: const Text('Upload'),
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

  double _angleDifference(double a, double b) {
    final difference = (a - b).abs();
    return difference > 180 ? 360 - difference : difference;
  }

  String _guidanceText(CameraAppState state) {
    if (!state.isCaptureState) {
      return 'Set point to start album';
    }

    if (!state.hasCaptureBaseline) {
      final distanceDelta = state.currentDistanceCm - state.targetDistanceCm;
      if (distanceDelta.abs() > state.distanceToleranceCm) {
        final amount = distanceDelta.abs().toStringAsFixed(0);
        return distanceDelta > 0 ? 'Move closer by $amount cm' : 'Move farther by $amount cm';
      }
      return 'Take first capture to lock height/angle baseline';
    }

    final distanceDelta = state.currentDistanceCm - state.targetDistanceCm;
    final heightDelta = state.currentAltitude - state.activeAlbum!.baselineHeight!;
    final angleDelta = _angleDifference(state.currentApproachYawDeg, state.activeAlbum!.baselineAngle!);

    if (distanceDelta.abs() > state.distanceToleranceCm) {
      final amount = distanceDelta.abs().toStringAsFixed(0);
      return distanceDelta > 0 ? 'Move closer by $amount cm' : 'Move farther by $amount cm';
    }

    if (heightDelta.abs() > 0.5) {
      return heightDelta > 0 ? 'Lower device to match height' : 'Raise device to match height';
    }

    if (angleDelta > 10) {
      return 'Rotate to match first capture angle';
    }

    return 'Aligned. Capture now';
  }

  IconData _guidanceArrowIcon(CameraAppState state) {
    if (!state.isCaptureState) {
      return Icons.control_camera_outlined;
    }

    final distanceDelta = state.currentDistanceCm - state.targetDistanceCm;
    if (distanceDelta.abs() > state.distanceToleranceCm) {
      return distanceDelta > 0 ? Icons.arrow_downward : Icons.arrow_upward;
    }

    if (!state.hasCaptureBaseline) {
      return Icons.center_focus_strong;
    }

    final heightDelta = state.currentAltitude - state.activeAlbum!.baselineHeight!;
    if (heightDelta.abs() > 0.5) {
      return heightDelta > 0 ? Icons.keyboard_double_arrow_down : Icons.keyboard_double_arrow_up;
    }

    final angleDelta = _angleDifference(state.currentApproachYawDeg, state.activeAlbum!.baselineAngle!);
    if (angleDelta > 10) {
      return Icons.threed_rotation;
    }

    return Icons.check_circle;
  }

  Widget _glass({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraAppState>(builder: (context, state, child) {
      final album = state.activeAlbum;

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: !_arSupportChecked
                  ? const Center(child: CircularProgressIndicator())
                  : _arSupported
                      ? ARView(
                          onARViewCreated: _onARViewCreated,
                          planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
                        )
                      : _cameraReady && _cameraController != null
                          ? ClipRect(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController!.value.previewSize?.height ?? 1,
                                  height: _cameraController!.value.previewSize?.width ?? 1,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            )
                          : Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: const Text(
                                'Loading camera preview...',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _glass(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _StatusChip(label: 'Dist', value: '${state.currentDistanceCm.toStringAsFixed(0)} / ${state.targetDistanceCm.toStringAsFixed(0)} cm'),
                            const SizedBox(width: 8),
                            _StatusChip(label: 'Height', value: '${state.currentAltitude.toStringAsFixed(2)} m'),
                            const SizedBox(width: 8),
                            _StatusChip(label: 'Approach', value: '${state.currentApproachYawDeg.toStringAsFixed(0)}°'),
                            const SizedBox(width: 8),
                            _StatusChip(label: 'Pin', value: state.hasPinnedTarget ? 'Set' : 'Not set'),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    _glass(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (state.isInitialState)
                            IconButton.filledTonal(
                              onPressed: () => _showTargetDistanceDialog(state),
                              icon: const Icon(Icons.straighten),
                              tooltip: 'Set target distance',
                            )
                          else
                            InkWell(
                              onTap: () => _showCurrentAlbumDialog(state),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: album != null && album.captures.isNotEmpty
                                            ? Image.file(
                                                File(album.captures.first.path),
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                width: 40,
                                                height: 40,
                                                color: Colors.white.withValues(alpha: 0.18),
                                                child: const Icon(Icons.photo, size: 18),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          GestureDetector(
                            onTap: () async {
                              if (state.isInitialState) {
                                await _setPoint(state);
                                return;
                              }
                              await _captureFromAr(state);
                            },
                            child: Container(
                              width: 86,
                              height: 86,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: state.isInitialState
                                      ? [const Color(0xFF06B6D4), const Color(0xFF2563EB)]
                                      : state.canCaptureNow
                                          ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                          : [const Color(0xFFF59E0B), const Color(0xFFEA580C)],
                                ),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Icon(
                                state.isInitialState ? Icons.place : Icons.camera_alt,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                          if (state.isInitialState)
                            IconButton.filledTonal(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const GalleryScreen()),
                              ),
                              icon: const Icon(Icons.photo_library_outlined),
                              tooltip: 'Albums',
                            )
                          else
                            _glass(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_guidanceArrowIcon(state), color: Colors.white, size: 26),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      _guidanceText(state),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (state.isCaptureState)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _glass(
                          child: Text(
                            '${album?.captures.length ?? 0} / 4 minimum captures in current album',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }
}

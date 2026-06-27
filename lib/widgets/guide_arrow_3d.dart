import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class GuideArrow3D extends StatefulWidget {
  const GuideArrow3D({
    super.key,
    required this.bearingDelta,
    required this.distanceDelta,
    required this.heightDelta,
    this.targetDistanceCm = 150.0,
  });

  final double bearingDelta;
  final double distanceDelta;
  final double heightDelta;
  final double targetDistanceCm;

  @override
  State<GuideArrow3D> createState() => _GuideArrow3DState();
}

class _GuideArrow3DState extends State<GuideArrow3D> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _smoothController;

  late Animation<double> _bearingTween;
  late Animation<double> _distanceTween;
  late Animation<double> _heightTween;

  double _animatedBearing = 0.0;
  double _animatedDistance = 0.0;
  double _animatedHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _smoothController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        setState(() {
          _animatedBearing = _bearingTween.value;
          _animatedDistance = _distanceTween.value;
          _animatedHeight = _heightTween.value;
        });
      });

    _setupTweens(
      bearing: widget.bearingDelta,
      distance: widget.distanceDelta,
      height: widget.heightDelta,
      immediate: true,
    );
  }

  @override
  void didUpdateWidget(covariant GuideArrow3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bearingDelta != widget.bearingDelta ||
        oldWidget.distanceDelta != widget.distanceDelta ||
        oldWidget.heightDelta != widget.heightDelta) {
      _setupTweens(
        bearing: widget.bearingDelta,
        distance: widget.distanceDelta,
        height: widget.heightDelta,
      );
    }
  }

  void _setupTweens({
    required double bearing,
    required double distance,
    required double height,
    bool immediate = false,
  }) {
    _bearingTween = Tween<double>(begin: _animatedBearing, end: bearing).animate(CurvedAnimation(
      parent: _smoothController,
      curve: Curves.easeOutCubic,
    ));
    _distanceTween = Tween<double>(begin: _animatedDistance, end: distance).animate(CurvedAnimation(
      parent: _smoothController,
      curve: Curves.easeOutCubic,
    ));
    _heightTween = Tween<double>(begin: _animatedHeight, end: height).animate(CurvedAnimation(
      parent: _smoothController,
      curve: Curves.easeOutCubic,
    ));

    if (immediate) {
      _animatedBearing = bearing;
      _animatedDistance = distance;
      _animatedHeight = height;
      setState(() {});
      return;
    }

    _smoothController
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _smoothController.dispose();
    super.dispose();
  }

  bool get _bearingOk => _animatedBearing.abs() <= 5.0;
  bool get _distanceOk => _animatedDistance.abs() <= 15.0;
  bool get _heightOk => _animatedHeight.abs() <= 10.0;
  bool get _allOk => _bearingOk && _distanceOk && _heightOk;

  @override
  Widget build(BuildContext context) {
    final vm.Matrix4 matrix = vm.Matrix4.identity()
      ..rotateY(_animatedBearing * math.pi / 180.0 * 0.5)
      ..rotateX((_animatedDistance / widget.targetDistanceCm) * 0.5)
      ..rotateZ((_animatedHeight / 30.0) * 0.3);

    final vm.Matrix4 perspective = vm.Matrix4.identity()..setEntry(3, 2, 0.001);
    final vm.Matrix4 combined = perspective * matrix;

    final Color accent = _allOk ? const Color(0xFF4CAF50) : const Color(0xFF00BCD4);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final double glowOpacity = _allOk ? 0.85 : 0.4 + (_pulseController.value * 0.6);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: glowOpacity),
                    blurRadius: 24,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _Arrow3DPainter(
                  matrix: combined,
                  allOk: _allOk,
                  accent: accent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _deltaLabel(
              '↔ Bearing: ${_animatedBearing >= 0 ? '+' : ''}${_animatedBearing.toStringAsFixed(0)}°',
              _bearingOk,
            ),
            _deltaLabel(
              '↕ Distance: ${_animatedDistance >= 0 ? '+' : ''}${_animatedDistance.toStringAsFixed(0)}cm',
              _distanceOk,
            ),
            _deltaLabel(
              '↑↓ Height: ${_animatedHeight >= 0 ? '+' : ''}${_animatedHeight.toStringAsFixed(0)}cm',
              _heightOk,
            ),
          ],
        );
      },
    );
  }

  Widget _deltaLabel(String text, bool ok) {
    return Text(
      text,
      style: TextStyle(
        color: ok ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _Arrow3DPainter extends CustomPainter {
  _Arrow3DPainter({
    required this.matrix,
    required this.allOk,
    required this.accent,
  });

  final vm.Matrix4 matrix;
  final bool allOk;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);
    canvas.transform(matrix.storage);

    if (allOk) {
      final Paint checkPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = accent;

      final Path check = Path()
        ..moveTo(-24, 0)
        ..lineTo(-6, 20)
        ..lineTo(26, -18);
      canvas.drawPath(check, checkPaint);
      return;
    }

    final Paint bodyPaint = Paint()..color = accent.withValues(alpha: 0.85);
    final Paint shadePaint = Paint()..color = accent.withValues(alpha: 0.45);

    final Path shaft = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-10, -36, 20, 58),
          const Radius.circular(4),
        ),
      );

    final Path head = Path()
      ..moveTo(0, -58)
      ..lineTo(-24, -22)
      ..lineTo(24, -22)
      ..close();

    final Path extrude = Path()
      ..moveTo(10, -36)
      ..lineTo(20, -44)
      ..lineTo(20, 16)
      ..lineTo(10, 22)
      ..close();

    canvas.drawPath(extrude, shadePaint);
    canvas.drawPath(shaft, bodyPaint);
    canvas.drawPath(head, bodyPaint);
  }

  @override
  bool shouldRepaint(covariant _Arrow3DPainter oldDelegate) {
    return oldDelegate.matrix != matrix ||
        oldDelegate.allOk != allOk ||
        oldDelegate.accent != accent;
  }
}

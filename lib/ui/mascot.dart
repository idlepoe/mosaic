import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Screen artwork is decorative; the adjacent localized UI carries its meaning.
enum MascotPose { splash, select, settings, loading, complete, error }

class MascotArt extends StatelessWidget {
  final MascotPose pose;
  final double size;
  const MascotArt(this.pose, {super.key, this.size = 96});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: Theme.of(context).brightness == Brightness.dark
                ? RadialGradient(
                    colors: [
                      const Color(0xfff7f5ef).withValues(alpha: .12),
                      Colors.transparent,
                    ],
                  )
                : null,
          ),
          child: Image.asset(
            'assets/mascot/${pose.name}.png',
            fit: BoxFit.contain,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                .ceil()
                .clamp(128, 640)
                .toInt(),
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    ),
  );
}

/// A separate tile follows a 2.4 second loop; this is never a completion signal.
class LoadingMascot extends StatefulWidget {
  final double size;
  final bool active;
  const LoadingMascot({super.key, this.size = 88, this.active = true});
  @override
  State<LoadingMascot> createState() => _LoadingMascotState();
}

class _LoadingMascotState extends State<LoadingMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool reducedMotion = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LoadingMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (widget.active &&
        !reducedMotion &&
        TickerMode.valuesOf(context).enabled) {
      if (!controller.isAnimating) controller.repeat();
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        child: MascotArt(MascotPose.loading, size: widget.size),
        builder: (context, child) {
          final t = reducedMotion || !widget.active ? .55 : controller.value;
          final double travel;
          if (t < .45) {
            travel = Curves.easeInOutCubic.transform(t / .45);
          } else if (t < .65) {
            travel = 1;
          } else {
            travel = 1 - Curves.easeInOutCubic.transform((t - .65) / .35);
          }
          final s = widget.size;
          return SizedBox(
            width: s,
            height: s,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child!,
                Positioned(
                  key: const ValueKey('mascot-loading-tile'),
                  left: s * (.64 - .112 * travel),
                  top: s * (.295 + .193 * travel),
                  width: s * .207,
                  height: s * .185,
                  child: Transform.rotate(
                    angle: -.20 * (1 - travel),
                    child: const CustomPaint(painter: _LooseTilePainter()),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// A code-native tile layer allows motion without a video player or image atlas.
class _LooseTilePainter extends CustomPainter {
  const _LooseTilePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * .03, h * .035)
      ..lineTo(w * .96, h * .01)
      ..lineTo(w * .99, h * .965)
      ..lineTo(w * .02, h * .99)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xfffffdf9));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff291337)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, w * .045)
        ..strokeJoin = StrokeJoin.round,
    );
    final ink = Paint()
      ..color = const Color(0xff291337).withValues(alpha: .6)
      ..strokeWidth = math.max(.7, w * .015);
    canvas.drawLine(Offset(w * .1, h * .18), Offset(w * .21, h * .08), ink);
    canvas.drawLine(Offset(w * .13, h * .23), Offset(w * .28, h * .09), ink);
    canvas.drawLine(Offset(w * .77, h * .87), Offset(w * .88, h * .76), ink);
  }

  @override
  bool shouldRepaint(covariant _LooseTilePainter oldDelegate) => false;
}

class MascotStartup extends StatelessWidget {
  const MascotStartup({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MascotArt(
                MascotPose.splash,
                size: math.min(200, constraints.maxHeight * .45),
              ),
              const SizedBox(height: 16),
              Text(
                'Mosaic',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

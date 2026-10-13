import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// Placeholder block shown while data loads. Pulses gently,
/// and stays still when the device asks for reduced motion.
class SdSkeleton extends StatefulWidget {
  const SdSkeleton({super.key, this.width = double.infinity, this.height = 16});

  final double width;
  final double height;

  @override
  State<SdSkeleton> createState() => _SdSkeletonState();
}

class _SdSkeletonState extends State<SdSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.5,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: SdColors.of(context).subtleFill,
          borderRadius: BorderRadius.circular(SdRadius.sm),
        ),
      ),
    );
  }
}

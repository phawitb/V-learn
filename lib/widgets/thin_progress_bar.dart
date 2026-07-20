import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ThinProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color fillColor;
  final Color trackColor;
  final double height;

  const ThinProgressBar({
    super.key,
    required this.value,
    this.fillColor = AppColors.blueDark,
    this.trackColor = AppColors.surfaceSoft,
    this.height = 5,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: trackColor,
        valueColor: AlwaysStoppedAnimation(fillColor),
      ),
    );
  }
}

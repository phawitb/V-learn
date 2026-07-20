import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EggCounterChip extends StatelessWidget {
  final int balance;

  const EggCounterChip({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 16,
            decoration: const BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.all(Radius.elliptical(14, 16)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$balance',
            style: const TextStyle(
              color: AppColors.goldInk,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

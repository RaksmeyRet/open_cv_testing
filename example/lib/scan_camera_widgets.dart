import 'package:flutter/material.dart';

class FrameCorner extends StatelessWidget {
  const FrameCorner({
    super.key,
    this.top,
    this.right,
    this.bottom,
    this.left,
    required this.horizontal,
  });

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: horizontal ? 64 : 6,
        height: horizontal ? 6 : 64,
        color: Colors.white,
      ),
    );
  }
}

class CameraTool extends StatelessWidget {
  const CameraTool({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: label,
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 30,
          color: Colors.white,
          style: IconButton.styleFrom(
            backgroundColor:
                active ? const Color(0xFF2F6FED) : const Color(0xFF67696A),
            fixedSize: const Size(64, 64),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

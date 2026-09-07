import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'my_text.dart';

class MyElevatedButton extends StatelessWidget {
  final VoidCallback? onPress;
  final Widget? icon;
  final String text;
  final Color textColor;
  final Color color;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double fontSize;
  final bool isWrap;
  final Color borderColor;
  final double borderWidth;
  final bool? isAlignLeft;
  final Size? minSize;
  final Size? size;
  final Color? shadowColor;
  final double spaceBetweenIcon;
  final bool alignIconLeft;
  final Color? disableColor;

  const MyElevatedButton({
    super.key,
    required this.onPress,
    this.icon,
    required this.text,
    this.borderRadius = 10,
    this.padding,
    this.fontSize = 16,
    this.textColor = AppColors.textWhiteColor,
    this.isWrap = false,
    this.borderWidth = 0,
    this.borderColor = Colors.transparent,
    this.color = AppColors.primaryColor,
    this.minSize,
    this.size,
    this.isAlignLeft = false,
    this.spaceBetweenIcon = 8,
    this.shadowColor,
    this.alignIconLeft = true,
    this.disableColor = AppColors.greyColor,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPress,
      style: ElevatedButton.styleFrom(
        backgroundColor: onPress != null ? color : disableColor,
        disabledBackgroundColor: disableColor,
        alignment: Alignment.centerLeft,
        side: BorderSide(width: borderWidth, color: borderColor),
        minimumSize: minSize ?? const Size(36, 36),
        shadowColor: shadowColor,
        fixedSize: size,
        padding:
            padding ?? const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        ),
      ),
      child: Row(
        mainAxisSize: isWrap ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment:
            isAlignLeft! ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          if (icon != null && alignIconLeft)
            Padding(
              padding: EdgeInsets.only(right: spaceBetweenIcon),
              child: icon,
            ),
          MyText.normalText(
            text,
            fontSize: fontSize,
            textAlign: TextAlign.center,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
            color: textColor,
            maxLines: 1,
          ),
          if (icon != null && !alignIconLeft)
            Padding(
              padding: EdgeInsets.only(left: spaceBetweenIcon),
              child: icon,
            ),
        ],
      ),
    );
  }
}

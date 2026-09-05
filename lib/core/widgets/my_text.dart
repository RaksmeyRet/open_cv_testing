import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

abstract final class MyText {
  static Text normalText(
    String? text, {
    double? fontSize,
    TextStyle? style,
    Color? color,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    String? fontFamily,
    TextAlign textAlign = TextAlign.start,
    TextOverflow overflow = TextOverflow.ellipsis,
    int? maxLines = 1,
    TextDecoration? decoration,
    Color? decorationColor,
    double? height,
    double? letterSpacing,
    List<Shadow>? shadows,
    bool? softWrap,
    TextDirection? textDirection,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    TextHeightBehavior? textHeightBehavior,
    TextScaler? textScaler,
    StrutStyle? strutStyle,
    Locale? locale,
    String? semanticsLabel,
  }) {
    final value = text ?? '';
    return Text(
      value,
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: overflow,
      softWrap: softWrap,
      textDirection: textDirection,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      textScaler: textScaler,
      strutStyle: strutStyle,
      locale: locale,
      semanticsLabel: semanticsLabel,
      style: (style ?? const TextStyle()).copyWith(
        color: color ?? style?.color ?? AppColors.blackColor,
        fontSize: fontSize ?? style?.fontSize ?? 16,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        fontFamily: fontFamily,
        decoration: decoration,
        decorationColor: decorationColor ?? color,
        height: height ?? style?.height ?? _lineHeight(value),
        letterSpacing: letterSpacing,
        shadows: shadows,
      ),
    );
  }

  static Text screenTitle(
    String text, {
    Color? color,
    String? fontFamily,
    double? height,
    TextAlign textAlign = TextAlign.start,
    int? maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    return normalText(
      text,
      fontSize: 24,
      color: color ?? AppColors.primaryColor,
      fontWeight: FontWeight.w700,
      fontFamily: fontFamily,
      height: height,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  static Text sectionTitle(
    String text, {
    Color? color,
    String? fontFamily,
    double? height,
    TextAlign textAlign = TextAlign.start,
    int? maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    return normalText(
      text,
      fontSize: 18,
      color: color ?? AppColors.primaryColor,
      fontWeight: FontWeight.w700,
      fontFamily: fontFamily,
      height: height,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  static Text label(
    String text, {
    Color? color,
    String? fontFamily,
    double? height,
    TextAlign textAlign = TextAlign.start,
    int? maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    return normalText(
      text,
      fontSize: 14,
      color: color ?? AppColors.hintColor,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
      height: height,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  static Text description(
    String text, {
    Color? color,
    String? fontFamily,
    double? height,
    FontWeight? fontWeight,
    TextAlign textAlign = TextAlign.start,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
  }) {
    return normalText(
      text,
      fontSize: 14,
      color: color ?? AppColors.darkGreyColor,
      fontFamily: fontFamily,
      height: height,
      fontWeight: fontWeight,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  static Text mainText(
    String text, {
    Color color = AppColors.blackColor,
    int maxline = 1,
    TextAlign textAlign = TextAlign.start,
    FontWeight fontWeight = FontWeight.w600,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    return normalText(
      text,
      fontSize: 20,
      color: color,
      maxLines: maxline,
      textAlign: textAlign,
      fontWeight: fontWeight,
      overflow: overflow,
    );
  }

  static Text sectionBoldTitle(
    String? text, {
    Color color = AppColors.blackColor,
    double fontSize = 18,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
    double? height,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return normalText(
      text,
      fontSize: fontSize,
      color: color,
      maxLines: maxLines,
      textAlign: textAlign,
      height: height,
      fontWeight: fontWeight,
    );
  }

  static Text labelText(
    String text, {
    Color? color,
    int maxline = 1,
    TextAlign textAlign = TextAlign.start,
    double fontSize = 14,
    double? height,
    FontWeight fontWeight = FontWeight.w500,
    TextOverflow textOverflow = TextOverflow.ellipsis,
  }) {
    return normalText(
      text,
      fontSize: fontSize,
      color: color ?? AppColors.blackColor,
      maxLines: maxline,
      textAlign: textAlign,
      height: height,
      fontWeight: fontWeight,
      overflow: textOverflow,
    );
  }

  static Text valueText(
    String text, {
    Color? color,
    int maxline = 1,
    TextAlign textAlign = TextAlign.start,
    double fontSize = 16,
    double? height,
    FontWeight fontWeight = FontWeight.w500,
    TextOverflow textOverflow = TextOverflow.ellipsis,
  }) {
    return normalText(
      text,
      fontSize: fontSize,
      color: color ?? AppColors.blackColor,
      maxLines: maxline,
      textAlign: textAlign,
      height: height,
      fontWeight: fontWeight,
      overflow: textOverflow,
    );
  }

  static Text descText(
    String? text, {
    Color color = AppColors.blackColor,
    double fontSize = 14,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
    TextAlign textAlign = TextAlign.start,
    double? height,
    FontWeight fontWeight = FontWeight.normal,
  }) {
    return normalText(
      text ?? '-',
      fontSize: fontSize,
      color: color,
      maxLines: maxLines,
      textAlign: textAlign,
      height: height,
      fontWeight: fontWeight,
      overflow: overflow,
    );
  }

  static double _lineHeight(String text) {
    return RegExp(r'[\u1780-\u17FF]').hasMatch(text) ? 1.6 : 1.3;
  }
}

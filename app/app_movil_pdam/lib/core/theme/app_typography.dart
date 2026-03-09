import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

class AppTypography {
  AppTypography(String text, {required double fontSize});

  // Ahora usamos AutoSizeText para los títulos del Login
  static Widget textTitle(
    String text, {
    Color? color,
    double? fontSize,
    TextAlign? textAlign,
  }) {
    return AutoSizeText(
      text,
      minFontSize: 18,
      maxFontSize: 26,
      style: TextStyle(
        fontSize: fontSize ?? 28,
        fontWeight: FontWeight.normal,
        color: color ?? Colors.white,
      ),
      maxLines: 1,
      textAlign: textAlign ?? TextAlign.start,

      overflow: TextOverflow.ellipsis,
    );
  }

  static Widget textSubTitle(
    String text, {
    Color? color,
    double? fontSize,
    TextAlign? textAlign,
  }) {
    return AutoSizeText(
      text,
      maxFontSize: 18,
      minFontSize: 14,
      style: TextStyle(fontSize: fontSize ?? 18, color: color ?? Colors.white),
      maxLines: 1,
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  static Widget textBody(
    String text, {
    Color? color,
    double? fontSize,
    TextAlign? textAlign,
  }) {
    return AutoSizeText(
      text,
      minFontSize: 14,
      maxFontSize: 16,
      style: TextStyle(fontSize: fontSize ?? 16, color: color ?? Colors.white),
      maxLines: 1,
      textAlign: textAlign ?? TextAlign.start,
    );
  }
}

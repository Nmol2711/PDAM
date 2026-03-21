import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

class AppTypography {
  AppTypography(String text, {required double fontSize});

  // Ahora usamos AutoSizeText para los títulos del Login
  static Widget textTitle(
    BuildContext context,
    String text, {
    Color? color,
    double? fontSize,
    TextAlign? textAlign,
    bool superTitle = false,
  }) {
    return AutoSizeText(

      text,
      minFontSize: 18,
      maxFontSize: superTitle ? 52 : 26,
      style: TextStyle(
        fontSize: fontSize ?? 28,
        fontWeight: FontWeight.normal,
        color: color ?? Theme.of(context).textTheme.bodyMedium?.color,
      ),
      maxLines: 1,
      textAlign: textAlign ?? TextAlign.start,

      overflow: TextOverflow.ellipsis,
    );
  }

  static Widget textSubTitle(
    BuildContext context,
    String text, {
    Color? color,
    double? fontSize,
    TextAlign? textAlign,
    bool superSubTitle = false,
  }) {
    return AutoSizeText(
      text,
      maxFontSize: superSubTitle ? 36 : 2,
      minFontSize: 14,
      style: TextStyle(fontSize: fontSize ?? 18, color: color ?? Theme.of(context).textTheme.bodyMedium?.color,),
      maxLines: 1,
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  static Widget textBody(
    BuildContext context,
    String text, {
    Color? color,
    double? fontSize,
    TextAlign? textAlign,
  }) {
    return AutoSizeText(
      text,
      minFontSize: 14,
      maxFontSize: 16,
      style: TextStyle(fontSize: fontSize ?? 16, color: color ?? Theme.of(context).textTheme.bodyMedium?.color,),
      maxLines: 1,
      textAlign: textAlign ?? TextAlign.start,
    );
  }
}

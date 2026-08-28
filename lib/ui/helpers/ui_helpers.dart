import 'dart:math' as math;
import 'package:flutter/material.dart';

double dialogWidthForScreen(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return math.min(420, math.max(280, screenWidth - 48));
}

String blockLabelFromIndex(int index) {
  var current = index + 1;
  var label = '';
  while (current > 0) {
    final remainder = (current - 1) % 26;
    label = String.fromCharCode(65 + remainder) + label;
    current = ((current - 1) / 26).floor();
  }
  return '$label Blok';
}

String formatDateTime(DateTime? dateTime) {
  if (dateTime == null) {
    return '-';
  }
  final local = dateTime.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month.$year $hour:$minute';
}


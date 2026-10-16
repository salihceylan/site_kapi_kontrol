import 'package:flutter/widgets.dart';

/// [scope] düğümünün ALTINDAKİ ilk odaklanabilir düğüme odak verir (örn. odak düğümü alamayan bir düğmeyi
/// `Focus(focusNode: scope)` ile saran ve ona odak taşımak isteyen formlar için). Odaklanabilir bir düğüm
/// yoksa hiçbir şey yapmaz ve false döner.
bool focusFirstWithin(FocusNode scope) {
  for (final node in scope.traversalDescendants) {
    if (node.canRequestFocus) {
      node.requestFocus();
      return true;
    }
  }
  return false;
}

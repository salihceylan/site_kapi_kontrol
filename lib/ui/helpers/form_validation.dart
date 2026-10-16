import 'package:flutter/material.dart';

/// Doğrulama başarısız olduğunda formun üstünde gösterilen özet (canlı bölge: ekran okuyucu duyurur).
const String kFixFieldsMessage = 'Lütfen işaretli alanları düzeltin.';

/// [formKey] formunu doğrular. Geçersizse İLK geçersiz alanı görünür konuma kaydırır ve odaklar (uzun,
/// kaydırılmış bir formda Kaydet'e basınca hata ekran dışında kalıp kullanıcıdan gizlenmesin) ve false
/// döner; geçerliyse true. Çağıran ayrıca [kFixFieldsMessage] özetini göstermelidir.
///
/// Kaydırma iki çerçeve sonra yapılır: özet bildirimi (`CrmFormError`) kendini en üste kaydırır, alan
/// ondan SONRA görünür kılınır ve odaklanır.
bool validateForm(GlobalKey<FormState> formKey) {
  final form = formKey.currentState;
  if (form == null) return false;
  if (form.validate()) return true;
  final context = formKey.currentContext;
  if (context != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) revealFirstInvalidField(context);
      });
    });
  }
  return false;
}

/// [formContext] altındaki ilk geçersiz (`hasError`) form alanını görünür kılar ve metin alanıysa odaklar.
/// Alan yoksa hiçbir şey yapmaz.
void revealFirstInvalidField(BuildContext formContext) {
  Element? invalid;
  void visit(Element element) {
    if (invalid != null) return;
    if (element is StatefulElement) {
      final state = element.state;
      if (state is FormFieldState<dynamic> && state.hasError) {
        invalid = element;
        return;
      }
    }
    element.visitChildren(visit);
  }

  formContext.visitChildElements(visit);
  final field = invalid;
  if (field == null) return;
  Scrollable.ensureVisible(
    field,
    alignment: 0.15,
    duration: Duration.zero,
  );
  FocusNode? focusNode;
  void findEditable(Element element) {
    if (focusNode != null) return;
    final widget = element.widget;
    if (widget is EditableText) {
      focusNode = widget.focusNode;
      return;
    }
    element.visitChildren(findEditable);
  }

  field.visitChildren(findEditable);
  focusNode?.requestFocus();
}

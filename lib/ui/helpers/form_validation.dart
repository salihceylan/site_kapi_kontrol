import 'package:flutter/material.dart';

/// Doğrulama başarısız olduğunda formun üstünde gösterilen özet (canlı bölge: ekran okuyucu duyurur).
const String kFixFieldsMessage = 'Lütfen işaretli alanları düzeltin.';

/// [formKey] formunu doğrular. Geçersizse İLK geçersiz alanı görünür konuma kaydırır ve odaklar (uzun,
/// kaydırılmış bir formda Kaydet'e basınca hata ekran dışında kalıp kullanıcıdan gizlenmesin) ve false
/// döner; geçerliyse true. Çağıran ayrıca [kFixFieldsMessage] özetini göstermelidir.
///
/// Kaydırma iki çerçeve sonra yapılır: özet bildirimi (`CrmFormError`) kendini en üste kaydırır, alan
/// ondan SONRA görünür kılınır ve odaklanır.
///
/// [validateExtra]: form alanı OLMAYAN ek kuralların (örn. hedef seçimi, kategori listesi) doğrulayıcısı; geçerliyse
/// true döner. [revealExtra]: alan hatası yoksa ek kuralın hatasını görünür kılar (true: gösterdi). Ek hataların
/// kendi bildirimleri kendilerini kaydırmaz; görünür kılma işini yalnız bu TEK yol yapar, böylece iki
/// `ensureVisible` birbirinin kaydırmasını ezmez. [reveal] verilirse varsayılan zincirin YERİNE çalışır (alan
/// hatalarıyla ek hataların ekrandaki sırası karışıksa çağıran sırayı kendisi belirler).
bool validateForm(
  GlobalKey<FormState> formKey, {
  bool Function()? validateExtra,
  bool Function()? revealExtra,
  void Function(BuildContext formContext)? reveal,
}) {
  final form = formKey.currentState;
  if (form == null) return false;
  final fieldsOk = form.validate();
  final extraOk = validateExtra?.call() ?? true;
  if (fieldsOk && extraOk) return true;
  final context = formKey.currentContext;
  if (context != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (reveal != null) {
          reveal(context);
        } else if (!revealFirstInvalidField(context)) {
          revealExtra?.call();
        }
      });
    });
  }
  return false;
}

/// [formContext] altındaki ilk geçersiz (`hasError`) form alanını görünür kılar ve metin alanıysa odaklar.
/// Alan yoksa hiçbir şey yapmaz ve false döner.
bool revealFirstInvalidField(BuildContext formContext) {
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
  if (field == null) return false;
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
  return true;
}

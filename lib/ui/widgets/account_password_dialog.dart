import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/form_validation.dart';
import 'package:site_kapi_kontrol/ui/helpers/retry_lock.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

/// "SİL" onayı: büyük/küçük harf ve Türkçe i/İ/ı ayrımı gözetilmez (Türkçe olmayan klavyede "SIL" de olur).
bool matchesConfirmWord(String input, String word) {
  String fold(String s) => s.trim().toUpperCase().replaceAll('İ', 'I');
  return fold(input) == fold(word);
}

/// Parola isteyen işlem penceresi (kişisel veri indirme, hesap silme son onayı).
///
/// - Pencere işlemi KENDİSİ çalıştırır ([onSubmit]); başarıda sonuçla kapanır. Hata pencerede görünür ve
///   pencere AÇIK kalır (parola alanı odaklanır; yanlış parolada alan temizlenir).
/// - Çift gönderim kilidi: işlem sürerken düğmeler pasif, geri tuşu / dış dokunuş kapatmaz.
/// - 429 (hız sınırı / kilitli parola): gönderme düğmesi `retry_after` kadar kilitlenir.
/// - [confirmWord] verilirse (örn. "SİL") gönderme düğmesi yalnız kelime yazılınca açılır.
/// - [closeOnError] true dönen hatada pencere sonuçsuz kapanır (çağıran hatayı kendisi gösterir; örn. silme
///   engeli çıktı).
/// - Parola alanı gizlidir, otomatik düzeltme / öneri / otomatik doldurma kapalıdır.
class AccountPasswordDialog<T> extends StatefulWidget {
  const AccountPasswordDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    required this.confirmLabel,
    required this.busyLabel,
    required this.onSubmit,
    this.tone = AppTone.primary,
    this.confirmWord,
    this.closeOnError,
    this.extra,
  });

  final String title;
  final IconData icon;
  final String message;
  final String confirmLabel;
  final String busyLabel;
  final AppTone tone;

  /// Yazdırılacak onay sözcüğü; null ise yalnız parola istenir.
  final String? confirmWord;

  /// Parola girildikten sonra çalışır; fırlatırsa pencerede gösterilir.
  final Future<T> Function(String password) onSubmit;

  final bool Function(Object error)? closeOnError;

  /// Mesajın altında gösterilen ek içerik (örn. uyarı kutusu).
  final Widget? extra;

  /// Sunucu MEVCUT parola için 1024 karaktere kadar kabul eder (eski, daha gevşek ilkeyle belirlenmiş uzun
  /// parolası olan kullanıcılar da silme / dışa aktarma yapabilsin).
  static const int maxPasswordLength = 1024;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String message,
    required String confirmLabel,
    required String busyLabel,
    required Future<T> Function(String password) onSubmit,
    AppTone tone = AppTone.primary,
    String? confirmWord,
    bool Function(Object error)? closeOnError,
    Widget? extra,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountPasswordDialog<T>(
        title: title,
        icon: icon,
        message: message,
        confirmLabel: confirmLabel,
        busyLabel: busyLabel,
        onSubmit: onSubmit,
        tone: tone,
        confirmWord: confirmWord,
        closeOnError: closeOnError,
        extra: extra,
      ),
    );
  }

  @override
  State<AccountPasswordDialog<T>> createState() => _AccountPasswordDialogState<T>();
}

class _AccountPasswordDialogState<T> extends State<AccountPasswordDialog<T>> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _word = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  /// Hata kutusunun odak düğümü: sunucu hatasından sonra odak buraya gelir (klavye yeniden açılıp hata kutusunu
  /// örtmez; ekran okuyucu / klavye kullanıcısı hatada kalır).
  final FocusNode _errorFocus = FocusNode(debugLabel: 'account_dialog_error');
  final RetryLock _retry = RetryLock();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  bool get _needsWord => widget.confirmWord != null;
  bool get _wordOk => !_needsWord || matchesConfirmWord(_word.text, widget.confirmWord!);

  @override
  void dispose() {
    _retry.dispose();
    _password.dispose();
    _word.dispose();
    _passwordFocus.dispose();
    _errorFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _retry.locked) return;
    if (!validateForm(_formKey)) {
      setState(() => _error = kFixFieldsMessage);
      return;
    }
    final password = _password.text;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(password);
      if (!mounted) return;
      _password.clear();
      popIfCurrent<T>(context, result);
    } catch (e) {
      if (!mounted) return;
      if (widget.closeOnError?.call(e) ?? false) {
        _password.clear();
        popIfCurrent<T>(context);
        return;
      }
      _retry.lockIfRateLimited(e, () {
        if (mounted) setState(() {});
      });
      final wrongPassword = e is ApiException &&
          (e.code == 'CURRENT_PASSWORD_INVALID' ||
              e.code == 'CURRENT_PASSWORD_REQUIRED' ||
              e.code == 'CURRENT_PASSWORD_LOCKED');
      setState(() {
        _busy = false;
        _error = e is ApiException && e.message.trim().isNotEmpty
            ? e.message
            : 'İşlem tamamlanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
        if (wrongPassword) _password.clear();
      });
      // Hata sonrası odak hata kutusuna gider. Parola alanına dönmek klavyeyi yeniden açardı; küçük ekran + büyük
      // yazıda klavye hata kutusunu örtüyordu. Kullanıcı alana dokunarak yeniden yazar (hata kutusu alanın
      // hemen altında, düğmelerin üstünde kalır).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _errorFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final canSubmit = !_busy && !_retry.locked && _wordOk;
    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        title: widget.title,
        icon: widget.icon,
        tone: widget.tone,
        actions: [
          TextButton(
            key: const ValueKey<String>('account_dialog_cancel'),
            onPressed: _busy ? null : () => popIfCurrent<T>(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('account_dialog_submit'),
            style: filledToneStyle(context, tone: widget.tone),
            onPressed: canSubmit ? _submit : null,
            child: _busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Flexible(child: Text(widget.busyLabel, textAlign: TextAlign.center)),
                    ],
                  )
                : Text(widget.confirmLabel, textAlign: TextAlign.center),
          ),
        ],
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.message, style: th.bodyMedium),
              if (widget.extra != null) ...[
                const SizedBox(height: AppSpace.md),
                widget.extra!,
              ],
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const ValueKey<String>('account_password_field'),
                controller: _password,
                focusNode: _passwordFocus,
                enabled: !_busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: _needsWord ? TextInputAction.next : TextInputAction.done,
                maxLength: AccountPasswordDialog.maxPasswordLength,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onFieldSubmitted: (_) {
                  if (!_needsWord && canSubmit) _submit();
                },
                decoration: InputDecoration(
                  labelText: 'Şifreniz',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                    onPressed: _busy ? null : () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
                validator: (value) =>
                    (value ?? '').isEmpty ? 'Devam etmek için şifrenizi girin.' : null,
              ),
              if (_needsWord) ...[
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  key: const ValueKey<String>('account_confirm_word_field'),
                  controller: _word,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  maxLength: 12,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) {
                    if (canSubmit) _submit();
                  },
                  decoration: InputDecoration(
                    labelText: 'Onaylamak için ${widget.confirmWord} yazın',
                    prefixIcon: const Icon(Icons.keyboard_alt_outlined),
                    helperText: _wordOk
                        ? null
                        : '${widget.confirmWord} yazdığınızda düğme açılır.',
                    helperMaxLines: 3,
                  ),
                ),
              ],
              // Hata kutusu alanların HEMEN ALTINDA (sabit düğmelerin üstünde): klavye açıkken de görünür bölgede
              // kalır; ekrana gelince kaydırılarak görünür kılınır ve ekran okuyucuya duyurulur.
              if (_error != null) ...[
                const SizedBox(height: AppSpace.md),
                Focus(
                  key: const ValueKey<String>('account_dialog_error_focus'),
                  focusNode: _errorFocus,
                  child: CrmFormError(message: _error!, announce: true),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

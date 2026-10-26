import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:site_kapi_kontrol/models/legal_document.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Her sosyal girişte yeniden üretilen kriptografik rastgele nonce (HAM değer): 32 bayt `Random.secure()` -> base64url (dolgusuz, 43 karakter).
/// Ham değer yalnız sunucuya (`nonce` alanı) gider; sağlayıcıya [oauthNonceHash] verilir.
String generateOAuthNonce([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Sağlayıcıya verilen nonce: ham değerin SHA-256 özeti (onaltılı, küçük harf). Belirteçteki `nonce` talebi bu özettir; sunucu ham değeri özetleyip
/// karşılaştırır. Ham değer belirteçte görünmediği için ele geçirilen belirteç tek başına yeniden oynatılamaz.
String oauthNonceHash(String rawNonce) => sha256.convert(utf8.encode(rawNonce)).toString();

class SocialAuthCredentials {
  const SocialAuthCredentials({
    required this.idToken,
    this.fullName,
    this.firstName,
    this.lastName,
    this.nonce,
  });

  final String idToken;
  final String? fullName;
  final String? firstName;
  final String? lastName;

  /// Belirtecin bağlandığı HAM nonce (varsa sunucuya iletilir); sağlayıcı nonce desteklemiyorsa null.
  final String? nonce;
}

class SocialAuthButtons extends StatefulWidget {
  const SocialAuthButtons({
    super.key,
    required this.authService,
    this.isRegisterMode = false,
    this.enabled = true,
    this.acceptedDocumentsBuilder,
    this.onBeforeSubmit,
    this.onSuccess,
    this.onError,
    this.onProvideCredentials,
  });

  final AuthService authService;
  final bool isRegisterMode;
  final bool enabled;
  final List<AcceptedDocument>? Function()? acceptedDocumentsBuilder;
  final bool Function()? onBeforeSubmit;
  final VoidCallback? onSuccess;
  final void Function(String message)? onError;
  final Future<SocialAuthCredentials?> Function(String provider)? onProvideCredentials;

  @override
  State<SocialAuthButtons> createState() => _SocialAuthButtonsState();
}

class _SocialAuthButtonsState extends State<SocialAuthButtons> {
  String? _busyProvider;

  void _reportError(String message) {
    if (!mounted) return;
    if (widget.onError != null) {
      widget.onError!(message);
    } else {
      AppSnack.show(context, message, kind: AppSnackKind.error, maxLines: 8);
    }
  }

  Future<void> _handleGoogleTap() async {
    if (_busyProvider != null || !widget.enabled) return;
    if (widget.onBeforeSubmit != null && !widget.onBeforeSubmit!()) return;

    setState(() => _busyProvider = 'google');
    try {
      final acceptedDocs = widget.acceptedDocumentsBuilder?.call();

      // Testler için enjekte edilen kimlik bilgisi
      if (widget.onProvideCredentials != null) {
        final creds = await widget.onProvideCredentials!('google');
        if (!mounted || creds == null || creds.idToken.trim().isEmpty) return;
        final error = await widget.authService.loginWithOAuth(
          provider: 'google',
          idToken: creds.idToken.trim(),
          fullName: creds.fullName,
          firstName: creds.firstName,
          lastName: creds.lastName,
          acceptedDocuments: acceptedDocs,
          nonce: creds.nonce,
        );
        if (!mounted) return;
        if (error != null) {
          _reportError(error);
          return;
        }
        widget.onSuccess?.call();
        return;
      }

      // Web platformunda Google Client ID kontrolü
      final status = await widget.authService.oauthStatus();
      final String? serverClientId = (status['google'] as Map?)?['client_id'] as String?;

      if (kIsWeb && (serverClientId == null || serverClientId.trim().isEmpty)) {
        _reportError(
          'Web tarayıcısında Google ile giriş yapabilmek için Google Web Client ID gereklidir. '
          'Lütfen sunucu .env dosyasına GOOGLE_CLIENT_ID ekleyiniz (Google Cloud Console OAuth 2.0 Web İstemcisi) '
          'veya testi Android/iOS uygulamasından gerçekleştiriniz.',
        );
        return;
      }

      // Standart yerel Google hesap seçici (Android / iOS / Web)
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? serverClientId : null,
        scopes: const <String>['email', 'profile'],
      );
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        // Kullanıcı hesap seçiciyi kapattı/vazgeçti
        return;
      }

      // NOT: google_sign_in 6.x (platform paketleri dahil) nonce'u sağlayıcıya iletemez; belirteçte nonce talebi olmaz. Bu yüzden Google yerel
      // girişinde nonce GÖNDERİLMEZ (sunucu OAUTH_REQUIRE_NONCE=apple gibi sağlayıcı bazlı açılır). google_sign_in ^7 ile
      // `GoogleSignIn.instance.initialize(nonce: oauthNonceHash(ham))` + loginWithOAuth(nonce: ham) eklenmeli.
      final GoogleSignInAuthentication auth = await account.authentication;
      final String tokenToSend = (auth.idToken != null && auth.idToken!.isNotEmpty)
          ? auth.idToken!
          : (auth.accessToken ?? '');

      if (tokenToSend.isEmpty) {
        _reportError('Google kimlik belirteci alınamadı.');
        return;
      }

      final error = await widget.authService.loginWithOAuth(
        provider: 'google',
        idToken: tokenToSend,
        fullName: account.displayName,
        acceptedDocuments: acceptedDocs,
      );

      if (!mounted) return;
      if (error != null) {
        _reportError(error);
        return;
      }

      widget.onSuccess?.call();
    } catch (e) {
      if (!mounted) return;
      _reportError('Google ile giriş yapılamadı: $e');
    } finally {
      if (mounted) {
        setState(() => _busyProvider = null);
      }
    }
  }

  Future<void> _handleAppleTap() async {
    if (_busyProvider != null || !widget.enabled) return;
    if (widget.onBeforeSubmit != null && !widget.onBeforeSubmit!()) return;

    setState(() => _busyProvider = 'apple');
    try {
      final acceptedDocs = widget.acceptedDocumentsBuilder?.call();

      // Testler için enjekte edilen kimlik bilgisi
      if (widget.onProvideCredentials != null) {
        final creds = await widget.onProvideCredentials!('apple');
        if (!mounted || creds == null || creds.idToken.trim().isEmpty) return;
        final error = await widget.authService.loginWithOAuth(
          provider: 'apple',
          idToken: creds.idToken.trim(),
          fullName: creds.fullName,
          firstName: creds.firstName,
          lastName: creds.lastName,
          acceptedDocuments: acceptedDocs,
          nonce: creds.nonce,
        );
        if (!mounted) return;
        if (error != null) {
          _reportError(error);
          return;
        }
        widget.onSuccess?.call();
        return;
      }

      if (kIsWeb || (defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.macOS)) {
        _reportError('iCloud ile giriş yalnızca Apple (iOS / macOS) cihazlarında desteklenmektedir.');
        return;
      }

      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        _reportError('Bu Apple cihazında Apple ile giriş desteklenmiyor.');
        return;
      }

      // Her girişte yeni nonce: sağlayıcıya SHA-256 özeti verilir (identityToken içindeki `nonce` talebi bu özet olur), ham değer sunucuya gider.
      final String rawNonce = generateOAuthNonce();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: oauthNonceHash(rawNonce),
      );

      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        _reportError('Apple kimlik belirteci alınamadı.');
        return;
      }

      final fullName = [
        credential.givenName,
        credential.familyName,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

      final error = await widget.authService.loginWithOAuth(
        provider: 'apple',
        idToken: idToken,
        fullName: fullName.isNotEmpty ? fullName : null,
        firstName: credential.givenName,
        lastName: credential.familyName,
        acceptedDocuments: acceptedDocs,
        nonce: rawNonce,
      );

      if (!mounted) return;
      if (error != null) {
        _reportError(error);
        return;
      }

      widget.onSuccess?.call();
    } catch (e) {
      if (!mounted) return;
      _reportError('iCloud ile giriş yapılamadı: $e');
    } finally {
      if (mounted) {
        setState(() => _busyProvider = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final googleLabel = widget.isRegisterMode
        ? 'Google ile Kaydol'
        : 'Google ile Giriş Yap / Kaydol';
    final appleLabel = widget.isRegisterMode
        ? 'iCloud ile Kaydol'
        : 'iCloud ile Giriş Yap / Kaydol';

    // Apple ile giriş (iCloud) yalnızca iOS ve macOS cihazlarında sunulur.
    // Android, Web veya Windows üzerinde gösterilmez (test mock'ları hariç).
    final bool showAppleButton = widget.onProvideCredentials != null ||
        (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: p.border)),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                child: Text(
                  widget.isRegisterMode ? 'veya hızlı kaydol' : 'veya sosyal hesapla',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: th.bodySmall,
                ),
              ),
            ),
            Expanded(child: Divider(color: p.border)),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        _SocialButton(
          buttonKey: const Key('social-auth-google-button'),
          provider: 'google',
          label: googleLabel,
          isLoading: _busyProvider == 'google',
          enabled: widget.enabled && _busyProvider == null,
          onPressed: _handleGoogleTap,
        ),
        if (showAppleButton) ...[
          const SizedBox(height: AppSpace.sm),
          _SocialButton(
            buttonKey: const Key('social-auth-apple-button'),
            provider: 'apple',
            label: appleLabel,
            isLoading: _busyProvider == 'apple',
            enabled: widget.enabled && _busyProvider == null,
            onPressed: _handleAppleTap,
          ),
        ],
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.buttonKey,
    required this.provider,
    required this.label,
    required this.isLoading,
    required this.enabled,
    required this.onPressed,
  });

  final Key buttonKey;
  final String provider;
  final String label;
  final bool isLoading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: buttonKey,
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.surfaceMuted,
          side: BorderSide(color: p.border),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              _ProviderBadge(provider: provider, palette: p),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider, required this.palette});

  final String provider;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (provider == 'apple') {
      return Icon(
        Icons.apple_rounded,
        size: 20,
        color: palette.text,
      );
    }
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        'G',
        style: TextStyle(
          color: palette.text,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          height: 1.0,
        ),
      ),
    );
  }
}

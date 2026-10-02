// FAZ 5 / A2-G2: DynamicQrPassModal (QR modalı) tasarım yenileme testleri.
//
// - Taşma matrisi: 320x640 x2,0 ve 360x640 x1,5; açık + koyu; tüm durumlar (yükleniyor, hata, canlı,
//   kalıcı/geçici ret, uyuşmazlık, kullanılmış, hükümsüz, süresi doldu, başarı) ve pencere ekran içinde.
// - Tasarım: AppDialogHeader, CountdownRing(+sn), StatusChip(pulse), PrimaryActionButton, SkeletonBox,
//   InlineNotice, tek _QrOverlay; sonsuz _pulseController KALKTI (bitiş durumlarında kare yok).
// - Davranış: ret/kalıcı durum metinleri, yenile, kapat, otomatik kapanış; yoklama mantığı değişmedi
//   (qr_modal_polling_test / fix_fx2_qr_modal_test ayrıca çalışır).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/countdown_ring.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';

import '../design/harness.dart';
import 'g2_support.dart';

class _QrAuth extends AuthService {
  _QrAuth({
    Map<String, dynamic>? status,
    this.tokenError,
    this.holdNextToken = false,
  }) : status = status ?? <String, dynamic>{},
       super(api: AuthApi(baseUrl: 'http://localhost'));

  Map<String, dynamic> status;
  String? tokenError;

  /// true iken bir SONRAKİ karekod isteği [release]'e kadar bekler (yükleniyor durumunu gözlemlemek için).
  bool holdNextToken;
  int tokenCalls = 0;
  int statusCalls = 0;
  Completer<void>? _gate;

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<(Map<String, dynamic>?, String?)> requestDoorQrToken(
    int doorId, {
    Map<String, dynamic>? location,
  }) async {
    tokenCalls++;
    if (holdNextToken) {
      holdNextToken = false;
      final gate = Completer<void>();
      _gate = gate;
      await gate.future;
    }
    if (tokenError != null) return (null, tokenError);
    return (
      <String, dynamic>{'token': 'tok-$tokenCalls', 'expires_in_seconds': 30},
      null,
    );
  }

  @override
  Future<(Map<String, dynamic>?, String?)> getDoorQrStatus(
    String qrToken,
  ) async {
    statusCalls++;
    return (status, null);
  }

  @override
  Future<(Map<String, dynamic>?, String?)> revokeMyDoorQr(int doorId) async =>
      (null, null);
}

Future<void> _open(
  WidgetTester t,
  _QrAuth auth, {
  double width = 360,
  double height = 760,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
  DoorRecord? door,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(
    harnessApp(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) =>
                DynamicQrPassModal(door: door ?? g2Door(), authService: auth),
          ),
          child: const Text('Aç'),
        ),
      ),
      dark: dark,
      scale: scale,
      reduce: reduce,
    ),
  );
  await t.tap(find.text('Aç'));
  await t.pump(); // diyalog
  await t.pump(const Duration(milliseconds: 50)); // token isteği tamamlanır
}

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

/// Yoklama sonucu ([ms] sonra) işlensin ve geçiş animasyonları bitsin.
Future<void> _settleState(WidgetTester t, {int ms = 1000}) async {
  await t.pump(Duration(milliseconds: ms));
  await t.pump(const Duration(milliseconds: 300));
}

StatusChip _headerChip(WidgetTester t) =>
    t.widget<StatusChip>(find.byType(StatusChip).first);

CountdownRing _ring(WidgetTester t) =>
    t.widget<CountdownRing>(find.byType(CountdownRing));

double _qrAlpha(WidgetTester t) =>
    t.widget<QrImageView>(find.byType(QrImageView)).eyeStyle.color!.a;

typedef _State = ({
  String name,
  Map<String, dynamic> status,
  int ms,
  String? tokenError,
  bool never,
});

const Map<String, dynamic> _live = <String, dynamic>{};
final List<_State> _states = <_State>[
  (name: 'canlı', status: _live, ms: 100, tokenError: null, never: false),
  (name: 'yükleniyor', status: _live, ms: 100, tokenError: null, never: true),
  (
    name: 'hata',
    status: _live,
    ms: 100,
    tokenError:
        'Sunucuya ulaşılamadı. Bağlantınızı kontrol edin ve tekrar deneyin.',
    never: false,
  ),
  (
    name: 'kalıcı ret (ACCESS_REVOKED)',
    status: {'last_denial_reason': 'ACCESS_REVOKED', 'last_denied_at': 'x'},
    ms: 1000,
    tokenError: null,
    never: false,
  ),
  (
    name: 'kalıcı ret, uzun metin (TOKEN_OR_USER_INACTIVE)',
    status: {
      'last_denial_reason': 'TOKEN_OR_USER_INACTIVE',
      'last_denied_at': 'x',
    },
    ms: 1000,
    tokenError: null,
    never: false,
  ),
  (
    name: 'geçici ret (PULSE_FAILED)',
    status: {'last_denial_reason': 'PULSE_FAILED', 'last_denied_at': 'x'},
    ms: 1000,
    tokenError: null,
    never: false,
  ),
  (
    name: 'kapı uyuşmazlığı',
    status: {
      'last_denial_reason': 'DOOR_MISMATCH',
      'denied_door_name': 'B Blok Çok Uzun İsimli Kapısı',
    },
    ms: 1000,
    tokenError: null,
    never: false,
  ),
  (
    name: 'kullanılmış karekod',
    status: {'last_denial_reason': 'ALREADY_USED'},
    ms: 1000,
    tokenError: null,
    never: false,
  ),
  (
    name: 'hükümsüz karekod',
    status: {'last_denial_reason': 'SUPERSEDED'},
    ms: 1000,
    tokenError: null,
    never: false,
  ),
  (
    name: 'süresi doldu (sunucu)',
    status: {'last_denial_reason': 'EXPIRED_TOKEN', 'last_denied_at': 'z'},
    ms: 1000,
    tokenError: null,
    never: false,
  ),
  (
    name: 'geçiş başarılı',
    status: {'used': true},
    ms: 1000,
    tokenError: null,
    never: false,
  ),
];

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  group(
    'taşma matrisi (320x640 x2,0 ve 360x640 x1,5; açık + koyu); pencere ekran içinde',
    () {
      for (final s in _states) {
        testWidgets(s.name, (t) async {
          for (final cell in kG2Cells) {
            for (final dark in const <bool>[false, true]) {
              final auth = _QrAuth(
                status: s.status,
                tokenError: s.tokenError,
                holdNextToken: s.never,
              );
              await _open(
                t,
                auth,
                width: cell.width,
                height: 640,
                scale: cell.scale,
                dark: dark,
              );
              await _settleState(t, ms: s.ms);
              final reason =
                  '${s.name}: ${g2CellLabel(cell.width, cell.scale, dark)}';
              expect(t.takeException(), isNull, reason: reason);
              final rect = t.getRect(find.byType(Dialog));
              expect(rect.left, greaterThanOrEqualTo(0), reason: reason);
              expect(
                rect.right,
                lessThanOrEqualTo(cell.width + 0.5),
                reason: reason,
              );
              expect(rect.top, greaterThanOrEqualTo(0), reason: reason);
              expect(rect.bottom, lessThanOrEqualTo(640 + 0.5), reason: reason);
              await _close(t);
            }
          }
        });
      }
    },
  );

  group('canlı durum', () {
    testWidgets(
      'başlık şeridi (kapı/site), durum rozeti (nabız), kalan saniye, halka + karekod, "Kodu Yenile"',
      (t) async {
        final auth = _QrAuth();
        await _open(t, auth);
        await _settleState(t, ms: 100);

        final header = t.widget<AppDialogHeader>(find.byType(AppDialogHeader));
        expect(header.title, 'A Blok Ana Giriş Kapısı');
        expect(header.subtitle, 'Güneş Sitesi');
        expect(header.icon, Icons.qr_code_2_rounded);
        expect(header.tone, AppTone.success);

        expect(find.text('Güvenli Kapı QR Kodu'), findsOneWidget);
        expect(_headerChip(t).tone, AppTone.success);
        expect(
          _headerChip(t).pulse,
          isTrue,
          reason: 'geçerli kodda nabız (3 tur sonra durur)',
        );
        expect(
          find.text('30 sn'),
          findsOneWidget,
          reason: 'tek yeni metin: sn',
        );
        expect(find.byType(CountdownRing), findsOneWidget);
        expect(
          _ring(t).colorOverride,
          isNull,
          reason: 'akış: renk painter içinde yeşil -> amber -> kırmızı',
        );
        expect(find.byType(QrImageView), findsOneWidget);
        expect(_qrAlpha(t), 1.0);
        final button = t.widget<PrimaryActionButton>(
          find.byType(PrimaryActionButton),
        );
        expect(button.label, 'Kodu Yenile');
        expect(button.variant, AppButtonVariant.tonal);
        await _close(t);
      },
    );

    testWidgets(
      'kalan saniye geri sayar: 30 sn -> 29 sn -> 28 sn (hareket azaltmada da)',
      (t) async {
        for (final reduce in const <bool>[false, true]) {
          final auth = _QrAuth();
          await _open(t, auth, reduce: reduce);
          await _settleState(t, ms: 100);
          expect(find.text('30 sn'), findsOneWidget, reason: 'reduce=$reduce');
          await t.pump(const Duration(milliseconds: 1000));
          expect(find.text('29 sn'), findsOneWidget, reason: 'reduce=$reduce');
          await t.pump(const Duration(milliseconds: 1000));
          expect(find.text('28 sn'), findsOneWidget, reason: 'reduce=$reduce');
          await _close(t);
        }
      },
    );

    testWidgets(
      'kalan saniye metni kendi RepaintBoundary\'sinde (saniyelik boyama karekodu etkilemez)',
      (t) async {
        await _open(t, _QrAuth());
        await _settleState(t, ms: 100);
        final boundary = find
            .ancestor(
              of: find.text('30 sn'),
              matching: find.byType(RepaintBoundary),
            )
            .first;
        expect(t.getSize(boundary).height, lessThan(40));
        await _close(t);
      },
    );

    testWidgets(
      'karekod soluklaşması Opacity/saveLayer ile değil renk alfası ile (canlıda tam, ölüde %12)',
      (t) async {
        final auth = _QrAuth();
        await _open(t, auth);
        await _settleState(t, ms: 100);
        expect(
          find.ancestor(
            of: find.byType(QrImageView),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(_qrAlpha(t), 1.0);
        await t.pump(const Duration(seconds: 31));
        await t.pump();
        expect(_qrAlpha(t), closeTo(0.12, 0.01));
        expect(
          find.ancestor(
            of: find.byType(QrImageView),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        await _close(t);
      },
    );

    testWidgets(
      'diyalog yüzeyi palet yüzeyi; kapatma düğmesi >= 44 dp ve "Kapat" ipucu ile kapatır',
      (t) async {
        for (final dark in const <bool>[false, true]) {
          final p = dark ? AppPalette.dark : AppPalette.light;
          final auth = _QrAuth();
          await _open(t, auth, dark: dark);
          await _settleState(t, ms: 100);
          expect(
            t.widget<Dialog>(find.byType(Dialog)).backgroundColor,
            p.surface,
          );
          final close = find.byTooltip('Kapat');
          expect(close, findsOneWidget);
          final size = t.getSize(close);
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
          await t.tap(close);
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byType(DynamicQrPassModal), findsNothing);
          await _close(t);
        }
      },
    );
  });

  group('süre dolunca', () {
    testWidgets(
      '"Süresi Dolmuş QR Kod", "Süresi Doldu" rozeti, "Yeni QR Kod Al" (dolu), saniye gizli, kod soluk',
      (t) async {
        final auth = _QrAuth();
        await _open(t, auth);
        await _settleState(t, ms: 100);
        await t.pump(const Duration(seconds: 31));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));

        expect(find.text('Süresi Dolmuş QR Kod'), findsOneWidget);
        expect(_headerChip(t).tone, AppTone.danger);
        expect(_headerChip(t).pulse, isFalse);
        expect(find.text('Süresi Doldu'), findsOneWidget);
        expect(find.text('Kodu yenileyiniz'), findsOneWidget);
        expect(find.textContaining(' sn'), findsNothing);
        final button = t.widget<PrimaryActionButton>(
          find.byType(PrimaryActionButton),
        );
        expect(button.label, 'Yeni QR Kod Al');
        expect(button.variant, AppButtonVariant.filled);
        expect(_ring(t).colorOverride, CountdownRing.lowColor);
        expect(
          _ring(t).progress,
          same(kAlwaysDismissedAnimation),
          reason: 'boş halka (iz)',
        );
        await _close(t);
      },
    );

    testWidgets(
      '"Yeni QR Kod Al" yeni karekod ister; bu sırada karekod boyutunda iskelet (iğne dönen gösterge yok)',
      (t) async {
        final auth = _QrAuth();
        await _open(t, auth);
        await _settleState(t, ms: 100);
        await t.pump(const Duration(seconds: 31));
        await t.pump();
        auth.holdNextToken = true;
        await t.tap(find.text('Yeni QR Kod Al'));
        await t.pump();
        expect(auth.tokenCalls, 2);
        expect(find.byType(ShimmerScope), findsOneWidget);
        expect(find.byType(SkeletonBox), findsOneWidget);
        expect(find.text('Güvenli token üretiliyor...'), findsOneWidget);
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'spinner iskeletle değişti',
        );
        expect(find.byType(QrImageView), findsNothing);

        auth.release();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byType(ShimmerScope), findsNothing);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('30 sn'), findsOneWidget);
        expect(find.text('Süresi Dolmuş QR Kod'), findsNothing);
        await _close(t);
      },
    );
  });

  group('ret ve durum rozetleri (halka rengi, rozet tonu, tek _QrOverlay)', () {
    testWidgets(
      'kalıcı ret: danger; halka boş + kırmızı; saniye gizli; rozet hem başlıkta hem üstte',
      (t) async {
        await _open(
          t,
          _QrAuth(
            status: {
              'last_denial_reason': 'ACCESS_REVOKED',
              'last_denied_at': 'x',
            },
          ),
        );
        await _settleState(t);
        expect(
          find.text('Kapı Yetkisi Yok'),
          findsNWidgets(2),
          reason: 'başlık rozeti + üst rozet (mevcut sözleşme)',
        );
        expect(_headerChip(t).tone, AppTone.danger);
        expect(_headerChip(t).pulse, isFalse);
        expect(_ring(t).colorOverride, CountdownRing.lowColor);
        expect(_ring(t).progress, same(kAlwaysDismissedAnimation));
        expect(find.textContaining(' sn'), findsNothing);
        expect(_qrAlpha(t), closeTo(0.12, 0.01));
        expect(find.byIcon(Icons.block_rounded), findsOneWidget);
        expect(find.text('Kodu Yenile'), findsOneWidget);
        await _close(t);
      },
    );

    testWidgets(
      'geçici ret (PULSE_FAILED): warning; halka akışta kalır (amber), saniye sayar; 5 sn sonra normale döner',
      (t) async {
        final auth = _QrAuth(
          status: {'last_denial_reason': 'PULSE_FAILED', 'last_denied_at': 'x'},
        );
        await _open(t, auth);
        await _settleState(t);
        expect(find.text('Kapı Komutu Gönderilemedi'), findsNWidgets(2));
        expect(_headerChip(t).tone, AppTone.warning);
        expect(_ring(t).colorOverride, CountdownRing.warnColor);
        expect(
          _ring(t).progress,
          isNot(same(kAlwaysDismissedAnimation)),
          reason: 'kod hâlâ geçerli: halka sayar',
        );
        expect(find.textContaining(' sn'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

        await t.pump(const Duration(seconds: 6));
        expect(find.text('Kapı Komutu Gönderilemedi'), findsNothing);
        expect(_headerChip(t).tone, AppTone.success);
        expect(_ring(t).colorOverride, isNull);
        await _close(t);
      },
    );

    testWidgets(
      'kapı uyuşmazlığı: danger, kırmızı halka, ileti geçerli kapı adıyla',
      (t) async {
        await _open(
          t,
          _QrAuth(
            status: {
              'last_denial_reason': 'DOOR_MISMATCH',
              'denied_door_name': 'B Blok Kapısı',
            },
          ),
        );
        await _settleState(t);
        expect(find.text('Kapı Uyuşmazlığı'), findsOneWidget);
        expect(find.text('Kapı Uyuşmazlığı!'), findsOneWidget);
        expect(
          find.text('Bu kod B Blok Kapısı kapısına ait değil'),
          findsOneWidget,
        );
        expect(_headerChip(t).tone, AppTone.danger);
        expect(_ring(t).colorOverride, CountdownRing.lowColor);
        expect(find.byIcon(Icons.wrong_location_rounded), findsOneWidget);
        await _close(t);
      },
    );

    testWidgets(
      'kullanılmış ve hükümsüz karekod: warning, amber halka, cümleler birebir',
      (t) async {
        await _open(t, _QrAuth(status: {'last_denial_reason': 'ALREADY_USED'}));
        await _settleState(t);
        expect(find.text('Kullanılmış Karekod'), findsOneWidget);
        expect(find.text('Bu Karekod Zaten Kullanıldı!'), findsOneWidget);
        expect(
          find.text('Karekodlar tek kullanımlıktır. Lütfen yeni kod alınız.'),
          findsOneWidget,
        );
        expect(_headerChip(t).tone, AppTone.warning);
        expect(_ring(t).colorOverride, CountdownRing.warnColor);
        await _close(t);

        await _open(t, _QrAuth(status: {'last_denial_reason': 'SUPERSEDED'}));
        await _settleState(t);
        expect(find.text('Yenilenmiş Karekod'), findsOneWidget);
        expect(find.text('Karekod Hükümsüz Kılındı!'), findsOneWidget);
        expect(
          find.text(
            'Bu kod yenilendiği için geçersizdir. Lütfen ekrandaki yeni kodu gösteriniz.',
          ),
          findsOneWidget,
        );
        expect(_headerChip(t).tone, AppTone.warning);
        await _close(t);
      },
    );

    testWidgets(
      'uzun ret iletisi kırpılmaz (rozet büyük yazıda orantılı küçülür); tam metin görünür',
      (t) async {
        await _open(
          t,
          _QrAuth(
            status: {
              'last_denial_reason': 'TOKEN_OR_USER_INACTIVE',
              'last_denied_at': 'x',
            },
          ),
          width: 320,
          scale: 2.0,
          height: 900,
        );
        await _settleState(t);
        expect(
          find.text(
            'Hesabınız veya karekodunuz artık geçerli değil. Yeni kod alın; sorun sürerse site yönetimine başvurun.',
          ),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        final text = t.widget<Text>(
          find.textContaining('Hesabınız veya karekodunuz'),
        );
        expect(
          text.maxLines,
          greaterThanOrEqualTo(8),
          reason: 'FittedBox taşmayı engeller; satır sınırı kırpmaz',
        );
        await _close(t);
      },
    );

    testWidgets('rozet beyaz metni ton gradyanının iki ucunda da >= 4,5:1', (
      t,
    ) async {
      for (final tone in const <AppTone>[AppTone.danger, AppTone.warning]) {
        expect(
          g2Contrast(Colors.white, tone.a),
          greaterThanOrEqualTo(4.5),
          reason: '${tone.name}.a',
        );
        expect(
          g2Contrast(Colors.white, tone.b),
          greaterThanOrEqualTo(4.5),
          reason: '${tone.name}.b',
        );
      }
    });
  });

  group('geçiş başarılı', () {
    testWidgets(
      'başarı içeriği, dolu yeşil halka, tik animasyonu 320 ms easeOutBack, yenile düğmesi yok; 3,2 sn sonra kapanır',
      (t) async {
        await _open(t, _QrAuth(status: {'used': true}));
        await _settleState(t);
        expect(find.text('Geçiş Başarılı'), findsOneWidget);
        expect(find.text('Kapı Açıldı!'), findsOneWidget);
        expect(find.text('Geçiş onaylandı'), findsOneWidget);
        expect(_headerChip(t).tone, AppTone.success);
        expect(_headerChip(t).pulse, isFalse);
        expect(_ring(t).colorOverride, CountdownRing.successColor);
        expect(
          _ring(t).progress,
          same(kAlwaysCompleteAnimation),
          reason: 'dolu halka',
        );
        expect(find.byType(QrImageView), findsNothing);
        expect(find.byType(PrimaryActionButton), findsNothing);
        expect(find.textContaining(' sn'), findsNothing);

        final scale =
            t
                    .widget<ScaleTransition>(
                      find.descendant(
                        of: find.byType(CountdownRing),
                        matching: find.byType(ScaleTransition),
                      ),
                    )
                    .scale
                as CurvedAnimation;
        expect(scale.curve, CountdownRing.successTickCurve);
        expect(
          (scale.parent as AnimationController).duration,
          CountdownRing.successTickDuration,
        );

        await t.pump(const Duration(seconds: 4));
        await t.pump(const Duration(milliseconds: 400));
        expect(
          find.byType(DynamicQrPassModal),
          findsNothing,
          reason: 'eski davranış: otomatik kapanır',
        );
        await _close(t);
      },
    );
  });

  group('hata ve yükleniyor', () {
    testWidgets(
      'hata: InlineNotice (mesaj birebir) + "Tekrar Dene"; dokununca yeniden ister',
      (t) async {
        final auth = _QrAuth(
          tokenError: 'Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.',
        );
        await _open(t, auth);
        await _settleState(t, ms: 100);
        expect(find.byType(InlineNotice), findsOneWidget);
        expect(
          find.text('Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.'),
          findsOneWidget,
        );
        expect(
          t.widget<InlineNotice>(find.byType(InlineNotice)).tone,
          AppTone.danger,
        );
        expect(find.text('Tekrar Dene'), findsOneWidget);
        expect(find.byType(CountdownRing), findsNothing);
        expect(find.textContaining(' sn'), findsNothing);
        expect(_headerChip(t).pulse, isFalse);

        auth.tokenError = null;
        await t.tap(find.text('Tekrar Dene'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(auth.tokenCalls, 2);
        expect(find.byType(QrImageView), findsOneWidget);
        await _close(t);
      },
    );

    testWidgets(
      'ilk yükleme: iskelet + "Güvenli token üretiliyor..."; "Yükleniyor" anlamsal etiketi; spinner yok',
      (t) async {
        final handle = t.ensureSemantics();
        final auth = _QrAuth(holdNextToken: true);
        await _open(t, auth);
        expect(find.byType(ShimmerScope), findsOneWidget);
        expect(find.text('Güvenli token üretiliyor...'), findsOneWidget);
        expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(QrImageView), findsNothing);
        expect(find.byType(PrimaryActionButton), findsNothing);
        handle.dispose();
        auth.release();
        await t.pump();
        await _close(t);
      },
    );
  });

  group(
    'sonsuz animasyon yok: bitiş durumlarında kare istenmez (pumpAndSettle güvenli)',
    () {
      for (final c in <({String name, Map<String, dynamic> status})>[
        (
          name: 'kalıcı ret',
          status: {
            'last_denial_reason': 'ACCESS_REVOKED',
            'last_denied_at': 'x',
          },
        ),
        (
          name: 'süresi doldu (sunucu)',
          status: {
            'last_denial_reason': 'EXPIRED_TOKEN',
            'last_denied_at': 'z',
          },
        ),
        (name: 'geçiş başarılı', status: {'used': true}),
      ]) {
        testWidgets(c.name, (t) async {
          await _open(t, _QrAuth(status: c.status));
          await _settleState(t, ms: 1000);
          await t.pump(const Duration(seconds: 1)); // geçişler biter
          expect(
            t.binding.hasScheduledFrame,
            isFalse,
            reason: 'eski sonsuz _pulseController artık yok',
          );
          await _close(t);
        });
      }

      testWidgets(
        'canlıda yalnız geri sayım halkası kare ister; süre dolunca durur',
        (t) async {
          await _open(t, _QrAuth());
          await _settleState(t, ms: 100);
          expect(
            t.binding.hasScheduledFrame,
            isTrue,
            reason: 'geri sayım sürüyor',
          );
          await t.pump(const Duration(seconds: 31));
          await t.pump();
          await t.pump(const Duration(seconds: 3));
          expect(t.binding.hasScheduledFrame, isFalse);
          await _close(t);
        },
      );
    },
  );

  group('kart içi başlık ve tasarım belirteçleri', () {
    testWidgets('konum korumalı rozet StatusChip(info) olarak; metin birebir', (
      t,
    ) async {
      // Konum doğrulaması açık kapıda karekod isteği önce konum ister (testte platform yok): rozet başlıkta görünür.
      final auth = _QrAuth();
      await _open(t, auth, door: g2Door(geofence: true));
      await t.pump(const Duration(milliseconds: 100));
      final chip = t.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'Konum Korumalı (~100m)'),
      );
      expect(chip.tone, AppTone.info);
      expect(chip.icon, Icons.near_me_rounded);
      await _close(t);
    });

    testWidgets('site adı yoksa alt başlık yok; ad bir kez gösterilir', (
      t,
    ) async {
      await _open(t, _QrAuth(), door: g2Door(siteName: null));
      await _settleState(t, ms: 100);
      expect(
        t.widget<AppDialogHeader>(find.byType(AppDialogHeader)).subtitle,
        isNull,
      );
      expect(find.text('A Blok Ana Giriş Kapısı'), findsOneWidget);
      await _close(t);
    });
  });

  group(
    'tablet (820x1180) ve yatay telefon (640x360); pencere ekran içinde',
    () {
      for (final s in _states) {
        testWidgets(s.name, (t) async {
          for (final size in const <({double w, double h})>[
            (w: 820, h: 1180),
            (w: 640, h: 360),
          ]) {
            for (final dark in const <bool>[false, true]) {
              final auth = _QrAuth(
                status: s.status,
                tokenError: s.tokenError,
                holdNextToken: s.never,
              );
              await _open(
                t,
                auth,
                width: size.w,
                height: size.h,
                scale: 1.0,
                dark: dark,
              );
              await _settleState(t, ms: s.ms);
              final reason = '${s.name}: ${size.w}x${size.h} koyu=$dark';
              expect(t.takeException(), isNull, reason: reason);
              final rect = t.getRect(find.byType(Dialog));
              expect(rect.left, greaterThanOrEqualTo(0), reason: reason);
              expect(
                rect.right,
                lessThanOrEqualTo(size.w + 0.5),
                reason: reason,
              );
              expect(rect.top, greaterThanOrEqualTo(0), reason: reason);
              expect(
                rect.bottom,
                lessThanOrEqualTo(size.h + 0.5),
                reason: reason,
              );
              await _close(t);
            }
          }
        });
      }
    },
  );
}

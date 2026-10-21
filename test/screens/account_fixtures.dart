// F1 (Gizlilik ve Veri, Platform Ayarları, İstemci Hataları) ekran testlerinin ortak sahte servisleri.
//
// `_test.dart` ile bitmediği için kendi başına test olarak çalışmaz. Sunucu uçları sahte yanıt (fixture) ile
// sürülür: her çağrı kaydedilir; hata ve "yanıt bekleme" (Completer) testten verilir.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/account_client_error.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart';
import 'package:site_kapi_kontrol/models/account_deletion.dart';
import 'package:site_kapi_kontrol/models/account_platform_config.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart';
import 'package:site_kapi_kontrol/services/account_local_wipe.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

import 'dialog_layout_harness.dart' show kLayoutCells;

/// Sözleşme §1.6 örnek önizlemesi (silinebilir).
AccountDeletionPreview acPreview({
  bool canDelete = true,
  List<AccountDeletionBlocker> blockers = const <AccountDeletionBlocker>[],
  List<String>? willRemove,
  List<String>? willKeep,
}) => AccountDeletionPreview(
  canDelete: canDelete,
  blockers: blockers,
  willRemove:
      willRemove ??
      const <String>[
        'Adınız, e-posta adresiniz ve telefon numaranız',
        'Tüm site üyelikleriniz ve kapı yetkileriniz',
        'Oluşturduğunuz aktif misafir geçişleri',
        'Bildirim tercihleriniz ve okundu kayıtlarınız',
      ],
  willKeep:
      willKeep ??
      const <String>[
        'Site yönetiminin tuttuğu aidat ve ekstre kayıtları (yasal saklama gerekçesiyle, kimliksiz)',
      ],
);

const AccountDeletionBlocker acLastManager = AccountDeletionBlocker(
  code: 'LAST_SITE_MANAGER',
  message:
      '"Çok Uzun Adlı Konut Yapı Kooperatifi Sitesi" sitesinin tek yöneticisisiniz.',
  siteId: 12,
);

const AccountDeletionBlocker acSuperUser = AccountDeletionBlocker(
  code: 'SUPER_USER',
  message: 'Süper kullanıcı hesabı bu ekrandan silinemez.',
);

AccountDataExport acExport({String name = 'kisisel-veri-42-20261016.json', int size = 12 * 1024}) =>
    AccountDataExport(
      bytes: Uint8List.fromList(utf8.encode('{"format_version":1,"pad":"${'x' * size}"}')),
      fileName: name,
    );

ApiException acWrongPassword() => ApiException(
  'Şifreniz hatalı. Lütfen kontrol edip tekrar deneyin.',
  statusCode: 400,
  code: 'CURRENT_PASSWORD_INVALID',
);

ApiException acExportLimited({int retryAfter = 18000}) => ApiException(
  'Kişisel verilerinizi 24 saat içinde en fazla 3 kez indirebilirsiniz. 5 saat sonra tekrar deneyin.',
  statusCode: 429,
  code: 'EXPORT_RATE_LIMITED',
  retryAfterSeconds: retryAfter,
);

/// Sahte [AccountApi]: bütün uçlar testten sürülür.
class FakeAccountApi extends AccountApi {
  FakeAccountApi() : super(baseUrl: 'http://localhost');

  // Hesap silme.
  AccountDeletionPreview preview = acPreview();
  Object? previewError;
  Completer<void>? previewGate;
  int previewCalls = 0;
  Object? deleteError;
  Completer<void>? deleteGate;
  final List<String> deletePasswords = <String>[];

  // Dışa aktarma.
  AccountDataExport export = acExport();
  Object? exportError;
  Completer<void>? exportGate;
  final List<String> exportPasswords = <String>[];

  // Platform ayarları.
  PlatformConfig config = const PlatformConfig();
  Object? configError;
  Completer<void>? configGate;
  int configCalls = 0;
  Object? putError;
  Completer<void>? putGate;
  final List<Map<String, Map<String, Object>>> putPatches = <Map<String, Map<String, Object>>>[];

  /// PUT yanıtı: null ise yama [config] üzerine uygulanıp döner (sunucu gibi).
  PlatformConfig? putResponse;

  // İstemci hataları.
  List<ClientErrorPage> pages = const <ClientErrorPage>[];
  Object? errorsError;
  Completer<void>? errorsGate;
  final List<({int limit, String? cursor})> errorCalls = <({int limit, String? cursor})>[];

  @override
  Future<AccountDeletionPreview> previewDeletion({required String token}) async {
    previewCalls++;
    await previewGate?.future;
    final error = previewError;
    if (error != null) throw error;
    return preview;
  }

  @override
  Future<void> deleteAccount({required String token, required String currentPassword}) async {
    deletePasswords.add(currentPassword);
    await deleteGate?.future;
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<AccountDataExport> exportData({required String token, required String currentPassword}) async {
    exportPasswords.add(currentPassword);
    await exportGate?.future;
    final error = exportError;
    if (error != null) throw error;
    return export;
  }

  @override
  Future<PlatformConfig> getPlatformConfig({required String token}) async {
    configCalls++;
    await configGate?.future;
    final error = configError;
    if (error != null) throw error;
    return config;
  }

  @override
  Future<PlatformConfig?> updatePlatformConfig({
    required String token,
    required Map<String, Map<String, Object>> patch,
  }) async {
    putPatches.add(patch);
    await putGate?.future;
    final error = putError;
    if (error != null) throw error;
    final response = putResponse ?? _apply(config, patch);
    config = response;
    return response;
  }

  @override
  Future<ClientErrorPage> listClientErrors({
    required String token,
    int limit = 50,
    String? cursor,
  }) async {
    errorCalls.add((limit: limit, cursor: cursor));
    await errorsGate?.future;
    final error = errorsError;
    if (error != null) throw error;
    final index = cursor == null ? 0 : (int.tryParse(cursor) ?? 0);
    if (pages.isEmpty) return const ClientErrorPage();
    return pages[index.clamp(0, pages.length - 1)];
  }

  static PlatformConfig _apply(PlatformConfig base, Map<String, Map<String, Object>> patch) {
    final json = <String, Map<String, dynamic>>{
      for (final entry in base.toJson().entries) entry.key: Map<String, dynamic>.from(entry.value),
    };
    for (final section in patch.entries) {
      json[section.key]!.addAll(section.value);
    }
    return PlatformConfig.fromJson(json);
  }
}

/// Sahte [AuthService]: oturum rolü ve çıkış kaydı. `logout()` çağrılınca oturum kapanır ve dinleyiciler uyarılır.
class FakeAccountAuth extends AuthService {
  FakeAccountAuth({this.role = UserRole.individual, List<String>? order})
    : _order = order,
      super(api: AuthApi(baseUrl: 'http://localhost'));

  UserRole role;
  bool loggedIn = true;
  int logoutCalls = 0;
  int forcedRefreshes = 0;
  final List<String>? _order;

  @override
  UserSession? get session => loggedIn
      ? UserSession(
          id: 7,
          fullName: 'Ayşe Yılmaz',
          email: 'ayse@example.com',
          loginName: null,
          role: role,
          isActive: true,
          token: 'tok-7',
        )
      : null;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) forcedRefreshes++;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    _order?.add('logout');
    loggedIn = false;
    notifyListeners();
  }
}

class FakeWiper implements LocalDataWiper {
  FakeWiper({List<String>? order}) : _order = order;

  final List<String>? _order;
  int wipes = 0;
  int hintClears = 0;

  /// [wipe] sonucu (varsayılan: tüm adımlar tamam).
  LocalWipeReport report = const LocalWipeReport();

  @override
  Future<void> clearSavedLoginIdentifier() async {
    hintClears++;
    _order?.add('hint');
  }

  @override
  Future<LocalWipeReport> wipe() async {
    wipes++;
    _order?.add('wipe');
    return report;
  }
}

/// Sahte paylaşım: çağrılar kaydedilir; sonuç/hata/bekleme testten verilir.
class FakeSharer implements AccountExportSharer {
  final List<AccountDataExport> shared = <AccountDataExport>[];
  final List<Rect?> origins = <Rect?>[];
  ExportShareOutcome outcome = ExportShareOutcome.shared;
  Object? error;
  Completer<void>? gate;

  @override
  Future<ExportShareOutcome> share(
    AccountDataExport export, {
    Rect? sharePositionOrigin,
    String subject = 'Kişisel veri dosyam',
  }) async {
    shared.add(export);
    origins.add(sharePositionOrigin);
    await gate?.future;
    final thrown = error;
    if (thrown != null) throw thrown;
    return outcome;
  }
}

/// Üç sahte katmanı bir araya getirir.
class AccountHarness {
  AccountHarness({UserRole role = UserRole.individual})
    : order = <String>[],
      api = FakeAccountApi() {
    auth = FakeAccountAuth(role: role, order: order);
    wiper = FakeWiper(order: order);
    service = AccountService(authService: auth, api: api, wiper: wiper);
    sharer = FakeSharer();
  }

  final List<String> order;
  final FakeAccountApi api;
  late final FakeAccountAuth auth;
  late final FakeWiper wiper;
  late final AccountService service;
  late final FakeSharer sharer;
}

/// Tüm alanları dolu örnek platform ayarları.
PlatformConfig acConfig({
  String minVersion = '1.0.0',
  String latest = '1.2.0',
  bool maintenance = false,
  bool enforce = false,
}) => PlatformConfig(
  app: PlatformAppConfig(
    minSupportedVersion: minVersion,
    latestVersion: latest,
    updateUrlAndroid: 'https://play.google.com/store/apps/details?id=tr.com.gudeteknoloji.ahbu',
    updateUrlIos: 'https://apps.apple.com/tr/app/ahbu/id1234567890',
    maintenanceActive: maintenance,
    maintenanceMessage: 'Planlı bakım çalışması nedeniyle kısa süre hizmet veremiyoruz.',
  ),
  support: const PlatformSupportConfig(
    email: 'destek@gudeteknoloji.com.tr',
    phone: '+90 212 000 00 00',
    hours: 'Hafta içi 09:00 - 18:00',
    webUrl: 'https://gudeteknoloji.com.tr/destek',
  ),
  legal: PlatformLegalConfig(
    companyName: 'Güde Teknoloji Anonim Şirketi',
    companyAddress: 'Çok Uzun Bir Mahalle Adı Mahallesi, Çok Uzun Bir Sokak Adı Sokak No: 12/4 Kadıköy İstanbul',
    mersisNo: '0123456789012345',
    kepAddress: 'gude@hs01.kep.tr',
    contactEmail: 'kvkk@gudeteknoloji.com.tr',
    contactPhone: '+90 212 000 00 01',
    enforceConsents: enforce,
  ),
);

/// Örnek istemci hata kaydı.
ClientErrorItem acError(
  int n, {
  bool fatal = false,
  String platform = 'android',
  String? stack,
  String? message,
  String? type,
}) => ClientErrorItem(
  fingerprint: 'fp$n',
  errorType: type ?? 'FlutterError',
  message: message ?? 'A RenderFlex overflowed by ${n * 7} pixels on the right.',
  appVersion: '1.0.$n',
  platform: platform,
  fatal: fatal,
  count: n * 3,
  firstSeen: DateTime.utc(2026, 10, 1, 9, 5),
  lastSeen: DateTime.utc(2026, 10, 16, 7, 30),
  sampleStack: stack ?? '#0 RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1:1)\n#1 main (package:site/main.dart:$n:1)',
);

// ---------------------------------------------------------------------------
// Taşma matrisi ve erişilebilirlik yardımcıları
// ---------------------------------------------------------------------------

/// Ortak zorunlu hücrelere (320x640 x2,0, 360x640 x1,5, yatay 640x360, tablet 820x1180) ek olarak YATAY + BÜYÜK
/// YAZI hücresi (640x360 x2,0). Ortak `kLayoutCells`i genişletmek başka ajanların tüm diyalog testlerini
/// değiştireceğinden hücre yalnız F1 ekranlarında kullanılır.
const List<(double, double, double)> kAccountCells = <(double, double, double)>[
  ...kLayoutCells,
  (640, 360, 2.0),
];

/// Her hücre x {açık, koyu} için bir `testWidgets` kaydeder; gövde sonunda çerçeve hatası (taşma dahil) kalmamalıdır.
void accountLayoutMatrix(
  String name,
  Future<void> Function(WidgetTester t, double width, double height, double scale, bool dark) body,
) {
  for (final (width, height, scale) in kAccountCells) {
    for (final dark in const <bool>[false, true]) {
      final label =
          '$name: ${width.toInt()}x${height.toInt()} x$scale ${dark ? 'koyu' : 'açık'} tema, taşma yok';
      testWidgets(label, (t) async {
        await body(t, width, height, scale, dark);
        expect(t.takeException(), isNull);
      });
    }
  }
}

/// Ekran okuyucuya gönderilen duyuruları (`SemanticsService.sendAnnouncement`) toplar. Test sonunda kendiliğinden
/// kapatılır.
List<String> captureAnnouncements(WidgetTester t) {
  final messages = <String>[];
  t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
    if (message is Map && message['type'] == 'announce') {
      final data = message['data'];
      if (data is Map && data['message'] is String) messages.add(data['message'] as String);
    }
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
  return messages;
}

// Hesap / gizlilik / platform yönetimi modelleri (lib/models/account_*.dart): sözleşme gövdelerinin
// (docs/PLATFORM_SATISA_HAZIRLIK.md §1.2, §1.3, §1.5, §1.6) çözümlenmesi, güvenli varsayılanlar ve doğrulayıcılar.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/account_client_error.dart';
import 'package:site_kapi_kontrol/models/account_data_export.dart';
import 'package:site_kapi_kontrol/models/account_deletion.dart';
import 'package:site_kapi_kontrol/models/account_platform_config.dart';

void main() {
  group('AccountDeletionPreview', () {
    test('sözleşme gövdesi: silinebilir, listeler ve engelsiz', () {
      final preview = AccountDeletionPreview.fromJson(<String, dynamic>{
        'can_delete': true,
        'blockers': <Object>[],
        'will_remove': <String>['Ad, e-posta ve telefon', 'Bildirim tercihleri'],
        'will_keep': <String>['Aidat kayıtları (yasal saklama)'],
      });
      expect(preview.canDelete, isTrue);
      expect(preview.blockers, isEmpty);
      expect(preview.willRemove, <String>['Ad, e-posta ve telefon', 'Bildirim tercihleri']);
      expect(preview.willKeep, <String>['Aidat kayıtları (yasal saklama)']);
    });

    test('engel varsa can_delete true dese bile ilerlenemez (güvenli taraf)', () {
      final preview = AccountDeletionPreview.fromJson(<String, dynamic>{
        'can_delete': true,
        'blockers': <Map<String, dynamic>>[
          <String, dynamic>{'code': 'SUPER_USER', 'message': 'Süper kullanıcı silinemez.'},
        ],
      });
      expect(preview.canDelete, isFalse);
      expect(preview.blockers.single.code, 'SUPER_USER');
    });

    test('can_delete yok / bozuk: silinemez (açık true gerekir)', () {
      expect(AccountDeletionPreview.fromJson(<String, dynamic>{}).canDelete, isFalse);
      expect(AccountDeletionPreview.fromJson(<String, dynamic>{'can_delete': 'true'}).canDelete, isFalse);
      expect(AccountDeletionPreview.fromJson(<String, dynamic>{'can_delete': 1}).canDelete, isFalse);
    });

    test('blokaj: site_id sayı ya da metin; sunucu metni yoksa Türkçe yedek metin ve yönerge', () {
      final preview = AccountDeletionPreview.fromJson(<String, dynamic>{
        'can_delete': false,
        'blockers': <Object>[
          <String, dynamic>{'code': 'LAST_SITE_MANAGER', 'site_id': 12},
          <String, dynamic>{'code': 'LAST_SITE_MANAGER', 'message': '  ', 'site_id': '7'},
          <String, dynamic>{'code': 'SUPER_USER'},
          <String, dynamic>{'code': 'BILINMEYEN'},
          'bozuk',
          42,
        ],
      });
      expect(preview.blockers, hasLength(4), reason: 'harita olmayan öğeler atlanır');
      expect(preview.blockers[0].siteId, 12);
      expect(preview.blockers[0].message, 'Sitenizde aktif üyeler varken tek yöneticisiniz.');
      expect(preview.blockers[0].hint, contains('başka bir yönetici atayın'));
      expect(preview.blockers[1].siteId, 7);
      expect(preview.blockers[2].message, 'Süper kullanıcı hesapları buradan silinemez.');
      expect(preview.blockers[3].message, 'Hesabınız şu anda silinemez.');
      expect(preview.blockers[3].hint, isNull);
    });

    test('sunucu metni varsa yedek metne tercih edilir', () {
      final blocker = AccountDeletionBlocker.fromJson(<String, dynamic>{
        'code': 'LAST_SITE_MANAGER',
        'message': '"Gül Sitesi" sitesinde tek yöneticisiniz.',
      });
      expect(blocker.message, '"Gül Sitesi" sitesinde tek yöneticisiniz.');
    });

    test('listeler: yalnız dolu metinler, kırpılır; liste olmayan değer boş', () {
      final preview = AccountDeletionPreview.fromJson(<String, dynamic>{
        'can_delete': true,
        'will_remove': <Object?>['  a  ', '', 3, null, 'b'],
        'will_keep': 'bozuk',
      });
      expect(preview.willRemove, <String>['a', 'b']);
      expect(preview.willKeep, isEmpty);
    });
  });

  group('AccountDataExport', () {
    test('boyut etiketi', () {
      expect(formatByteSize(0), '0 B');
      expect(formatByteSize(532), '532 B');
      expect(formatByteSize(1536), '1,5 KB');
      expect(formatByteSize(12 * 1024), '12 KB');
      expect(formatByteSize((1.4 * 1024 * 1024).round()), '1,4 MB');
      expect(formatByteSize(25 * 1024 * 1024), '25 MB');
      final export = AccountDataExport(bytes: Uint8List(2048), fileName: 'x.json');
      expect(export.sizeBytes, 2048);
      expect(export.sizeLabel, '2,0 KB');
    });

    test('Content-Disposition: tırnaklı, tırnaksız ve filename*', () {
      const fb = 'kisisel-veri-20261016.json';
      expect(
        exportFileNameFrom('attachment; filename="kisisel-veri-42-20261016.json"', fallback: fb),
        'kisisel-veri-42-20261016.json',
      );
      expect(
        exportFileNameFrom('attachment; filename=kisisel-veri-42-20261016.json', fallback: fb),
        'kisisel-veri-42-20261016.json',
      );
      expect(
        exportFileNameFrom("attachment; filename*=UTF-8''k%C4%B1s-veri.json", fallback: fb),
        'k-s-veri.json',
        reason: 'ASCII dışı karakterler güvenli karaktere çevrilir',
      );
    });

    test('dosya adı güvenli hale getirilir: yol bileşenleri, kontrol karakterleri, uzantı', () {
      const fb = 'kisisel-veri-20261016.json';
      expect(exportFileNameFrom('attachment; filename="../../etc/passwd"', fallback: fb), 'passwd.json');
      expect(exportFileNameFrom(r'attachment; filename="C:\Windows\x.json"', fallback: fb), 'x.json');
      expect(exportFileNameFrom('attachment; filename="a b;c.json"', fallback: fb), 'a-b-c.json');
      expect(exportFileNameFrom('attachment; filename=".hidden"', fallback: fb), 'hidden.json');
      expect(exportFileNameFrom('attachment; filename="veri"', fallback: fb), 'veri.json');
      expect(exportFileNameFrom('attachment; filename=""', fallback: fb), fb);
      expect(exportFileNameFrom(null, fallback: fb), fb);
      expect(exportFileNameFrom('inline', fallback: fb), fb);
      final long = exportFileNameFrom('attachment; filename="${'a' * 200}.json"', fallback: fb);
      expect(long.length, lessThanOrEqualTo(85));
      expect(long.endsWith('.json'), isTrue);
    });

    test('yedek dosya adı yerel tarihten türetilir', () {
      expect(fallbackExportFileName(DateTime(2026, 10, 6)), 'kisisel-veri-20261006.json');
    });
  });

  group('PlatformConfig', () {
    Map<String, dynamic> body() => <String, dynamic>{
      'app': <String, dynamic>{
        'min_supported_version': '1.0.0',
        'latest_version': '1.2.0',
        'update_url_android': 'https://play.google.com/x',
        'update_url_ios': '',
        'maintenance_active': true,
        'maintenance_message': ' Bakımdayız ',
      },
      'support': <String, dynamic>{'email': 'destek@ahbu.example', 'phone': '', 'hours': null, 'web_url': ''},
      'legal': <String, dynamic>{
        'company_name': 'Güde Teknoloji',
        'company_address': '',
        'mersis_no': '',
        'kep_address': '',
        'contact_email': '',
        'contact_phone': '',
        'enforce_consents': true,
      },
    };

    test('fromJson / toJson gidiş dönüş; metinler kırpılır, null boş olur', () {
      final config = PlatformConfig.fromJson(body());
      expect(config.app.maintenanceActive, isTrue);
      expect(config.app.maintenanceMessage, 'Bakımdayız');
      expect(config.support.hours, '');
      expect(config.legal.enforceConsents, isTrue);
      final round = PlatformConfig.fromJson(
        Map<String, dynamic>.from(config.toJson()),
      );
      expect(round.sameAs(config), isTrue);
    });

    test('eksik / bozuk gövde: boş metin, kapalı anahtar', () {
      final empty = PlatformConfig.fromJson(<String, dynamic>{});
      expect(empty.app.latestVersion, '');
      expect(empty.app.maintenanceActive, isFalse);
      expect(empty.legal.enforceConsents, isFalse);
      final odd = PlatformConfig.fromJson(<String, dynamic>{
        'app': 'x',
        'support': <String, dynamic>{'email': 5},
        'legal': <String, dynamic>{'enforce_consents': 'true'},
      });
      expect(odd.support.email, '');
      expect(odd.legal.enforceConsents, isFalse, reason: 'yalnız gerçek true açar');
    });

    test('looksLikeConfig', () {
      expect(PlatformConfig.looksLikeConfig(body()), isTrue);
      expect(PlatformConfig.looksLikeConfig(<String, dynamic>{'ok': true}), isFalse);
      expect(PlatformConfig.looksLikeConfig(<String, dynamic>{'app': <String, dynamic>{}}), isTrue);
    });

    test('patchAgainst: yalnız DEĞİŞEN alanlar, iç içe, kırpılmış', () {
      final base = PlatformConfig.fromJson(body());
      const next = PlatformConfig(
        app: PlatformAppConfig(
          minSupportedVersion: '1.0.0',
          latestVersion: ' 1.3.0 ',
          updateUrlAndroid: 'https://play.google.com/x',
          maintenanceActive: false,
          maintenanceMessage: 'Bakımdayız',
        ),
        support: PlatformSupportConfig(email: 'destek@ahbu.example'),
        legal: PlatformLegalConfig(companyName: 'Güde Teknoloji', enforceConsents: true),
      );
      expect(next.patchAgainst(base), <String, Map<String, Object>>{
        'app': <String, Object>{'latest_version': '1.3.0', 'maintenance_active': false},
      });
      expect(base.patchAgainst(base), isEmpty);
      expect(next.sameAs(base), isFalse);
    });

    test('patchAgainst: boş dize "ayarsız yap" olarak gönderilir', () {
      final base = PlatformConfig.fromJson(body());
      final next = PlatformConfig.fromJson(<String, dynamic>{
        ...body(),
        'support': <String, dynamic>{'email': '', 'phone': '', 'hours': '', 'web_url': ''},
      });
      expect(next.patchAgainst(base), <String, Map<String, Object>>{
        'support': <String, Object>{'email': ''},
      });
    });

    test('yalnız boşluk farkı değişiklik sayılmaz', () {
      final base = PlatformConfig.fromJson(body());
      final next = PlatformConfig(
        app: PlatformAppConfig(
          minSupportedVersion: ' 1.0.0 ',
          latestVersion: base.app.latestVersion,
          updateUrlAndroid: base.app.updateUrlAndroid,
          maintenanceActive: base.app.maintenanceActive,
          maintenanceMessage: base.app.maintenanceMessage,
        ),
        support: base.support,
        legal: base.legal,
      );
      expect(next.sameAs(base), isTrue);
    });
  });

  group('platform doğrulayıcıları (sunucu kurallarını aynalar)', () {
    test('sürüm', () {
      expect(validatePlatformVersion('', 'Sürüm'), isNull);
      expect(validatePlatformVersion('1.2.3', 'Sürüm'), isNull);
      expect(validatePlatformVersion(' 10.20.30 ', 'Sürüm'), isNull);
      for (final bad in <String>['1.2', '1.2.3.4', 'v1.2.3', '1.2.x', '1..3', '1234567890.0.0']) {
        expect(validatePlatformVersion(bad, 'Sürüm'), isNotNull, reason: bad);
      }
    });

    test('sürüm karşılaştırma', () {
      expect(comparePlatformVersions('1.2.3', '1.2.3'), 0);
      expect(comparePlatformVersions('1.2.10', '1.2.9'), 1, reason: 'sayısal, metinsel değil');
      expect(comparePlatformVersions('0.9.9', '1.0.0'), -1);
      expect(comparePlatformVersions('1.0', '1.0.0'), isNull);
    });

    test('URL: yalnız https, boşluk / tırnak / kullanıcı bilgisi yok', () {
      expect(validatePlatformUrl('', 'Adres'), isNull);
      expect(validatePlatformUrl('https://play.google.com/store/apps/details?id=x', 'Adres'), isNull);
      expect(validatePlatformUrl('HTTPS://Example.com', 'Adres'), isNull);
      for (final bad in <String>[
        'http://example.com',
        'ftp://example.com',
        'example.com',
        'https://',
        'https://exa mple.com',
        'https://user:pw@example.com',
        'https://example.com/"x"',
        'javascript:alert(1)',
      ]) {
        expect(validatePlatformUrl(bad, 'Adres'), isNotNull, reason: bad);
      }
      expect(validatePlatformUrl('https://example.com/${'a' * 500}', 'Adres'), contains('en çok 500'));
    });

    test('e-posta', () {
      expect(validatePlatformEmail('', 'E-posta'), isNull);
      expect(validatePlatformEmail('destek@gudeteknoloji.com.tr', 'E-posta'), isNull);
      for (final bad in <String>['a@b', 'a b@c.com', '@c.com', 'a@@c.com', 'a..b@c.com', 'a@c.com,b@d.com', '<a>@c.com']) {
        expect(validatePlatformEmail(bad, 'E-posta'), isNotNull, reason: bad);
      }
    });

    test('telefon: 7-15 rakam, izinli işaretler', () {
      expect(validatePlatformPhone('', 'Tel'), isNull);
      expect(validatePlatformPhone('+90 212 000 00 00', 'Tel'), isNull);
      expect(validatePlatformPhone('0212/555-00.00', 'Tel'), isNull);
      for (final bad in <String>['12345', 'abc1234567', '1234567890123456', '+90 (212) 000 00 00 x1']) {
        expect(validatePlatformPhone(bad, 'Tel'), isNotNull, reason: bad);
      }
    });

    test('MERSİS: 16 hane, boşluk ve tire yok sayılır', () {
      expect(validatePlatformMersis(''), isNull);
      expect(validatePlatformMersis('0123 4567 8901 2345'), isNull);
      expect(validatePlatformMersis('0123-4567-8901-2345'), isNull);
      expect(validatePlatformMersis('123'), isNotNull);
      expect(validatePlatformMersis('01234567890123456'), isNotNull);
      expect(validatePlatformMersis('012345678901234a'), isNotNull);
    });

    test('yasal metin: Markdown / HTML ayırıcıları ve satır başı işaretleri yasak', () {
      expect(validatePlatformLegalText('Güde Teknoloji A.Ş.', 200, 'Unvan'), isNull);
      expect(validatePlatformLegalText('', 200, 'Unvan'), isNull);
      for (final bad in <String>['[x](http://a)', 'a <b> c', 'a`b', r'a\b', 'a **b**', '# Başlık', '- madde', '> alıntı', '*x', '+x']) {
        expect(validatePlatformLegalText(bad, 200, 'Unvan'), isNotNull, reason: bad);
      }
      expect(validatePlatformLegalText('a' * 201, 200, 'Unvan'), contains('en çok 200'));
      expect(validatePlatformText('a' * 501, 500, 'İleti'), contains('en çok 500'));
      expect(validatePlatformText('a' * 500, 500, 'İleti'), isNull);
    });
  });

  group('ClientError modelleri', () {
    test('öğe: sözleşme alanları', () {
      final item = ClientErrorItem.fromJson(<String, dynamic>{
        'fingerprint': 'abc123',
        'error_type': 'FlutterError',
        'message': 'RenderFlex overflowed',
        'app_version': '1.0.0',
        'platform': 'android',
        'fatal': true,
        'count': 12,
        'first_seen': '2026-10-01T10:00:00.000Z',
        'last_seen': '2026-10-16T07:30:00.000Z',
        'sample_stack': '#0 main (package:x/main.dart:1)',
      });
      expect(item.fingerprint, 'abc123');
      expect(item.fatal, isTrue);
      expect(item.count, 12);
      expect(item.platformLabel, 'Android');
      expect(item.firstSeen, DateTime.utc(2026, 10, 1, 10));
      expect(item.sampleStack, startsWith('#0 main'));
    });

    test('öğe: eksik / bozuk alanlara dayanıklı (parmak izi türetilir, sayı en az 1, yığın boş)', () {
      final item = ClientErrorItem.fromJson(<String, dynamic>{
        'error_type': 'StateError',
        'message': 'x',
        'app_version': '2.0.0',
        'count': 0,
        'first_seen': 'tarih değil',
        'sample_stack': null,
        'platform': 'linux',
      });
      expect(item.fingerprint, 'StateError|x|2.0.0');
      expect(item.count, 1);
      expect(item.firstSeen, isNull);
      expect(item.lastSeen, isNull);
      expect(item.sampleStack, '');
      expect(item.fatal, isFalse);
      expect(item.platformLabel, 'linux');
      expect(ClientErrorItem.fromJson(<String, dynamic>{}).platformLabel, 'Bilinmiyor');
    });

    test('platform etiketleri', () {
      String label(String p) => ClientErrorItem.fromJson(<String, dynamic>{'platform': p}).platformLabel;
      expect(label('ios'), 'iOS');
      expect(label('web'), 'Web');
      expect(label('other'), 'Diğer');
    });

    test('sayfa: imleç opak metin olarak korunur; bozuk öğeler atlanır', () {
      final page = ClientErrorPage.fromJson(<String, dynamic>{
        'items': <Object>[
          <String, dynamic>{'fingerprint': 'a'},
          'bozuk',
          <String, dynamic>{'fingerprint': 'b'},
        ],
        'next_cursor': 'WyIyMDI2LTEwIiwiNyJd',
      });
      expect(page.items.map((e) => e.fingerprint), <String>['a', 'b']);
      expect(page.nextCursor, 'WyIyMDI2LTEwIiwiNyJd');
    });

    test('sayfa: son sayfada imleç null; sayısal imleç metne çevrilir; items yoksa boş', () {
      expect(ClientErrorPage.fromJson(<String, dynamic>{'items': <Object>[], 'next_cursor': null}).nextCursor, isNull);
      expect(ClientErrorPage.fromJson(<String, dynamic>{'next_cursor': ' '}).nextCursor, isNull);
      expect(ClientErrorPage.fromJson(<String, dynamic>{'next_cursor': 42}).nextCursor, '42');
      expect(ClientErrorPage.fromJson(<String, dynamic>{}).items, isEmpty);
    });
  });
}

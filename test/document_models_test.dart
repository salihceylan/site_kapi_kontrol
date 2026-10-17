// Belge modelleri (lib/models/document_models.dart, document_upload_models.dart) ve duyuru ekleri / denetim
// kaydı bağlantıları: alan yok / bozuk ise güvenli varsayılan; kitle özeti; boyut biçimi; sözleşme (A5-A12).
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/models/document_models.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart';
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/audit_log_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

Map<String, dynamic> _summary({
  String audience = 'residents',
  String targetType = 'site',
  List<String>? labels,
  Object? current = const <String, dynamic>{
    'version_no': 2,
    'file_name': 'a.pdf',
    'mime_type': 'application/pdf',
    'size_bytes': 2516582,
    'completed_at': '2026-10-16T10:00:00Z',
  },
}) => <String, dynamic>{
  'id': 41,
  'title': '  Site Yönetmeliği ',
  'category': 'regulation',
  'audience': audience,
  'target_type': targetType,
  'status': 'active',
  'version_count': 2,
  'download_count': 12,
  'current_version': current,
  'created_at': '2026-10-15T10:00:00',
  'updated_at': '2026-10-16T10:00:00Z',
  'target_labels': ?labels,
};

void main() {
  group('enumlar', () {
    test('bilinmeyen değerler güvenli varsayılana düşer (çökme yok)', () {
      expect(DocumentCategory.fromApi('???'), DocumentCategory.other);
      expect(DocumentCategory.fromApi(null), DocumentCategory.other);
      expect(DocumentCategory.fromApi(' MINUTES '), DocumentCategory.minutes);
      expect(DocumentAudience.fromApi('everyone'), DocumentAudience.unknown);
      expect(DocumentAudience.fromApi(''), DocumentAudience.unknown);
      expect(DocumentAudience.fromApi('board'), DocumentAudience.board);
      expect(DocumentStatus.fromApi('x'), DocumentStatus.unknown);
      expect(DocumentTargetType.fromApi('x'), DocumentTargetType.site);
    });

    test('kategori etiketleri sözleşmedeki adlar', () {
      expect(DocumentCategory.values.map((c) => c.label), <String>[
        'Yönetmelik',
        'Toplantı Tutanağı / Karar',
        'Sözleşme',
        'Bilgilendirme',
        'Diğer',
      ]);
    });

    test(
      'formda seçilebilen kitleler: sakinler, kurul, yöneticiler (bilinmiyor değil)',
      () {
        expect(DocumentAudience.choices, <DocumentAudience>[
          DocumentAudience.residents,
          DocumentAudience.board,
          DocumentAudience.managers,
        ]);
      },
    );

    test('dosya türü MIME ve ada göre', () {
      expect(
        DocumentFileKind.fromMime('application/pdf'),
        DocumentFileKind.pdf,
      );
      expect(DocumentFileKind.fromMime('image/png'), DocumentFileKind.image);
      expect(
        DocumentFileKind.fromMime(
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        DocumentFileKind.word,
      );
      expect(
        DocumentFileKind.fromMime(
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
        DocumentFileKind.excel,
      );
      expect(DocumentFileKind.fromMime('', 'plan.JPG'), DocumentFileKind.image);
      expect(DocumentFileKind.fromMime('', 'x.bin'), DocumentFileKind.other);
    });
  });

  group('boyut ve zaman biçimleri', () {
    test('formatDocumentSize Türkçe ondalık virgül', () {
      expect(formatDocumentSize(0), '0 B');
      expect(formatDocumentSize(1023), '1023 B');
      expect(formatDocumentSize(1024), '1,0 KB');
      expect(formatDocumentSize(2516582), '2,4 MB');
      expect(formatDocumentSize(10 * 1024), '10 KB');
      expect(formatDocumentSize(209715200), '200 MB');
      expect(documentFileLabel('application/pdf', 2516582), 'PDF, 2,4 MB');
      expect(documentFileLabel('', 51200, 'tutanak.docx'), 'Word, 50 KB');
    });

    test('documentInstant: saat dilimi yoksa UTC; bozuk değer null', () {
      expect(
        documentInstant('2026-10-16T10:00:00Z'),
        DateTime.utc(2026, 10, 16, 10),
      );
      expect(
        documentInstant('2026-10-16 10:00:00'),
        DateTime.utc(2026, 10, 16, 10),
      );
      expect(
        documentInstant('2026-10-16T13:00:00+03:00'),
        DateTime.utc(2026, 10, 16, 10),
      );
      expect(documentInstant('bozuk'), isNull);
      expect(documentInstant(null), isNull);
      expect(documentInstant(''), isNull);
    });
  });

  group('DocumentSummary', () {
    test('alanlar çözülür; başlık kırpılır; sürüm özeti okunur', () {
      final d = DocumentSummary.fromJson(_summary());
      expect(d.id, 41);
      expect(d.title, 'Site Yönetmeliği');
      expect(d.category, DocumentCategory.regulation);
      expect(d.audience, DocumentAudience.residents);
      expect(d.status, DocumentStatus.active);
      expect(d.versionCount, 2);
      expect(d.downloadCount, 12);
      expect(d.currentVersion?.versionNo, 2);
      expect(d.currentVersion?.sizeBytes, 2516582);
      expect(d.currentVersion?.kind, DocumentFileKind.pdf);
      expect(
        d.createdAt,
        DateTime.utc(2026, 10, 15, 10),
        reason: 'saat dilimsiz = UTC',
      );
      expect(d.isDeleted, isFalse);
    });

    test('{"document": {...}} sarmalı açılır; eksik alanlarda çökme yok', () {
      final d = DocumentSummary.fromJson(<String, dynamic>{
        'document': <String, dynamic>{'id': '9'},
      });
      expect(d.id, 9);
      expect(d.title, '');
      expect(d.category, DocumentCategory.other);
      expect(d.audience, DocumentAudience.unknown);
      expect(d.currentVersion, isNull);
      expect(d.audienceSummary, 'Kitle bilinmiyor');
      final empty = DocumentSummary.fromJson(<String, dynamic>{});
      expect(empty.id, 0);
    });

    test('kitle özeti: sakinler, kurul, yöneticiler, bloklar, daireler', () {
      String summary(Map<String, dynamic> json) =>
          DocumentSummary.fromJson(json).audienceSummary;
      expect(summary(_summary()), 'Tüm sakinler');
      expect(summary(_summary(audience: 'board')), 'Yönetim kurulu');
      expect(summary(_summary(audience: 'managers')), 'Yalnız yöneticiler');
      expect(summary(_summary(targetType: 'blocks')), 'Seçili bloklar');
      expect(
        summary(_summary(targetType: 'blocks', labels: <String>['A', 'B'])),
        'A, B Blok',
      );
      expect(
        summary(
          _summary(targetType: 'blocks', labels: <String>['A Blok', 'B Blok']),
        ),
        'A, B Blok',
      );
      expect(
        summary(
          _summary(
            targetType: 'blocks',
            labels: <String>['A', 'B', 'C', 'D', 'E'],
          ),
        ),
        'A, B, C Blok ve 2 daha',
      );
      expect(summary(_summary(targetType: 'apartments')), 'Seçili daireler');
      expect(
        summary(
          _summary(
            targetType: 'apartments',
            labels: <String>['A Blok - 5', 'B Blok - 2'],
          ),
        ),
        'A Blok - 5, B Blok - 2',
      );
    });

    test(
      'hedef yalnız sakin kitlesinde anlamlı: kurul belgesi blok etiketi taşısa da "Yönetim kurulu"',
      () {
        expect(
          DocumentSummary.fromJson(
            _summary(
              audience: 'board',
              targetType: 'blocks',
              labels: <String>['A'],
            ),
          ).audienceSummary,
          'Yönetim kurulu',
        );
      },
    );

    test('silinmiş belge: kalan gün ve çip metni', () {
      final d = DocumentSummary.fromJson(<String, dynamic>{
        ..._summary(),
        'status': 'deleted',
        'deleted_at': '2026-10-16T08:00:00Z',
        'days_until_purge': 12,
      });
      expect(d.isDeleted, isTrue);
      expect(d.daysUntilPurge, 12);
      expect(
        DocumentDeletedChip.remainingText(12),
        'Silindi · 12 gün sonra kalıcı silinir',
      );
      expect(
        DocumentDeletedChip.remainingText(0),
        'Silindi · bugün kalıcı silinir',
      );
      expect(DocumentDeletedChip.remainingText(null), 'Silindi');
    });
  });

  group('DocumentDetail', () {
    test(
      'sürümler yeniden eskiye; güncel sürüm özeti sürümlerden türetilir; hedef etiketleri birleşir',
      () {
        final d = DocumentDetail.fromJson(<String, dynamic>{
          'id': 7,
          'title': 'T',
          'audience': 'residents',
          'status': 'active',
          'description': ' açıklama ',
          'target': <String, dynamic>{
            'type': 'apartments',
            'apartment_ids': <int>[301, 302],
            'apartments': <Object>[
              <String, dynamic>{'id': 301, 'label': 'A Blok - 5'},
              <String, dynamic>{'id': 302, 'label': 'A Blok - 6'},
            ],
          },
          'versions': <Object>[
            <String, dynamic>{
              'version_no': 1,
              'file_name': 'v1.pdf',
              'size_bytes': 10,
            },
            <String, dynamic>{
              'version_no': 3,
              'file_name': 'v3.pdf',
              'size_bytes': 30,
              'is_current': true,
              'mime_type': 'application/pdf',
            },
            <String, dynamic>{
              'version_no': 2,
              'file_name': 'v2.pdf',
              'size_bytes': 20,
            },
          ],
          'attached_announcements': <Object>[
            <String, dynamic>{'id': 4, 'status': 'published'},
            <String, dynamic>{'id': 'bozuk'},
          ],
        });
        expect(d.description, 'açıklama');
        expect(d.versions.map((v) => v.versionNo), <int>[3, 2, 1]);
        expect(d.currentVersion?.versionNo, 3);
        expect(d.versionCount, 3);
        expect(d.targetType, DocumentTargetType.apartments);
        expect(d.audienceSummary, 'A Blok - 5, A Blok - 6');
        expect(d.target.apartmentIds, <int>[301, 302]);
        expect(d.attachedAnnouncements.map((a) => a.id), <int>[4]);
      },
    );

    test('kurul yanıtında yükleyen adı YOK: alan null', () {
      final d = DocumentDetail.fromJson(<String, dynamic>{
        'id': 1,
        'versions': <Object>[],
      });
      expect(d.uploadedByName, isNull);
      expect(d.versions, isEmpty);
    });
  });

  group('DocumentUsage ve DocumentPage', () {
    test(
      'kota bilinmiyorsa çubuk çizilmez; taşan kullanım 1.0 ile sınırlanır',
      () {
        expect(const DocumentUsage().hasQuota, isFalse);
        expect(const DocumentUsage(usedBytes: 5, quotaBytes: 0).fraction, 0);
        const over = DocumentUsage(usedBytes: 300, quotaBytes: 200);
        expect(over.fraction, 1.0);
        expect(over.remainingBytes, 0);
        final u = DocumentUsage.fromJson(<String, dynamic>{
          'used_bytes': 44040192,
          'quota_bytes': 209715200,
          'document_count': 41,
          'document_limit': 2000,
        });
        expect(u.label, '42 MB / 200 MB');
        expect(u.remainingBytes, 209715200 - 44040192);
        expect(DocumentUsage.fromJson('x').hasQuota, isFalse);
      },
    );

    test('sayfa: toplam yoksa öğe sayısı; usage yoksa null', () {
      final page = DocumentPage.fromJson(<String, dynamic>{
        'items': <Object>[_summary(), 'bozuk', _summary()],
      });
      expect(page.items, hasLength(2));
      expect(page.total, 2);
      expect(page.usage, isNull);
      expect(DocumentPage.fromJson(<String, dynamic>{}).items, isEmpty);
    });
  });

  group('sakin modelleri', () {
    test('ResidentDocument: is_updated yoksa sürüm > 1 ile türetilir', () {
      final updated = ResidentDocument.fromJson(<String, dynamic>{
        'id': 3,
        'site_code': 11,
        'site_name': 'Gül Sitesi',
        'title': 'Plan',
        'category': 'notice',
        'file_name': 'plan.png',
        'mime_type': 'image/png',
        'size_bytes': 1024,
        'version_no': 2,
      });
      expect(updated.isUpdated, isTrue);
      expect(updated.kind, DocumentFileKind.image);
      expect(updated.category, DocumentCategory.notice);
      final fresh = ResidentDocument.fromJson(<String, dynamic>{
        'id': 4,
        'version_no': 1,
      });
      expect(fresh.isUpdated, isFalse);
      final explicit = ResidentDocument.fromJson(<String, dynamic>{
        'id': 5,
        'version_no': 1,
        'is_updated': true,
      });
      expect(explicit.isUpdated, isTrue);
    });

    test('ResidentDocumentPage: imleç ve boş sayfa', () {
      final page = ResidentDocumentPage.fromJson(<String, dynamic>{
        'items': <Object>[
          <String, dynamic>{'id': 9},
        ],
        'next_before_id': 9,
      });
      expect(page.hasMore, isTrue);
      expect(page.nextBeforeId, 9);
      expect(
        ResidentDocumentPage.fromJson(<String, dynamic>{}).hasMore,
        isFalse,
      );
    });
  });

  group('duyuru ekleri', () {
    test(
      'DocumentAttachment.listFrom: geçersiz öğeler atılır; available varsayılan true',
      () {
        final list = DocumentAttachment.listFrom(<Object>[
          <String, dynamic>{
            'document_id': 4,
            'title': 'Plan',
            'file_name': 'plan.pdf',
            'mime_type': 'application/pdf',
            'size_bytes': 2516582,
            'available': true,
          },
          <String, dynamic>{
            'document_id': 5,
            'title': 'Silinmiş',
            'available': false,
          },
          <String, dynamic>{'title': 'kimliksiz'},
          'bozuk',
        ]);
        expect(list.map((a) => a.documentId), <int>[4, 5]);
        expect(list.first.fileLabel, 'PDF, 2,4 MB');
        expect(list.last.available, isFalse);
        expect(DocumentAttachment.listFrom(null), isEmpty);
        expect(DocumentAttachment.listFrom('x'), isEmpty);
      },
    );

    test(
      'AnnouncementDetail ve ResidentAnnouncement ekleri okur; eski sunucuda boş; copyWith korur',
      () {
        final detail = AnnouncementDetail.fromJson(<String, dynamic>{
          'id': 41,
          'title': 'Duyuru',
          'body': 'Metin',
          'status': 'published',
          'attachments': <Object>[
            <String, dynamic>{
              'document_id': 4,
              'title': 'Plan',
              'available': true,
            },
          ],
        });
        expect(detail.attachments.single.documentId, 4);
        expect(
          detail.attachmentCount,
          1,
          reason: 'attachment_count yoksa liste uzunluğu',
        );
        final withCount = AnnouncementSummary.fromJson(<String, dynamic>{
          'id': 1,
          'attachment_count': 3,
        });
        expect(withCount.attachmentCount, 3);
        final old = AnnouncementDetail.fromJson(<String, dynamic>{
          'id': 2,
          'title': 'x',
          'body': 'y',
        });
        expect(old.attachments, isEmpty);
        expect(old.attachmentCount, 0);

        final resident = ResidentAnnouncement.fromJson(<String, dynamic>{
          'id': 7,
          'title': 'D',
          'attachments': <Object>[
            <String, dynamic>{
              'document_id': 4,
              'title': 'Plan',
              'available': false,
            },
          ],
        });
        expect(resident.attachments.single.available, isFalse);
        expect(
          resident.copyWith(isRead: true).attachments.single.documentId,
          4,
        );
        expect(
          ResidentAnnouncement.fromJson(<String, dynamic>{'id': 8}).attachments,
          isEmpty,
        );
      },
    );
  });

  group('istek gövdeleri', () {
    test(
      'DocumentCreateRequest: boş açıklama / not gönderilmez; hedef yalnız sakin kitlesinde',
      () {
        const file = DocumentFileInput(name: 'a.pdf', size: 10);
        final managers = const DocumentCreateRequest(
          title: ' T ',
          description: '  ',
          category: DocumentCategory.contract,
          audience: DocumentAudience.managers,
          target: DocumentTargetInput(
            type: DocumentTargetType.blocks,
            blockIds: <int>[1],
          ),
          file: file,
          idempotencyKey: 'k',
          note: '',
        ).toJson();
        expect(managers.containsKey('description'), isFalse);
        expect(managers.containsKey('note'), isFalse);
        expect(managers.containsKey('target'), isFalse);
        expect(managers['title'], 'T');
        expect(managers['file'], <String, dynamic>{
          'name': 'a.pdf',
          'size': 10,
        });

        final residents = const DocumentCreateRequest(
          title: 'T',
          category: DocumentCategory.notice,
          audience: DocumentAudience.residents,
          target: DocumentTargetInput(
            type: DocumentTargetType.apartments,
            apartmentIds: <int>[5, 6],
          ),
          file: file,
          idempotencyKey: 'k',
        ).toJson();
        expect(residents['target'], <String, dynamic>{
          'type': 'apartments',
          'apartment_ids': <int>[5, 6],
        });
        expect(const DocumentTargetInput().toJson(), <String, dynamic>{
          'type': 'site',
        });
      },
    );

    test('yükleme bileti: eksik alanlarda güvenli varsayılan', () {
      final t = DocumentUploadTicket.fromJson(<String, dynamic>{});
      expect(t.document.id, 0);
      expect(t.upload.path, '');
      expect(t.upload.method, 'PUT');
      expect(t.warnings, isEmpty);
      final full = DocumentUploadTicket.fromJson(<String, dynamic>{
        'document': <String, dynamic>{'id': 3, 'status': 'pending'},
        'version': <String, dynamic>{'version_no': 2},
        'upload': <String, dynamic>{
          'method': 'put',
          'path': '/manager/sites/1/documents/3/versions/2/content',
          'size': 99,
          'max_bytes': 10485760,
          'expires_at': '2026-10-16T12:00:00Z',
        },
        'warnings': <Object>[
          <String, dynamic>{'code': 'DUPLICATE_CONTENT'},
          'BASKA',
        ],
      });
      expect(full.upload.method, 'PUT');
      expect(full.upload.maxBytes, 10485760);
      expect(full.version?.versionNo, 2);
      expect(full.warnings, <String>['DUPLICATE_CONTENT', 'BASKA']);
    });
  });

  group('denetim kaydı bağlantısı', () {
    test(
      'belge eylemleri Türkçe etiketlenir; hedef "Belge #id"; modül adı',
      () {
        final labels = <String, String>{
          'document.created': 'Belge yüklendi',
          'document.version_added': 'Belge sürümü eklendi',
          'document.updated': 'Belge düzenlendi',
          'document.deleted': 'Belge silindi',
          'document.restored': 'Belge geri yüklendi',
          'document.purged': 'Belge kalıcı silindi',
          'document.version_deleted': 'Belge sürümü silindi',
          'document.attached': 'Belge duyuruya eklendi',
          'document.detached': 'Belge duyurudan çıkarıldı',
        };
        for (final entry in labels.entries) {
          expect(
            documentActionLabel(entry.key),
            entry.value,
            reason: entry.key,
          );
          final audit = AuditLogEntry.fromJson(<String, dynamic>{
            'id': 1,
            'action': entry.key,
            'target_type': 'document',
            'target_id': '41',
          });
          expect(audit.actionLabel, entry.value, reason: entry.key);
          expect(audit.targetLabel, 'Belge #41');
          final filters = AuditLogView.actionFilters
              .where((f) => f.$1 == entry.key)
              .toList();
          expect(filters, hasLength(1), reason: 'süzgeç: ${entry.key}');
          expect(filters.single.$2, entry.value);
        }
        expect(documentActionLabel('document.xyz'), isNull);
        expect(
          AuditLogEntry.fromJson(<String, dynamic>{
            'id': 2,
            'action': 'document.xyz',
          }).actionLabel,
          'Diğer işlem',
        );
        final moduleAudit = AuditLogEntry.fromJson(<String, dynamic>{
          'id': 3,
          'action': 'module.enabled',
          'target_type': 'module',
          'target_id': 'documents',
        });
        expect(moduleAudit.targetLabel, 'Belgeler (Dosya Deposu)');
        final values = AuditLogView.actionFilters.map((f) => f.$1).toList();
        expect(
          values.toSet().length,
          values.length,
          reason: 'süzgeç değerleri tekrarlanmaz',
        );
      },
    );

    test(
      'ton: oluşturma / geri yükleme başarı, silme uyarı, kalıcı silme tehlike',
      () {
        expect(auditToneOf('document.created'), AppTone.success);
        expect(auditToneOf('document.restored'), AppTone.success);
        expect(auditToneOf('document.deleted'), AppTone.warning);
        expect(auditToneOf('document.version_deleted'), AppTone.warning);
        expect(auditToneOf('document.purged'), AppTone.danger);
        expect(auditToneOf('document.updated'), AppTone.info);
      },
    );
  });
}

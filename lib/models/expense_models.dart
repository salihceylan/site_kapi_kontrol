import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart' show announcementInstant;
import 'package:site_kapi_kontrol/models/expense_analysis.dart' show ExpenseNature;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;

/// Gider kaydı, kategori, tedarikçi ve gider belgesi modelleri (Platform Faz 4b, Ö3).
///
/// Gider NAKİT esaslıdır: her gider bir hesaptan çıkar. Gider silinmez; İPTAL (void) edilir ya da düzeltilir
/// (iptal + yeni gider). KDV tutara DAHİLDİR. Kategori / tedarikçi adları kayıtta anlık görüntüdür.

/// Gider kategorisi.
@immutable
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.isSystem = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.fund,
  });

  final int id;
  final String name;
  final bool isSystem;
  final bool isActive;
  final int sortOrder;

  /// Kategorinin kasası (`fund`): bu kategorideki gider varsayılan olarak bu kasadan çıkar. Eski sunucuda null
  /// ([effectiveFund] İşletme Projesi (Aidat) Hesabı sayar).
  final FinanceFund? fund;

  FinanceFund get effectiveFund => fund ?? FinanceFund.operating;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) => ExpenseCategory(
    id: f4Int(json['id']),
    name: f4Str(json['name']),
    isSystem: f4Bool(json['is_system']),
    isActive: f4Bool(json['is_active'], fallback: true),
    sortOrder: f4Int(json['sort_order']),
    fund: FinanceFund.tryParse(json['fund']),
  );
}

/// Tedarikçi. Kurul okurken `tax_id` / `phone` / `note` null gelir.
@immutable
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.taxId,
    this.phone,
    this.note,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? taxId;
  final String? phone;
  final String? note;
  final bool isActive;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: f4Int(json['id']),
    name: f4Str(json['name']),
    taxId: f4Text(json['tax_id']),
    phone: f4Text(json['phone']),
    note: f4Text(json['note']),
    isActive: f4Bool(json['is_active'], fallback: true),
  );
}

@immutable
class SupplierPage {
  const SupplierPage({this.items = const <Supplier>[], this.total = 0});

  final List<Supplier> items;
  final int total;

  factory SupplierPage.fromJson(Map<String, dynamic> json) {
    final items = f4List(json['items'], Supplier.fromJson);
    return SupplierPage(items: items, total: f4Int(json['total'], items.length));
  }
}

/// Belge türü (`document_kind`).
enum ExpenseDocumentKind {
  none('none', 'Belgesiz'),
  invoice('invoice', 'Fatura'),
  receipt('receipt', 'Fiş / makbuz'),
  contract('contract', 'Sözleşme'),
  other('other', 'Diğer');

  const ExpenseDocumentKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ExpenseDocumentKind fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final kind in values) {
        if (kind.apiValue == normalized) return kind;
      }
    }
    return none;
  }
}

/// Gider eki türü (`expense_documents.kind`).
enum ExpenseAttachmentKind {
  invoice('invoice', 'Fatura'),
  receipt('receipt', 'Fiş / makbuz'),
  photo('photo', 'Fotoğraf'),
  other('other', 'Diğer');

  const ExpenseAttachmentKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ExpenseAttachmentKind fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final kind in values) {
        if (kind.apiValue == normalized) return kind;
      }
    }
    return other;
  }
}

/// İptal bilgisi (`voided: {at, reason, period}`).
@immutable
class ExpenseVoidInfo {
  const ExpenseVoidInfo({this.at, this.reason, this.period});

  final DateTime? at;
  final String? reason;
  final FinancePeriod? period;

  static ExpenseVoidInfo? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return ExpenseVoidInfo(
      at: announcementInstant(map['at']),
      reason: f4Text(map['reason']),
      period: FinancePeriod.tryParse(map['period']),
    );
  }
}

/// Giderin eki (belge bağlantısı).
@immutable
class ExpenseAttachment {
  const ExpenseAttachment({
    required this.id,
    this.status = 'ready',
    this.displayName = '',
    this.mimeType,
    this.sizeBytes = 0,
    this.kind = ExpenseAttachmentKind.other,
    this.addedAt,
  });

  final int id;

  /// `uploading` / `ready`.
  final String status;
  final String displayName;
  final String? mimeType;
  final int sizeBytes;
  final ExpenseAttachmentKind kind;
  final DateTime? addedAt;

  bool get isReady => status == 'ready';

  factory ExpenseAttachment.fromJson(Map<String, dynamic> json) => ExpenseAttachment(
    id: f4Int(json['id']),
    status: f4Str(json['status'], 'ready'),
    displayName: f4Str(json['display_name'] ?? json['name']),
    mimeType: f4Text(json['mime_type']),
    sizeBytes: f4Int(json['size_bytes']),
    kind: ExpenseAttachmentKind.fromApi(json['kind']),
    addedAt: announcementInstant(json['added_at']),
  );
}

/// Gider (`Expense`).
@immutable
class Expense {
  const Expense({
    required this.id,
    this.categoryName = '',
    this.supplierName,
    this.description = '',
    required this.amountMinor,
    this.vatMinor,
    this.expenseDate,
    this.categoryId,
    this.supplierId,
    this.accountId,
    this.accountName,
    this.documentKind = ExpenseDocumentKind.none,
    this.documentNo,
    this.voided,
    this.correctsExpenseId,
    this.documentsCount = 0,
    this.createdByName,
    this.createdAt,
    this.nature,
    this.natureSource,
    this.attachments = const <ExpenseAttachment>[],
    this.fund,
  });

  final int id;
  final String categoryName;

  /// Giderin kasası (`fund`; satıra HER ZAMAN yazılır); 080 öncesi giderde ve eski sunucuda null.
  final FinanceFund? fund;
  final String? supplierName;
  final String description;
  final int amountMinor;
  final int? vatMinor;
  final DateTime? expenseDate;

  /// Sunucu yanıtında kimlikler varsa dolu (düzeltme formunu önceden doldurmak için); yoksa null ve ad eşlenir.
  final int? categoryId;
  final int? supplierId;
  final int? accountId;
  final String? accountName;
  final ExpenseDocumentKind documentKind;
  final String? documentNo;
  final ExpenseVoidInfo? voided;
  final int? correctsExpenseId;
  final int documentsCount;
  final String? createdByName;
  final DateTime? createdAt;

  /// Gider türü (rutin / beklenmedik); eski sunucu göndermezse null.
  final ExpenseNature? nature;

  /// suggested | manual | derived.
  final String? natureSource;

  /// Yalnız ayrıntı (`GET expenses/:id`) yanıtında dolu.
  final List<ExpenseAttachment> attachments;

  bool get isVoided => voided != null;

  factory Expense.fromJson(Map<String, dynamic> json) {
    final account = f4Map(json['account']);
    final documents = f4List(json['documents'], ExpenseAttachment.fromJson);
    return Expense(
      id: f4Int(json['id']),
      categoryName: f4Str(json['category_name']),
      supplierName: f4Text(json['supplier_name']),
      description: f4Str(json['description']),
      amountMinor: f4Minor(json, 'amount_minor'),
      vatMinor: f4MinorOrNull(json, 'vat_minor'),
      expenseDate: f4Date(json['expense_date']),
      categoryId: f4IntOrNull(json['category_id']),
      supplierId: f4IntOrNull(json['supplier_id']),
      accountId: f4IntOrNull(account['id'] ?? json['account_id']),
      accountName: f4Text(account['name'] ?? json['account_name']),
      documentKind: ExpenseDocumentKind.fromApi(json['document_kind']),
      documentNo: f4Text(json['document_no']),
      voided: ExpenseVoidInfo.tryParse(json['voided']),
      correctsExpenseId: f4IntOrNull(json['corrects_expense_id']),
      documentsCount: f4Int(json['documents_count'], documents.length),
      createdByName: f4Text(json['created_by_name']),
      createdAt: announcementInstant(json['created_at']),
      nature: ExpenseNature.tryParse(json['nature']),
      natureSource: f4Text(json['nature_source']),
      attachments: documents,
      fund: FinanceFund.tryParse(json['fund']),
    );
  }
}

@immutable
class ExpenseTotals {
  const ExpenseTotals({this.activeMinor = 0, this.voidedMinor = 0});

  final int activeMinor;
  final int voidedMinor;

  factory ExpenseTotals.fromJson(Map<String, dynamic> json) => ExpenseTotals(
    activeMinor: f4Minor(json, 'active_minor'),
    voidedMinor: f4Minor(json, 'voided_minor'),
  );
}

/// `GET expenses`.
@immutable
class ExpensePage {
  const ExpensePage({this.items = const <Expense>[], this.nextBeforeId, this.totals});

  final List<Expense> items;
  final int? nextBeforeId;

  /// Süzgece uyan toplamlar (yok = sunucu göndermedi; sıfır DEĞİL).
  final ExpenseTotals? totals;

  factory ExpensePage.fromJson(Map<String, dynamic> json) => ExpensePage(
    items: f4List(json['items'], Expense.fromJson),
    nextBeforeId: f4IntOrNull(json['next_before_id']),
    totals: json['totals'] is Map ? ExpenseTotals.fromJson(f4Map(json['totals'])) : null,
  );
}

/// `POST expenses` yanıtı.
@immutable
class ExpenseWriteResult {
  const ExpenseWriteResult({required this.expense, this.accountBalanceMinor});

  final Expense expense;
  final int? accountBalanceMinor;

  factory ExpenseWriteResult.fromJson(Map<String, dynamic> json) {
    final expense = json['expense'];
    if (expense is! Map) throw const FormatException('Gider okunamadı: expense');
    return ExpenseWriteResult(
      expense: Expense.fromJson(Map<String, dynamic>.from(expense)),
      accountBalanceMinor: f4MinorOrNull(json, 'account_balance_minor'),
    );
  }
}

/// `POST expenses/:id/correct` yanıtı: iptal edilen eski gider + yeni gider.
@immutable
class ExpenseCorrectResult {
  const ExpenseCorrectResult({this.voided, required this.expense});

  final Expense? voided;
  final Expense expense;

  factory ExpenseCorrectResult.fromJson(Map<String, dynamic> json) {
    final expense = json['expense'];
    if (expense is! Map) throw const FormatException('Gider okunamadı: expense');
    final voided = json['voided'];
    return ExpenseCorrectResult(
      voided: voided is Map ? Expense.fromJson(Map<String, dynamic>.from(voided)) : null,
      expense: Expense.fromJson(Map<String, dynamic>.from(expense)),
    );
  }
}

/// 409 `DUPLICATE_EXPENSE` / `DUPLICATE_DOCUMENT_NO` yanıtındaki mevcut gider.
int? existingExpenseIdOf(Map<String, dynamic>? payload) => f4IntOrNull(payload?['existing_expense_id']);

/// Gider oluşturma / düzeltme gövdesi. Tutarlar KURUŞ; tarih takvim günü.
@immutable
class ExpenseInput {
  const ExpenseInput({
    required this.categoryId,
    this.supplierId,
    required this.description,
    required this.amountMinor,
    this.vatMinor,
    required this.expenseDate,
    required this.accountId,
    this.documentKind = ExpenseDocumentKind.none,
    this.documentNo,
    this.allowDuplicate = false,
    this.nature,
    this.fund,
  });

  final int categoryId;
  final int? supplierId;
  final String description;
  final int amountMinor;
  final int? vatMinor;
  final DateTime expenseDate;
  final int accountId;
  final ExpenseDocumentKind documentKind;
  final String? documentNo;
  final bool allowDuplicate;

  /// Seçilen gider türü; null ise sunucu öneriyi yazar.
  final ExpenseNature? nature;

  /// Giderin kasası; null ise alan gönderilmez (sunucu kategorinin kasasını yazar).
  final FinanceFund? fund;

  /// İstek parmak izine girmeyen `allow_duplicate` hariç sunucu gövdesi.
  Map<String, dynamic> toJson() {
    final no = documentNo?.trim();
    return <String, dynamic>{
      'category_id': categoryId,
      'supplier_id': ?supplierId,
      'description': description.trim(),
      'amount_minor': amountMinor,
      'vat_minor': ?vatMinor,
      'expense_date': crmDateParam(expenseDate),
      'account_id': accountId,
      'document_kind': documentKind.apiValue,
      if (no != null && no.isNotEmpty) 'document_no': no,
      if (allowDuplicate) 'allow_duplicate': true,
      if (nature != null) 'nature': nature!.apiValue,
      if (fund != null) 'fund': fund!.apiValue,
    };
  }
}

/// `POST expenses/:id/documents` yanıtı: oluşan belge kaydı + yükleme bileti (iki adımlı yükleme).
@immutable
class ExpenseUploadTicket {
  const ExpenseUploadTicket({
    required this.document,
    required this.method,
    required this.path,
    required this.contentType,
    required this.size,
    this.maxBytes,
    this.expiresAt,
    this.alreadyStored = false,
  });

  final ExpenseAttachment document;
  final String method;
  final String path;
  final String contentType;
  final int size;
  final int? maxBytes;
  final DateTime? expiresAt;

  /// Aynı işlem anahtarıyla yeniden denemede belge ZATEN yüklenmiş (sunucu `upload: null` döner): ikinci yükleme yapılmaz.
  final bool alreadyStored;

  factory ExpenseUploadTicket.fromJson(Map<String, dynamic> json) {
    final document = json['document'];
    final upload = json['upload'];
    if (document is Map && upload == null) {
      final parsed = ExpenseAttachment.fromJson(Map<String, dynamic>.from(document));
      if (parsed.status == 'ready') {
        return ExpenseUploadTicket(
          document: parsed,
          method: 'PUT',
          path: '',
          contentType: 'application/octet-stream',
          size: parsed.sizeBytes,
          alreadyStored: true,
        );
      }
    }
    if (document is! Map || upload is! Map) {
      throw const FormatException('Yükleme bilgisi okunamadı: upload');
    }
    final up = Map<String, dynamic>.from(upload);
    final path = f4Text(up['path']);
    if (path == null) throw const FormatException('Yükleme yolu okunamadı: path');
    return ExpenseUploadTicket(
      document: ExpenseAttachment.fromJson(Map<String, dynamic>.from(document)),
      method: f4Str(up['method'], 'PUT'),
      path: path,
      contentType: f4Str(up['content_type'], 'application/octet-stream'),
      size: f4Int(up['size']),
      maxBytes: f4IntOrNull(up['max_bytes']),
      expiresAt: announcementInstant(up['expires_at']),
    );
  }
}

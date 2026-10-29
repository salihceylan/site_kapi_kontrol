// Aidat ve Finans Faz 4b uçları (docs/PLATFORM_FINANS_4B.md): makbuz, gecikme tazminatı, kasa/banka, gider,
// raporlar, dışa aktarma zarfı, borç hatırlatma ve finans ayarları.
//
// [Finance4bApi]: yalnız HTTP katmanı (belirteci çağıran verir; hata gövdesini Türkçe [ApiException]'a çevirir).
// [Finance4bService]: oturum belirtecini [AuthService]'ten alır ve oturum hatasını merkezi çıkışa bağlar.
//
// Kurallar (AuthApi / AccountApi ile aynı):
// - Mutasyonlar (POST/PUT/PATCH/DELETE) ASLA otomatik yeniden denenmez; çift kayıt `idempotency_key` ile
//   önlenir (aynı anahtar + aynı gövde = 200 tekrar, farklı gövde = 409 IDEMPOTENCY_CONFLICT).
// - Tutarlar KURUŞ tamsayıdır; kayan nokta yoktur.
// - 401 yetkili uçlarda "oturum bitti"dir; JSON olmayan 401/403 (proxy / captive portal) geçici ağ hatasıdır.
// - Belirteç, gövde ve kişisel veri günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/bulk_import.dart' show ExportEnvelope;
import 'package:site_kapi_kontrol/models/cash_models.dart';
import 'package:site_kapi_kontrol/models/check_mark.dart';
import 'package:site_kapi_kontrol/models/expense_analysis.dart';
import 'package:site_kapi_kontrol/models/enforcement_models.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/finance_charts.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/models/finance_liability.dart';
import 'package:site_kapi_kontrol/models/finance_refund.dart';
import 'package:site_kapi_kontrol/models/fund_models.dart';
import 'package:site_kapi_kontrol/models/late_fee_models.dart';
import 'package:site_kapi_kontrol/models/period_report_models.dart';
import 'package:site_kapi_kontrol/models/receipt_models.dart';
import 'package:site_kapi_kontrol/models/reminder_models.dart';
import 'package:site_kapi_kontrol/models/report_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/finance_4b_errors.dart';

/// Sunucu yanıtı: durum kodu + çözülmüş gövde (boş olabilir).
class Finance4bResponse {
  const Finance4bResponse(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;

  /// 201 = yeni kayıt; 200 = aynı `idempotency_key` ile tekrar (kayıt döndü).
  bool get created => status == 201;
}

class Finance4bApi {
  Finance4bApi({
    required String baseUrl,
    http.Client? client,
    Duration readTimeout = const Duration(seconds: 25),
    Duration writeTimeout = const Duration(seconds: 45),
    Duration uploadTimeout = const Duration(seconds: 120),
    this.maxDownloadBytes = 25 * 1024 * 1024,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _readTimeout = readTimeout,
       _writeTimeout = writeTimeout,
       _uploadTimeout = uploadTimeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _readTimeout;
  final Duration _writeTimeout;
  final Duration _uploadTimeout;
  final int maxDownloadBytes;

  static String _site(int siteCode, String tail) => '/manager/sites/$siteCode/finance/$tail';

  // --- Ayarlar -----------------------------------------------------------------------------------

  Future<FinanceSettings> getSettings({required String token, required int siteCode}) async {
    final r = await _send('GET', _site(siteCode, 'settings'), token: token);
    return _parse('Ayarlar', () => FinanceSettings.fromJson(r.body));
  }

  /// Kısmi güncelleme. Yanıt güncel ayarları taşımıyorsa null (çağıran ayarları yeniden okur).
  Future<FinanceSettings?> updateSettings({
    required String token,
    required int siteCode,
    required FinanceSettingsPatch patch,
    required int expectedVersion,
  }) async {
    final r = await _send(
      'PUT',
      _site(siteCode, 'settings'),
      token: token,
      body: patch.toJson(expectedVersion),
      write: true,
    );
    if (r.body['settings_version'] == null) return null;
    return _parse('Ayarlar', () => FinanceSettings.fromJson(r.body));
  }

  // --- Hukuk onayı bayrağı (yalnız süper kullanıcı; SİTE başına, sites.legal_ok) -------------------------------

  static String _legalGate(int siteCode) => '/admin/sites/$siteCode/finance-legal-gate';

  /// Sitenin hukuk onayı bayrağı (gecikme tazminatı / borç hatırlatma açılabilir mi?).
  Future<bool> getSiteLegalGate({required String token, required int siteCode}) async {
    final r = await _send('GET', _legalGate(siteCode), token: token);
    return _parse('Hukuk onayı', () => _legalGateValue(r.body));
  }

  /// Bayrağı [enabled] yapar (işlem izi sunucuda tutulur). Dönen değer sunucunun kaydettiği son durumdur.
  Future<bool> setSiteLegalGate({required String token, required int siteCode, required bool enabled}) async {
    final r = await _send(
      'PUT',
      _legalGate(siteCode),
      token: token,
      body: <String, dynamic>{'legal_ok': enabled},
      write: true,
    );
    return _parse('Hukuk onayı', () => _legalGateValue(r.body));
  }

  static bool _legalGateValue(Map<String, dynamic> body) {
    final value = body['legal_ok'];
    if (value is! bool) throw const FormatException('legal_ok');
    return value;
  }

  // --- Makbuz ------------------------------------------------------------------------------------

  Future<ReceiptPage> listReceipts({
    required String token,
    required int siteCode,
    int? apartmentId,
    int? year,
    ReceiptKind? kind,
    String? query,
    int limit = 50,
    int? beforeId,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'receipts'),
      token: token,
      query: <String, String>{
        if (apartmentId != null) 'apartment_id': '$apartmentId',
        if (year != null) 'year': '$year',
        if (kind != null && kind != ReceiptKind.unknown) 'kind': kind.apiValue,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
    );
    return _parse('Makbuzlar', () => ReceiptPage.fromJson(r.body));
  }

  Future<Receipt> getReceipt({required String token, required int siteCode, required int receiptId}) async {
    final r = await _send('GET', _site(siteCode, 'receipts/$receiptId'), token: token);
    return _parse('Makbuz', () => Receipt.fromJson(_unwrap(r.body, 'receipt')));
  }

  /// Eski / otomatiksiz tahsilat için makbuz düzenler (idempotent: aktif makbuz varsa onu döndürür, 200).
  Future<ReceiptIssueResult> issueReceipt({
    required String token,
    required int siteCode,
    required int entryId,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'entries/$entryId/receipt'),
      token: token,
      body: const <String, dynamic>{},
      write: true,
    );
    return _parse(
      'Makbuz',
      () => ReceiptIssueResult(receipt: Receipt.fromJson(_unwrap(r.body, 'receipt')), created: r.created),
    );
  }

  /// Ödeme doğru ama makbuz hatalıysa iptal eder (`issued_in_error`). Ödeme değişmez.
  Future<ReceiptCancelResult> cancelReceipt({
    required String token,
    required int siteCode,
    required int receiptId,
    String? note,
    required String idempotencyKey,
  }) async {
    final text = note?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'receipts/$receiptId/cancel'),
      token: token,
      body: <String, dynamic>{
        'reason_code': 'issued_in_error',
        if (text != null && text.isNotEmpty) 'note': text,
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('İptal makbuzu', () => ReceiptCancelResult.fromJson(r.body));
  }

  /// Yönetici basımını kaydeder; dönen sayı kopya numarasıdır (1 = ASIL).
  Future<int> recordReceiptPrint({
    required String token,
    required int siteCode,
    required int receiptId,
    String? idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'receipts/$receiptId/print'),
      token: token,
      body: <String, dynamic>{'idempotency_key': ?idempotencyKey},
      write: true,
    );
    return _parse('Basım kaydı', () {
      final copy = f4IntOrNull(r.body['copy_number']);
      if (copy == null || copy < 1) throw const FormatException('Kopya numarası okunamadı');
      return copy;
    });
  }

  /// Makbuz numarası + doğrulama kodu denetimi (hiçbir şey yazmaz).
  Future<ReceiptVerifyResult> verifyReceipt({
    required String token,
    required int siteCode,
    required String number,
    required String code,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'receipts/verify'),
      token: token,
      body: <String, dynamic>{'number': number.trim(), 'code': code.trim()},
    );
    return _parse('Doğrulama', () => ReceiptVerifyResult.fromJson(r.body));
  }

  // --- Sakin uçları (yalnız kendi dairesi) -------------------------------------------------------

  /// Sakinin makbuzları (kendi hesabı + salt okunur kiracı hesabı); [accountParty] (İP-1A) yalnız o hesabın görünümü.
  Future<ReceiptPage> listMyReceipts({
    required String token,
    int? apartmentId,
    int limit = 50,
    int? beforeId,
    AccountParty? accountParty,
  }) async {
    final r = await _send(
      'GET',
      '/app/my-finance/receipts',
      token: token,
      query: <String, String>{
        if (apartmentId != null) 'apartment_id': '$apartmentId',
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
        'account_party': ?accountParty?.apiValue,
      },
    );
    return _parse('Makbuzlarım', () => ReceiptPage.fromJson(r.body));
  }

  Future<Receipt> getMyReceipt({required String token, required int receiptId}) async {
    final r = await _send('GET', '/app/my-finance/receipts/$receiptId', token: token);
    return _parse('Makbuz', () => Receipt.fromJson(_unwrap(r.body, 'receipt')));
  }

  /// Sakin ekstresi: verilmezse KENDİ hesabı; [accountParty] (İP-1A) görünümlerinden biri olmalıdır (aksi 404).
  Future<ApartmentStatement> getMyStatement({
    required String token,
    required int apartmentId,
    DateTime? from,
    DateTime? to,
    AccountParty? accountParty,
  }) async {
    final r = await _send(
      'GET',
      '/app/my-finance/apartments/$apartmentId/statement',
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        'account_party': ?accountParty?.apiValue,
      },
      timeout: const Duration(seconds: 30),
    );
    return _parse('Ekstre', () => ApartmentStatement.fromJson(r.body));
  }

  Future<LateFeeExplanation> getMyLateFeeExplanation({required String token, required int entryId}) async {
    final r = await _send('GET', '/app/my-finance/entries/$entryId/late-fee', token: token);
    return _parse('Tazminat açıklaması', () => LateFeeExplanation.fromJson(r.body));
  }

  // --- Gecikme tazminatı -------------------------------------------------------------------------

  Future<LateFeePreview> previewLateFee({
    required String token,
    required int siteCode,
    FinancePeriod? period,
    List<int> excludedApartmentIds = const <int>[],
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'late-fee/preview'),
      token: token,
      body: <String, dynamic>{
        if (period != null) 'period': period.toApi(),
        if (excludedApartmentIds.isNotEmpty) 'excluded_apartment_ids': _sortedIds(excludedApartmentIds),
      },
      timeout: const Duration(seconds: 40),
    );
    return _parse('Önizleme', () => LateFeePreview.fromJson(r.body));
  }

  Future<LateFeePostResult> postLateFee({
    required String token,
    required int siteCode,
    required FinancePeriod period,
    List<int> excludedApartmentIds = const <int>[],
    required int expectedTotalMinor,
    required int expectedApartmentCount,
    required String expectedHash,
    required String idempotencyKey,
    bool recordEmpty = false,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'late-fee/post'),
      token: token,
      body: <String, dynamic>{
        'period': period.toApi(),
        'excluded_apartment_ids': _sortedIds(excludedApartmentIds),
        'expected_total_minor': expectedTotalMinor,
        'expected_apartment_count': expectedApartmentCount,
        'expected_hash': expectedHash,
        // Tazminat doğuran daire yoksa ay "tazminat yok" işaretiyle kaydedilir (satırsız, tutarsız çalıştırma).
        if (recordEmpty) 'record_empty': true,
        'idempotency_key': idempotencyKey,
      },
      write: true,
      timeout: const Duration(seconds: 60),
    );
    return _parse('Tazminat', () => LateFeePostResult.fromJson(r.body));
  }

  Future<LateFeeRunPage> listLateFeeRuns({
    required String token,
    required int siteCode,
    int limit = 24,
    int offset = 0,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'late-fee/runs'),
      token: token,
      query: <String, String>{'limit': '$limit', 'offset': '$offset'},
    );
    return _parse('Çalıştırmalar', () => LateFeeRunPage.fromJson(r.body));
  }

  Future<LateFeeLinePage> listLateFeeRunLines({
    required String token,
    required int siteCode,
    required int runId,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'late-fee/runs/$runId/lines'),
      token: token,
      query: <String, String>{'limit': '$limit', 'offset': '$offset'},
    );
    return _parse('Çalıştırma satırları', () => LateFeeLinePage.fromJson(r.body));
  }

  Future<LateFeeVoidResult> voidLateFeeRun({
    required String token,
    required int siteCode,
    required int runId,
    required String reason,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'late-fee/runs/$runId/void'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim(), 'idempotency_key': idempotencyKey},
      write: true,
      timeout: const Duration(seconds: 60),
    );
    return _parse('Çalıştırma iptali', () => LateFeeVoidResult.fromJson(r.body));
  }

  // --- Kasa / banka ------------------------------------------------------------------------------

  Future<CashOverview> listAccounts({required String token, required int siteCode}) async {
    final r = await _send('GET', _site(siteCode, 'accounts'), token: token);
    return _parse('Hesaplar', () => CashOverview.fromJson(r.body));
  }

  Future<CashAccount> createAccount({
    required String token,
    required int siteCode,
    required String name,
    required CashAccountKind kind,
    String? note,
    required int openingBalanceMinor,
    required DateTime openingDate,
    required String idempotencyKey,
  }) async {
    final text = note?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'accounts'),
      token: token,
      body: <String, dynamic>{
        'name': name.trim(),
        'kind': kind.apiValue,
        if (text != null && text.isNotEmpty) 'note': text,
        'opening_balance_minor': openingBalanceMinor,
        'opening_date': crmDateParam(openingDate),
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('Hesap', () => CashAccount.fromJson(_unwrap(r.body, 'account')));
  }

  Future<CashAccount> updateAccount({
    required String token,
    required int siteCode,
    required int accountId,
    required Map<String, Object?> fields,
  }) async {
    final r = await _send(
      'PATCH',
      _site(siteCode, 'accounts/$accountId'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      write: true,
    );
    return _parse('Hesap', () => CashAccount.fromJson(_unwrap(r.body, 'account')));
  }

  Future<MovementPage> listMovements({
    required String token,
    required int siteCode,
    required int accountId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int? beforeId,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'accounts/$accountId/movements'),
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
    );
    return _parse('Hareketler', () => MovementPage.fromJson(r.body));
  }

  /// Düzeltme hareketi (banka masrafı / faizi, sayım farkı). [amountMinor] İŞARETLİ ve sıfırdan farklı.
  Future<AccountMovement> adjustAccount({
    required String token,
    required int siteCode,
    required int accountId,
    required int amountMinor,
    required DateTime movementDate,
    required AdjustmentReason reason,
    String? note,
    required String idempotencyKey,
  }) async {
    final text = note?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'accounts/$accountId/adjustments'),
      token: token,
      body: <String, dynamic>{
        'amount_minor': amountMinor,
        'movement_date': crmDateParam(movementDate),
        'reason_code': reason.apiValue,
        if (text != null && text.isNotEmpty) 'note': text,
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('Düzeltme', () => AccountMovement.fromJson(_unwrap(r.body, 'movement')));
  }

  Future<TransferPage> listTransfers({
    required String token,
    required int siteCode,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int? beforeId,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'transfers'),
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
    );
    return _parse('Aktarımlar', () => TransferPage.fromJson(r.body));
  }

  Future<TransferWriteResult> createTransfer({
    required String token,
    required int siteCode,
    required int fromAccountId,
    required int toAccountId,
    required int amountMinor,
    required DateTime transferDate,
    String? description,
    required String idempotencyKey,
  }) async {
    final text = description?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'transfers'),
      token: token,
      body: <String, dynamic>{
        'from_account_id': fromAccountId,
        'to_account_id': toAccountId,
        'amount_minor': amountMinor,
        'transfer_date': crmDateParam(transferDate),
        if (text != null && text.isNotEmpty) 'description': text,
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('Aktarım', () => TransferWriteResult.fromJson(r.body));
  }

  Future<void> voidTransfer({
    required String token,
    required int siteCode,
    required int transferId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _send(
      'POST',
      _site(siteCode, 'transfers/$transferId/void'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim(), 'idempotency_key': idempotencyKey},
      write: true,
    );
  }

  /// Hesaba eşlenmemiş tahsilatları toplu eşleme önizlemesi (YAZMAZ). [accountByMethod]: `cash|transfer|cheque`
  /// -> hesap kimliği.
  Future<AssignPreview> previewAssignPayments({
    required String token,
    required int siteCode,
    required Map<String, int> accountByMethod,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'accounts/assign-payments/preview'),
      token: token,
      body: <String, dynamic>{'account_by_method': accountByMethod},
      timeout: const Duration(seconds: 40),
    );
    return _parse('Önizleme', () => AssignPreview.fromJson(r.body));
  }

  Future<AssignResult> commitAssignPayments({
    required String token,
    required int siteCode,
    required Map<String, int> accountByMethod,
    required int expectedCount,
    required int expectedTotalMinor,
    required String expectedHash,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'accounts/assign-payments/commit'),
      token: token,
      body: <String, dynamic>{
        'account_by_method': accountByMethod,
        'expected_count': expectedCount,
        'expected_total_minor': expectedTotalMinor,
        'expected_hash': expectedHash,
        'idempotency_key': idempotencyKey,
      },
      write: true,
      timeout: const Duration(seconds: 60),
    );
    return _parse('Toplu eşleme', () => AssignResult.fromJson(r.body));
  }

  Future<List<Reconciliation>> listReconciliations({
    required String token,
    required int siteCode,
    required int accountId,
  }) async {
    final r = await _send('GET', _site(siteCode, 'accounts/$accountId/reconciliations'), token: token);
    return _parse('Mutabakatlar', () => f4List(r.body['items'], Reconciliation.fromJson));
  }

  Future<ReconciliationResult> reconcileAccount({
    required String token,
    required int siteCode,
    required int accountId,
    required DateTime asOfDate,
    required int statementBalanceMinor,
    required int expectedComputedMinor,
    String? note,
    AdjustmentReason? adjustReason,
    String? adjustNote,
    required String idempotencyKey,
  }) async {
    final text = note?.trim();
    final adjustText = adjustNote?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'accounts/$accountId/reconciliations'),
      token: token,
      body: <String, dynamic>{
        'as_of_date': crmDateParam(asOfDate),
        'statement_balance_minor': statementBalanceMinor,
        'expected_computed_minor': expectedComputedMinor,
        if (text != null && text.isNotEmpty) 'note': text,
        if (adjustReason != null)
          'adjust': <String, dynamic>{
            'reason_code': adjustReason.apiValue,
            if (adjustText != null && adjustText.isNotEmpty) 'note': adjustText,
          },
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('Mutabakat', () => ReconciliationResult.fromJson(r.body));
  }

  // --- Gider -------------------------------------------------------------------------------------

  Future<List<ExpenseCategory>> listExpenseCategories({
    required String token,
    required int siteCode,
    bool? active,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'expense-categories'),
      token: token,
      query: <String, String>{'active': ?active?.toString()},
    );
    return _parse('Kategoriler', () => f4List(r.body['items'], ExpenseCategory.fromJson));
  }

  /// Yeni gider kategorisi. [fund] verilmezse sunucu İşletme Projesi (Aidat) Hesabı'nı yazar.
  Future<ExpenseCategory> createExpenseCategory({
    required String token,
    required int siteCode,
    required String name,
    FinanceFund? fund,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'expense-categories'),
      token: token,
      body: <String, dynamic>{'name': name.trim(), 'fund': ?fund?.apiValue},
      write: true,
    );
    return _parse('Kategori', () => ExpenseCategory.fromJson(_unwrap(r.body, 'category')));
  }

  Future<ExpenseCategory> updateExpenseCategory({
    required String token,
    required int siteCode,
    required int categoryId,
    required Map<String, Object?> fields,
  }) async {
    final r = await _send(
      'PATCH',
      _site(siteCode, 'expense-categories/$categoryId'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      write: true,
    );
    return _parse('Kategori', () => ExpenseCategory.fromJson(_unwrap(r.body, 'category')));
  }

  Future<SupplierPage> listSuppliers({
    required String token,
    required int siteCode,
    String? query,
    bool? active,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'suppliers'),
      token: token,
      query: <String, String>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'active': ?active?.toString(),
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _parse('Tedarikçiler', () => SupplierPage.fromJson(r.body));
  }

  Future<Supplier> createSupplier({
    required String token,
    required int siteCode,
    required String name,
    String? taxId,
    String? phone,
    String? note,
  }) async {
    String? clean(String? v) {
      final t = v?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    final r = await _send(
      'POST',
      _site(siteCode, 'suppliers'),
      token: token,
      body: <String, dynamic>{
        'name': name.trim(),
        'tax_id': ?clean(taxId),
        'phone': ?clean(phone),
        'note': ?clean(note),
      },
      write: true,
    );
    return _parse('Tedarikçi', () => Supplier.fromJson(_unwrap(r.body, 'supplier')));
  }

  Future<Supplier> updateSupplier({
    required String token,
    required int siteCode,
    required int supplierId,
    required Map<String, Object?> fields,
  }) async {
    final r = await _send(
      'PATCH',
      _site(siteCode, 'suppliers/$supplierId'),
      token: token,
      body: Map<String, dynamic>.of(fields),
      write: true,
    );
    return _parse('Tedarikçi', () => Supplier.fromJson(_unwrap(r.body, 'supplier')));
  }

  /// [status]: `active|voided|all`.
  Future<ExpensePage> listExpenses({
    required String token,
    required int siteCode,
    DateTime? from,
    DateTime? to,
    int? categoryId,
    int? supplierId,
    int? accountId,
    String status = 'active',
    String? query,
    int limit = 50,
    int? beforeId,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'expenses'),
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        if (categoryId != null) 'category_id': '$categoryId',
        if (supplierId != null) 'supplier_id': '$supplierId',
        if (accountId != null) 'account_id': '$accountId',
        'status': status,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
    );
    return _parse('Giderler', () => ExpensePage.fromJson(r.body));
  }

  Future<Expense> getExpense({required String token, required int siteCode, required int expenseId}) async {
    final r = await _send('GET', _site(siteCode, 'expenses/$expenseId'), token: token);
    return _parse('Gider', () => Expense.fromJson(_unwrap(r.body, 'expense')));
  }

  Future<ExpenseWriteResult> createExpense({
    required String token,
    required int siteCode,
    required ExpenseInput input,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'expenses'),
      token: token,
      body: <String, dynamic>{...input.toJson(), 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('Gider', () => ExpenseWriteResult.fromJson(r.body));
  }

  Future<Expense> voidExpense({
    required String token,
    required int siteCode,
    required int expenseId,
    required String reason,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'expenses/$expenseId/void'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim(), 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('Gider iptali', () => Expense.fromJson(_unwrap(r.body, 'expense')));
  }

  Future<ExpenseCorrectResult> correctExpense({
    required String token,
    required int siteCode,
    required int expenseId,
    required ExpenseInput input,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'expenses/$expenseId/correct'),
      token: token,
      body: <String, dynamic>{...input.toJson(), 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('Gider düzeltme', () => ExpenseCorrectResult.fromJson(r.body));
  }

  // --- Gider belgesi (iki adımlı yükleme; belge modülü gerektirmez) -------------------------------

  Future<ExpenseUploadTicket> createExpenseDocument({
    required String token,
    required int siteCode,
    required int expenseId,
    required String fileName,
    required int size,
    String? contentType,
    required ExpenseAttachmentKind kind,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'expenses/$expenseId/documents'),
      token: token,
      body: <String, dynamic>{
        'file': <String, dynamic>{'name': fileName, 'size': size, 'content_type': ?contentType},
        'kind': kind.apiValue,
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('Yükleme', () => ExpenseUploadTicket.fromJson(r.body));
  }

  /// Bilet yoluna ham gövdeyi `PUT` eder (A3: `Content-Length` zorunlu). Yol yalnız aynı sunucuya göreli
  /// olabilir; başka bir adrese yükleme reddedilir.
  Future<ExpenseAttachment> uploadExpenseDocument({
    required String token,
    required ExpenseUploadTicket ticket,
    required Uint8List bytes,
  }) async {
    final path = ticket.path;
    if (!path.startsWith('/') || path.startsWith('//') || path.contains('..')) {
      throw ApiException('Yükleme adresi geçersiz. Lütfen tekrar deneyin.');
    }
    final r = await _send(
      'PUT',
      path,
      token: token,
      rawBody: bytes,
      write: true,
      timeout: _uploadTimeout,
    );
    return _parse('Yükleme', () => ExpenseAttachment.fromJson(_unwrap(r.body, 'document')));
  }

  /// Bağlantıyı kaldırır (dosya diskte kalır; KMK m.36 saklama).
  Future<void> removeExpenseDocument({
    required String token,
    required int siteCode,
    required int expenseId,
    required int documentId,
    required String reason,
  }) async {
    await _send(
      'DELETE',
      _site(siteCode, 'expenses/$expenseId/documents/$documentId'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim()},
      write: true,
    );
  }

  Future<Uint8List> downloadExpenseDocument({
    required String token,
    required int siteCode,
    required int expenseId,
    required int documentId,
  }) async {
    final uri = Uri.parse('$_baseUrl${_site(siteCode, 'expenses/$expenseId/documents/$documentId/download')}');
    final request = http.Request('GET', uri)..headers['Authorization'] = 'Bearer $token';
    final response = await _exchange(request, timeout: _uploadTimeout, maxBytes: maxDownloadBytes);
    if (response.statusCode != 200) throw _failure(response);
    return response.bodyBytes;
  }

  // --- Raporlar ----------------------------------------------------------------------------------

  /// Yaşlandırma; [accountParty] (İP-1A) verilirse yalnız o hesabın tutarları (yoksa iki hesabın toplamı + kırılım).
  Future<AgingReport> getAgingReport({
    required String token,
    required int siteCode,
    DateTime? asOf,
    String status = 'all',
    int limit = 200,
    int offset = 0,
    AccountParty? accountParty,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/aging'),
      token: token,
      query: <String, String>{
        if (asOf != null) 'as_of': crmDateParam(asOf),
        'status': status,
        'limit': '$limit',
        'offset': '$offset',
        'account_party': ?accountParty?.apiValue,
      },
      timeout: const Duration(seconds: 40),
    );
    return _parse('Yaşlandırma raporu', () => AgingReport.fromJson(r.body));
  }

  /// İcra dökümü (F8; yalnız yönetici): vadesi geçmiş ödenmemiş kalemler, hesap bazında. [accountKeys] boşsa tüm borçlu hesaplar.
  Future<EnforcementReport> getEnforcementReport({
    required String token,
    required int siteCode,
    DateTime? asOf,
    Iterable<String> accountKeys = const <String>[],
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/enforcement'),
      token: token,
      query: <String, String>{
        if (asOf != null) 'as_of': crmDateParam(asOf),
        if (accountKeys.isNotEmpty) 'accounts': accountKeys.join(','),
      },
      timeout: const Duration(seconds: 40),
    );
    return _parse('İcra dökümü', () => EnforcementReport.fromJson(r.body));
  }

  Future<IncomeExpenseReport> getIncomeExpenseReport({
    required String token,
    required int siteCode,
    required FinancePeriod from,
    required FinancePeriod to,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/income-expense'),
      token: token,
      query: <String, String>{'from': from.toApi(), 'to': to.toApi()},
      timeout: const Duration(seconds: 40),
    );
    return _parse('Gelir-gider raporu', () => IncomeExpenseReport.fromJson(r.body));
  }

  /// Finans > Grafikler: son [months] ay (varsayılan 12) için aylık gelir-gider, aidat tahsilatı, kasa + banka seyri,
  /// gider kategorileri ve geciken borç yaşlandırması. Salt okunur; kurul da okur.
  Future<FinanceCharts> getFinanceCharts({required String token, required int siteCode, int months = 12}) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/charts'),
      token: token,
      query: <String, String>{'months': '$months'},
      timeout: const Duration(seconds: 40),
    );
    return _parse('Grafik', () => FinanceCharts.fromJson(r.body));
  }

  /// Gider analizi ve tahmin (R1). [increaseBp] null ise sunucu kurallar tablosundaki varsayılanı kullanır.
  Future<ExpenseAnalysisReport> getExpenseAnalysisReport({
    required String token,
    required int siteCode,
    required String to,
    required int window,
    int? increaseBp,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/expense-analysis'),
      token: token,
      query: <String, String>{'to': to, 'window': '$window', 'increase_bp': ?increaseBp?.toString()},
      timeout: const Duration(seconds: 40),
    );
    return _parse('Gider analizi', () => ExpenseAnalysisReport.fromJson(r.body));
  }

  /// Gider türü önerisi (kategori + tedarikçi + tarih).
  Future<NatureSuggestion> getNatureSuggestion({
    required String token,
    required int siteCode,
    required int categoryId,
    int? supplierId,
    required DateTime expenseDate,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'expenses/nature-suggestion'),
      token: token,
      query: <String, String>{
        'category_id': '$categoryId',
        'supplier_id': ?supplierId?.toString(),
        'expense_date': crmDateParam(expenseDate),
      },
    );
    return _parse('Gider türü önerisi', () => NatureSuggestion.fromJson(r.body));
  }

  /// Giderin türünü değiştirir (yönetici / süper).
  Future<void> setExpenseNature({
    required String token,
    required int siteCode,
    required int expenseId,
    required ExpenseNature nature,
  }) async {
    await _send(
      'PUT',
      _site(siteCode, 'expenses/$expenseId/nature'),
      token: token,
      body: <String, dynamic>{'nature': nature.apiValue},
      write: true,
    );
  }

  /// Giderin "kontrol edildi (kim, ne zaman)" izini koyar (yalnız yönetici / süper; kurul 403). İz zaten varsa İLK iz döner. İptal edilmiş giderde 409.
  Future<CheckMark?> setExpenseCheck({required String token, required int siteCode, required int expenseId}) async {
    final r = await _send('PUT', _site(siteCode, 'expenses/$expenseId/check'), token: token, write: true);
    return CheckMark.tryParse(r.body);
  }

  /// Giderin kontrol izini kaldırır (iz yoksa sessizce başarılı). Her zaman null (kontrolsüz) döner.
  Future<CheckMark?> clearExpenseCheck({required String token, required int siteCode, required int expenseId}) async {
    await _send('DELETE', _site(siteCode, 'expenses/$expenseId/check'), token: token, write: true);
    return null;
  }

  Future<CashPositionReport> getCashPositionReport({
    required String token,
    required int siteCode,
    DateTime? asOf,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/cash-position'),
      token: token,
      query: <String, String>{if (asOf != null) 'as_of': crmDateParam(asOf)},
      timeout: const Duration(seconds: 40),
    );
    return _parse('Kasa durumu', () => CashPositionReport.fromJson(r.body));
  }

  /// Yönetici daire ekstresi; [accountParty] (İP-1A) verilirse yalnız o hesap (yoksa iki hesap birlikte, eski davranış).
  Future<ApartmentStatement> getApartmentStatement({
    required String token,
    required int siteCode,
    required int apartmentId,
    DateTime? from,
    DateTime? to,
    AccountParty? accountParty,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'apartments/$apartmentId/statement'),
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        'account_party': ?accountParty?.apiValue,
      },
      timeout: const Duration(seconds: 40),
    );
    return _parse('Ekstre', () => ApartmentStatement.fromJson(r.body));
  }

  Future<BoardSummaryReport> getBoardSummary({
    required String token,
    required int siteCode,
    required FinancePeriod from,
    required FinancePeriod to,
    bool includeDebtorList = false,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/board-summary'),
      token: token,
      query: <String, String>{
        'from': from.toApi(),
        'to': to.toApi(),
        'include_debtor_list': includeDebtorList ? 'true' : 'false',
      },
      timeout: const Duration(seconds: 40),
    );
    return _parse('Kurul özeti', () => BoardSummaryReport.fromJson(r.body));
  }

  /// Dönemsel rapor paketi (aylık / 3 aylık / yıllık): iki Hesabın (Aidat / Fon) dönem özeti, gider kalemleri, aylık kırılım ve dönem
  /// sonu borçlu özeti (kişi verisi yok). Ağır rapor: 503 `REPORT_BUSY` gelirse kullanıcı beklemeye yönlendirilir.
  Future<PeriodReport> getPeriodReport({
    required String token,
    required int siteCode,
    required FinancePeriod from,
    required FinancePeriod to,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reports/period'),
      token: token,
      query: <String, String>{'from': from.toApi(), 'to': to.toApi()},
      timeout: const Duration(seconds: 40),
    );
    return _parse('Dönem raporu', () => PeriodReport.fromJson(r.body));
  }

  /// Dışa aktarma zarfı (`finance_*` kind'ları). Yalnız yönetici / süper kullanıcı; kurul 403 alır.
  Future<ExportEnvelope> getExport({
    required String token,
    required int siteCode,
    required String kind,
    Map<String, String> query = const <String, String>{},
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'exports/$kind'),
      token: token,
      query: query,
      timeout: const Duration(seconds: 60),
    );
    return _parse('Dışa aktarma', () => ExportEnvelope.fromJson(r.body));
  }

  // --- Borç hatırlatma ---------------------------------------------------------------------------

  Future<List<ReminderExclusion>> listReminderExclusions({required String token, required int siteCode}) async {
    final r = await _send('GET', _site(siteCode, 'reminders/exclusions'), token: token);
    return _parse('Muaf daireler', () => f4List(r.body['items'], ReminderExclusion.fromJson));
  }

  Future<void> addReminderExclusion({
    required String token,
    required int siteCode,
    required int apartmentId,
    String? reason,
  }) async {
    final text = reason?.trim();
    await _send(
      'PUT',
      _site(siteCode, 'reminders/exclusions/$apartmentId'),
      token: token,
      body: <String, dynamic>{if (text != null && text.isNotEmpty) 'reason': text},
      write: true,
    );
  }

  Future<void> removeReminderExclusion({
    required String token,
    required int siteCode,
    required int apartmentId,
  }) async {
    await _send('DELETE', _site(siteCode, 'reminders/exclusions/$apartmentId'), token: token, write: true);
  }

  Future<ReminderPreview> previewReminders({
    required String token,
    required int siteCode,
    required ReminderTone tone,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'reminders/preview'),
      token: token,
      body: <String, dynamic>{'tone': tone.apiValue},
      timeout: const Duration(seconds: 40),
    );
    return _parse('Önizleme', () => ReminderPreview.fromJson(r.body));
  }

  Future<ReminderSendResult> sendReminders({
    required String token,
    required int siteCode,
    required ReminderTone tone,
    String? note,
    required String expectedHash,
    required int expectedApartmentCount,
    required int expectedPersonCount,
    required String idempotencyKey,
  }) async {
    final text = note?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'reminders/send'),
      token: token,
      body: <String, dynamic>{
        'tone': tone.apiValue,
        if (text != null && text.isNotEmpty) 'note': text,
        'expected_hash': expectedHash,
        'expected_apartment_count': expectedApartmentCount,
        'expected_person_count': expectedPersonCount,
        'idempotency_key': idempotencyKey,
      },
      write: true,
      timeout: const Duration(seconds: 60),
    );
    return _parse(
      'Hatırlatma',
      () => ReminderSendResult(run: ReminderRun.fromJson(_unwrap(r.body, 'run')), created: r.created),
    );
  }

  Future<ReminderRunPage> listReminderRuns({
    required String token,
    required int siteCode,
    int limit = 20,
    int offset = 0,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'reminders/runs'),
      token: token,
      query: <String, String>{'limit': '$limit', 'offset': '$offset'},
    );
    return _parse('Hatırlatma geçmişi', () => ReminderRunPage.fromJson(r.body));
  }

  Future<ReminderRun> getReminderRun({required String token, required int siteCode, required int runId}) async {
    final r = await _send('GET', _site(siteCode, 'reminders/runs/$runId'), token: token);
    return _parse('Hatırlatma', () => ReminderRun.fromJson(_unwrap(r.body, 'run')));
  }

  Future<ReminderRun> cancelReminderRun({
    required String token,
    required int siteCode,
    required int runId,
    String? idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'reminders/runs/$runId/cancel'),
      token: token,
      body: <String, dynamic>{'idempotency_key': ?idempotencyKey},
      write: true,
    );
    return _parse('Hatırlatma iptali', () => ReminderRun.fromJson(_unwrap(r.body, 'run')));
  }

  // --- Tahsilat (hesap seçimli) ------------------------------------------------------------------

  /// Hesap seçimli tahsilat kaydı (`POST payments` + `account_id`). Yanıtta düzenlenen makbuz (`receipt`) ve
  /// hesap hareketi (`movement_id`) gelebilir. Sitede en az bir aktif hesap varsa [accountId] ZORUNLUDUR
  /// (409 `ACCOUNT_REQUIRED`). [fund] verilirse tahsilat YALNIZ o kasanın borçlarına uygulanır; verilmezse otomatik
  /// (en eski vade önce).
  Future<LedgerWriteResult> recordPayment({
    required String token,
    required int siteCode,
    required int apartmentId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    int? accountId,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) async {
    final note = description?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'payments'),
      token: token,
      body: <String, dynamic>{
        'apartment_id': apartmentId,
        'amount_minor': amountMinor,
        'entry_date': crmDateParam(entryDate),
        'method': method.apiValue,
        if (note != null && note.isNotEmpty) 'description': note,
        'account_id': ?accountId,
        'idempotency_key': idempotencyKey,
        // İP-1A: daire hesabı (ev sahibi / kiracı); verilmezse sunucu seçer
        'account_party': ?accountParty?.apiValue,
        // Kasa kısıtı; verilmezse otomatik dağıtım
        'fund': ?fund?.apiValue,
      },
      write: true,
    );
    return _parse('Tahsilat', () => LedgerWriteResult.fromJson(r.body));
  }

  /// Hesap seçimli tahsilat düzeltmesi (`POST entries/:id/correct` + `account_id`). Eski tahsilat hesaba eşlenmemişse
  /// (Toplu Eşle yapılmamış) sunucu hesap ister (409 `ACCOUNT_REQUIRED`); hesap verilmezse eski ödemenin hesabı kullanılır.
  Future<LedgerWriteResult> correctPayment({
    required String token,
    required int siteCode,
    required int entryId,
    required int amountMinor,
    required DateTime entryDate,
    required PaymentMethod method,
    String? description,
    int? accountId,
    required String idempotencyKey,
    AccountParty? accountParty,
    FinanceFund? fund,
  }) async {
    final note = description?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'entries/$entryId/correct'),
      token: token,
      body: <String, dynamic>{
        'amount_minor': amountMinor,
        'entry_date': crmDateParam(entryDate),
        'method': method.apiValue,
        if (note != null && note.isNotEmpty) 'description': note,
        'account_id': ?accountId,
        'idempotency_key': idempotencyKey,
        // İP-1A: verilirse yeni tahsilat bu daire hesabına yazılır (ters kayıt hep eski hesapta)
        'account_party': ?accountParty?.apiValue,
        // Verilmezse ASIL tahsilatın kasa kısıtı korunur
        'fund': ?fund?.apiValue,
      },
      write: true,
    );
    return _parse('Düzeltme', () => LedgerWriteResult.fromJson(r.body));
  }

  /// K3: tahsilatın İşletme / Fon hesabı seçim durumu (`GET payments/fund-choice`). Daire hesabında iki türün de açık borcu varsa
  /// seçim ZORUNLUDUR; tek türde önerilen hesap seçili gelir. [accountParty] verilmezse sunucu tahsilat hesabını kendi kuralıyla
  /// seçer (yanıttaki `account_party`). [amountMinor] verilirse otomatik dağıtımın önerisi (`proposal`, yalnız bilgi) da gelir.
  /// Bu uç yazmaz; yazma yetkisi gerektirir (kurul 403).
  Future<FundChoiceInfo> getFundChoice({
    required String token,
    required int siteCode,
    required int apartmentId,
    AccountParty? accountParty,
    int? amountMinor,
    DateTime? paidOn,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'payments/fund-choice'),
      token: token,
      query: <String, String>{
        'apartment_id': '$apartmentId',
        if (accountParty != null) 'account_party': accountParty.apiValue,
        if (amountMinor != null && amountMinor > 0) 'amount_minor': '$amountMinor',
        if (paidOn != null) 'paid_on': crmDateParam(paidOn),
      },
    );
    final info = FundChoiceInfo.tryParse(r.body);
    if (info == null) throw ApiException('Hesap bilgisi işlenemedi. Lütfen tekrar deneyin.');
    return info;
  }

  // --- İki kasa (İşletme Projesi (Aidat) Hesabı / Yatırım ve Demirbaş (Fon) Hesabı) ----------------

  /// Kasa özeti: iki kasanın açılış / tahsilat / gider / aktarım / düzeltme / bakiye değerleri + avans. [from] / [to] dönem
  /// süzgecidir (yoksa `to` bugündür ve `from` yoktur: tüm hareketler). Sitenin tüm defterini okur (ağır rapor): 503
  /// `REPORT_BUSY` gelirse kullanıcı beklemeye yönlendirilir, otomatik yeniden deneme YAPILMAZ.
  Future<FundSummary> getFundSummary({
    required String token,
    required int siteCode,
    DateTime? from,
    DateTime? to,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'funds'),
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
      },
      timeout: const Duration(seconds: 40),
    );
    return _parse('Kasa özeti', () => FundSummary.fromJson(r.body));
  }

  /// Bir kasanın sayfalı dökümü (yeni -> eski; `limit` en çok 200).
  Future<FundMovementPage> listFundMovements({
    required String token,
    required int siteCode,
    required FinanceFund fund,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'funds/${fund.apiValue}/movements'),
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        'limit': '$limit',
        'offset': '$offset',
      },
      timeout: const Duration(seconds: 40),
    );
    return _parse('Kasa dökümü', () => FundMovementPage.fromJson(r.body, fund));
  }

  Future<FundTransferPage> listFundTransfers({
    required String token,
    required int siteCode,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int? beforeId,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'fund-transfers'),
      token: token,
      query: <String, String>{
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        'limit': '$limit',
        if (beforeId != null) 'before_id': '$beforeId',
      },
    );
    return _parse('Kasalar arası aktarımlar', () => FundTransferPage.fromJson(r.body));
  }

  /// Kasalar arası aktarım (fiziksel hesap hareketi doğurmaz). Aynı [idempotencyKey] + aynı gövde = aynı kayıt (200);
  /// farklı gövde = 409 `IDEMPOTENCY_CONFLICT`.
  Future<FundTransfer> createFundTransfer({
    required String token,
    required int siteCode,
    required FinanceFund fromFund,
    required FinanceFund toFund,
    required int amountMinor,
    required DateTime transferDate,
    String? description,
    required String idempotencyKey,
  }) async {
    final text = description?.trim();
    final r = await _send(
      'POST',
      _site(siteCode, 'fund-transfers'),
      token: token,
      body: <String, dynamic>{
        'from_fund': fromFund.apiValue,
        'to_fund': toFund.apiValue,
        'amount_minor': amountMinor,
        'transfer_date': crmDateParam(transferDate),
        if (text != null && text.isNotEmpty) 'description': text,
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('Aktarım', () => FundTransfer.fromJson(_unwrap(r.body, 'transfer')));
  }

  /// Aktarımı ters çevirir (silinmez: yönleri değişmiş, bugün tarihli ters aktarım yazılır). Gerekçe zorunludur.
  Future<FundTransferReverseResult> reverseFundTransfer({
    required String token,
    required int siteCode,
    required int transferId,
    required String reason,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'fund-transfers/$transferId/reverse'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim(), 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('Ters aktarım', () => FundTransferReverseResult.fromJson(r.body));
  }

  // --- Kiracı borcunun malike devri (K1) ve gecikmede öneri (K17) ---------------------------------
  // Sözleşme: docs/PLATFORM_FINANS.md "Kiracı borcunun malike devri". Devir kendiliğinden olmaz: önizleme + neden + onay + iz + geri alma.

  /// K17: devredilebilir (vadesi gelmiş, ödenmemiş, tazminat olmayan) kiracı borcu olan daireler. Salt okunur; kişi adı yoktur.
  Future<LiabilityCandidatePage> listLiabilityCandidates({required String token, required int siteCode}) async {
    final r = await _send('GET', _site(siteCode, 'liability-transfer/candidates'), token: token);
    return _parse('Devir önerileri', () => LiabilityCandidatePage.fromJson(r.body));
  }

  /// Devir önizlemesi (hiçbir şey yazmaz): kalemler, tazminat istisnası, toplam ve onayda geri gönderilecek özet.
  Future<LiabilityPreview> previewLiabilityTransfer({
    required String token,
    required int siteCode,
    required int apartmentId,
  }) async {
    final r = await _send('GET', _site(siteCode, 'apartments/$apartmentId/liability-transfer/preview'), token: token);
    return _parse('Devir önizlemesi', () => LiabilityPreview.fromJson(r.body));
  }

  /// Kiracı borcunu malike devreder. Aynı [idempotencyKey] + aynı gövde = aynı kayıt (200, `replayed`); farklı gövde = 409
  /// `IDEMPOTENCY_CONFLICT`. Önizlemeden sonra kalemler / tutarlar değiştiyse 409 `LIABILITY_TRANSFER_CHANGED` (hiçbir şey yazılmaz).
  Future<LiabilityTransferResult> createLiabilityTransfer({
    required String token,
    required int siteCode,
    required int apartmentId,
    required int expectedTotalMinor,
    required String expectedHash,
    required String reason,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'apartments/$apartmentId/liability-transfer'),
      token: token,
      body: <String, dynamic>{
        'expected_total_minor': expectedTotalMinor,
        'expected_hash': expectedHash,
        'reason': reason.trim(),
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('Devir', () => LiabilityTransferResult.fromJson(r.body, replayed: !r.created));
  }

  /// Dairenin devirleri ve geri almaları (yeni -> eski, en çok 50); etkin devirde `reversible` sunucudan gelir.
  Future<List<LiabilityTransfer>> listLiabilityTransfers({
    required String token,
    required int siteCode,
    required int apartmentId,
  }) async {
    final r = await _send('GET', _site(siteCode, 'apartments/$apartmentId/liability-transfers'), token: token);
    return _parse('Devir geçmişi', () => f4List(r.body['items'], LiabilityTransfer.fromJson));
  }

  /// Devri geri alır (silinmez: ters kayıtlar eklenir; bakiyeler devirden önceki değerlere döner). Gerekçe zorunludur. Devirden sonra
  /// malik hesabına ödeme girildiyse ya da devrin satırı sonradan başka devirle taşındıysa 409.
  Future<LiabilityTransferResult> reverseLiabilityTransfer({
    required String token,
    required int siteCode,
    required int transferId,
    required String reason,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'liability-transfers/$transferId/reverse'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim(), 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('Devir geri alma', () => LiabilityTransferResult.fromJson(r.body, replayed: !r.created));
  }

  // --- Alacak iadesi (K4) -------------------------------------------------------------------------
  // Sözleşme: docs/PLATFORM_FINANS.md "Alacak iadesi". Fazla ödeme varsayılan olarak alacak kalır; iade istek + YÖNETİCİ ONAYI ile yapılır.

  /// Sakin: kendi hesabı için iade talebi açar (tutar <= Borcum'da görünen alacak). Aynı [idempotencyKey] + aynı gövde = aynı talep
  /// (200, `created` false); farklı gövde = 409 `IDEMPOTENCY_CONFLICT`. Alacak yoksa 409 `NO_CREDIT`, tutar fazlaysa 409 `REFUND_EXCEEDS_CREDIT`.
  Future<RefundRequest> createMyRefundRequest({
    required String token,
    required int apartmentId,
    required int amountMinor,
    String? note,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      '/app/my-finance/refund-requests',
      token: token,
      body: <String, dynamic>{
        'apartment_id': apartmentId,
        'amount_minor': amountMinor,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'idempotency_key': idempotencyKey,
      },
      write: true,
    );
    return _parse('İade talebi', () => RefundRequest.fromJson(_unwrap(r.body, 'refund')));
  }

  /// Sakin: kendi iade talepleri (yeni -> eski, en çok 50); [apartmentId] verilirse yalnız o daire.
  Future<List<RefundRequest>> listMyRefundRequests({required String token, int? apartmentId}) async {
    final r = await _send(
      'GET',
      '/app/my-finance/refund-requests',
      token: token,
      query: <String, String>{if (apartmentId != null) 'apartment_id': '$apartmentId'},
    );
    return _parse('İade talepleri', () => f4List(r.body['items'], RefundRequest.fromJson));
  }

  /// Sakin: bekleyen talebini geri çeker (onaylanmış / karara bağlanmış talep için 409 `REFUND_NOT_PENDING`).
  Future<RefundRequest> cancelMyRefundRequest({required String token, required int refundId}) async {
    final r = await _send('POST', '/app/my-finance/refund-requests/$refundId/cancel', token: token, write: true);
    return _parse('İade talebi', () => RefundRequest.fromJson(_unwrap(r.body, 'refund')));
  }

  /// Yönetici / kurul: iade talepleri. [status]: `requested` (varsayılan) | `approved` | `rejected` | `cancelled` | `reversed` | `all`.
  /// Yanıttaki bekleyen özeti süzgeçten bağımsızdır.
  Future<RefundPage> listRefunds({
    required String token,
    required int siteCode,
    String status = 'requested',
    int? apartmentId,
    int? beforeId,
    int limit = 50,
  }) async {
    final r = await _send(
      'GET',
      _site(siteCode, 'refunds'),
      token: token,
      query: <String, String>{
        'status': status,
        if (apartmentId != null) 'apartment_id': '$apartmentId',
        if (beforeId != null) 'before_id': '$beforeId',
        'limit': '$limit',
      },
    );
    return _parse('İade talepleri', () => RefundPage.fromJson(r.body));
  }

  /// Yönetici: talebi onaylar. TEK işlemde Hesaptan çıkış kaydı + defter + iade makbuzu yazılır; tutar DEĞİŞTİRİLEMEZ. Nakit Hesapta bakiye
  /// yetmezse 409 `CASH_INSUFFICIENT`, ay kapalıysa 409 `PERIOD_CLOSED`. Aynı [idempotencyKey] = aynı karar (200).
  Future<RefundRequest> approveRefund({
    required String token,
    required int siteCode,
    required int refundId,
    required int payAccountId,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'refunds/$refundId/approve'),
      token: token,
      body: <String, dynamic>{'pay_account_id': payAccountId, 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('İade onayı', () => RefundRequest.fromJson(_unwrap(r.body, 'refund')));
  }

  /// Yönetici: talebi gerekçeyle reddeder (gerekçe zorunlu, sakine görünür).
  Future<RefundRequest> rejectRefund({
    required String token,
    required int siteCode,
    required int refundId,
    required String reason,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'refunds/$refundId/reject'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim(), 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('İade reddi', () => RefundRequest.fromJson(_unwrap(r.body, 'refund')));
  }

  /// Yönetici: ONAYLI iadeyi geri alır (silinmez: ters kayıt + Hesapta ayna hareket; makbuz iptal sayılır; alacak yeniden oluşur). Gerekçe zorunlu.
  Future<RefundRequest> reverseRefund({
    required String token,
    required int siteCode,
    required int refundId,
    required String reason,
    required String idempotencyKey,
  }) async {
    final r = await _send(
      'POST',
      _site(siteCode, 'refunds/$refundId/reverse'),
      token: token,
      body: <String, dynamic>{'reason': reason.trim(), 'idempotency_key': idempotencyKey},
      write: true,
    );
    return _parse('İade geri alma', () => RefundRequest.fromJson(_unwrap(r.body, 'refund')));
  }

  // --- Taşıma katmanı ----------------------------------------------------------------------------

  static List<int> _sortedIds(List<int> ids) => (<int>{...ids}.toList()..sort());

  /// `{ "receipt": {...} }` gibi sarmalı açar; yoksa gövdenin kendisi.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> body, String key) {
    final inner = body[key];
    return inner is Map ? Map<String, dynamic>.from(inner) : body;
  }

  T _parse<T>(String what, T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw ApiException('$what bilgisi işlenemedi. Lütfen tekrar deneyin.');
    } on TypeError {
      throw ApiException('$what bilgisi işlenemedi. Lütfen tekrar deneyin.');
    }
  }

  Future<Finance4bResponse> _send(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Uint8List? rawBody,
    Map<String, String>? query,
    bool write = false,
    Duration? timeout,
  }) async {
    var uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (rawBody != null) {
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = rawBody;
    } else if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final response = await _exchange(request, timeout: timeout ?? (write ? _writeTimeout : _readTimeout), write: write);
    final status = response.statusCode;
    if (status < 200 || status >= 300) throw _failure(response);
    final parsed = _tryObject(response.bodyBytes);
    if (parsed == null && response.bodyBytes.isNotEmpty) {
      throw ApiException('Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.', statusCode: status);
    }
    if (parsed == null && !write) {
      // Okuma yanıtı boş olamaz: boş gövde "veri yok" diye yorumlanmaz.
      throw ApiException('Sunucu yanıtı okunamadı. Lütfen tekrar deneyin.', statusCode: status);
    }
    return Finance4bResponse(status, parsed ?? const <String, dynamic>{});
  }

  Future<http.Response> _exchange(
    http.Request request, {
    required Duration timeout,
    bool write = false,
    int? maxBytes,
  }) async {
    var timedOut = false;
    try {
      return await _stream(request, maxBytes: maxBytes, isCancelled: () => timedOut).timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          throw TimeoutException(null, timeout);
        },
      );
    } on TimeoutException {
      throw ApiException(
        write
            ? 'Sunucu zamanında yanıt vermedi. İşlem tamamlanmış olabilir; listeyi yenileyip kontrol edin.'
            : 'Sunucu yanıt vermedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
    } on ApiException {
      rethrow;
    } on http.ClientException {
      throw ApiException(_transportMessage);
    } on Exception catch (_) {
      throw ApiException(_transportMessage);
    }
  }

  static const String _transportMessage =
      'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  Future<http.Response> _stream(
    http.Request request, {
    int? maxBytes,
    required bool Function() isCancelled,
  }) async {
    final streamed = await _client.send(request);
    final declared = streamed.contentLength;
    if (maxBytes != null && declared != null && declared > maxBytes) {
      unawaited(streamed.stream.listen((_) {}).cancel());
      throw ApiException('Dosya çok büyük.', statusCode: 413);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      if (isCancelled()) break;
      builder.add(chunk);
      if (maxBytes != null && builder.length > maxBytes) {
        throw ApiException('Dosya çok büyük.', statusCode: 413);
      }
    }
    return http.Response.bytes(
      builder.takeBytes(),
      streamed.statusCode,
      headers: streamed.headers,
      request: request,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  // --- Hata çevirisi -----------------------------------------------------------------------------

  ApiException _failure(http.Response response) {
    final status = response.statusCode;
    final payload = _tryObject(response.bodyBytes);
    final retryAfter = _retryAfterSeconds(response, payload);

    if (payload == null) {
      final empty = response.bodyBytes.isEmpty;
      if ((status == 401 || status == 403) && !empty) {
        return ApiException(
          'Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy) kontrol edip tekrar deneyin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
      if (status >= 500) {
        return ApiException(
          'Sunucu şu anda yanıt veremiyor ($status). Lütfen biraz sonra tekrar deneyin.',
          statusCode: status,
        );
      }
      if (status == 429) {
        return ApiException(
          _withRetryHint('Çok fazla istek gönderildi.', retryAfter),
          statusCode: status,
          retryAfterSeconds: retryAfter,
        );
      }
      if (!empty) {
        return ApiException(
          'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
          statusCode: status,
          fromIntermediary: true,
        );
      }
    }

    final body = payload ?? const <String, dynamic>{};
    final rawCode = body['code'];
    final code = rawCode is String && rawCode.trim().isNotEmpty ? rawCode.trim() : null;
    final rawError = body['error'];
    final serverText = rawError is String && rawError.trim().isNotEmpty
        ? AuthApi.sanitizeServerMessage(rawError.trim())
        : null;

    if (status == 401) {
      return SessionExpiredException(
        code == 'TOKEN_REVOKED'
            ? 'Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.'
            : (code == 'ACCOUNT_DELETED'
                  ? 'Bu hesap silinmiş.'
                  : 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.'),
        code,
      );
    }

    final mapped = finance4bErrorMessage(code, retryAfterSeconds: retryAfter, payload: body);
    final generic = AuthApi.genericMessageForStatus(status, code: code);
    final fallback = mapped == null && serverText == null && generic == null;
    // Aynı kodun birden çok anlamı olanlarda (ACCOUNT_INACTIVE: tek hesap pasif / TÜM hesaplar pasif) sunucunun kendi
    // Türkçe iletisi önceliklidir.
    final serverWins = serverText != null && _serverTextWinsFor.contains(code);
    var message = serverWins ? serverText : (mapped ?? serverText ?? generic ?? 'İşlem başarısız ($status)');
    if (status == 429 && mapped == null) message = _withRetryHint(message, retryAfter);
    if (status >= 500) {
      final errorId = body['errorId'] ?? body['error_id'];
      if (errorId is String && errorId.isNotEmpty) message = '$message (Hata kodu: $errorId)';
    }
    return ApiException(
      message,
      statusCode: status,
      code: code,
      retryAfterSeconds: retryAfter,
      payload: body,
      genericFallback: fallback,
    );
  }

  static const Set<String> _serverTextWinsFor = <String>{'ACCOUNT_INACTIVE'};

  static String _withRetryHint(String base, int? retryAfter) {
    if (retryAfter == null) return base;
    if (base.toLowerCase().contains('sonra')) return base;
    final trimmed = base.endsWith('.') ? base : '$base.';
    return '$trimmed ${AuthApi.formatWait(retryAfter)} sonra tekrar deneyin.';
  }

  static int? _retryAfterSeconds(http.Response response, Map<String, dynamic>? payload) {
    final body = payload?['retry_after_seconds'] ?? payload?['retryAfterSeconds'];
    if (body is num && body.isFinite && body > 0) return body.ceil();
    if (body is String) {
      final parsed = int.tryParse(body.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    final header = response.headers['retry-after'];
    if (header != null) {
      final parsed = int.tryParse(header.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  static Map<String, dynamic>? _tryObject(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return raw is Map<String, dynamic> ? raw : (raw is Map ? Map<String, dynamic>.from(raw) : null);
    } on FormatException {
      return null;
    }
  }
}

/// Oturum belirtecini [AuthService]'ten alan, oturum hatalarını merkezi çıkışa bağlayan katman. Ekranlar
/// bunu kullanır; testlerde sahte [Finance4bApi] ile kurulur ([register]).
class Finance4bService {
  Finance4bService({
    required this.authService,
    Finance4bApi? api,
    String? Function()? tokenProvider,
  }) : api = api ?? Finance4bApi(baseUrl: authService.api.baseUrl),
       _tokenProvider = tokenProvider ?? (() => authService.session?.token);

  final AuthService authService;
  final Finance4bApi api;
  final String? Function() _tokenProvider;

  static final Expando<Finance4bService> _registered = Expando<Finance4bService>('finance4b');

  /// [authService] için ortak servis: kayıtlı (test) varsa o, yoksa tembel kurulan gerçek servis.
  static Finance4bService of(AuthService authService) =>
      _registered[authService] ??= Finance4bService(authService: authService);

  /// Test düzeneği: [authService] için sahte servis kaydeder.
  @visibleForTesting
  static void register(AuthService authService, Finance4bService service) {
    _registered[authService] = service;
  }

  /// Oturumun belirteciyle [call]'ı çalıştırır. 401 alınırsa oturum doğrulaması başlatılır (yerel çıkış
  /// burada yapılmaz; AuthService `/me` ile karar verir).
  Future<T> run<T>(Future<T> Function(Finance4bApi api, String token) call) async {
    final token = _tokenProvider();
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    try {
      return await call(api, token);
    } on ApiException catch (e) {
      if (e.invalidatesSession && authService.session?.token == token) {
        unawaited(authService.refreshSession(force: true));
      }
      rethrow;
    }
  }
}

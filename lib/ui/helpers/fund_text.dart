import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/finance_funds.dart';
import 'package:site_kapi_kontrol/ui/helpers/money.dart';

/// İki kasa (İşletme Projesi (Aidat) Hesabı / Yatırım ve Demirbaş (Fon) Hesabı) metin ve simge yardımcıları.
/// Widget'lara bağımlı değildir (ortak parçalar ve satır karoları aynı yardımcıları döngüsüz kullansın diye ayrı durur).

/// Kasa simgesi (dekoratif; anlam metindedir).
IconData fundIcon(FinanceFund fund) =>
    fund == FinanceFund.operating ? Icons.home_work_rounded : Icons.savings_rounded;

/// Gider formunda / kategori yönetiminde kasa seçeneğinin açıklaması: bu kasadan hangi giderler çıkar.
String expenseFundNote(FinanceFund fund) => fund == FinanceFund.operating
    ? 'aidat ile karşılanan işletme giderleri'
    : 'yatırım, demirbaş ve büyük onarım giderleri';

/// Tahsilatın kasalara dağılımı: "Aidat Hesabı 1.500,00 ₺, Fon Hesabı 500,00 ₺, avans 0,00 ₺".
String fundSplitText(FundSplit split) =>
    '${FinanceFund.operating.shortLabel} ${formatMinor(split.operatingMinor)}, '
    '${FinanceFund.capital.shortLabel} ${formatMinor(split.capitalMinor)}, '
    'avans ${formatMinor(split.advanceMinor)}';

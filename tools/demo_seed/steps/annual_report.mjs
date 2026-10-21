// Faaliyet Raporu (modul: annual_report): 2023, 2024, 2025 yillik raporlar (sistem verisi kayitlardan her okumada hesaplanir;
// burada yonetici duzenleme metinleri ve buyume orani kaydedilir) + 2026 taslak. Servis: saveDraft.

import { noonIstanbul } from '../lib/util.mjs';

const TEXTS = {
  2023: {
    general: 'Sitemiz 2023 yılında düzenli işleyen bir yönetim yılı geçirmiştir. Sakin sayımızda önemli bir değişiklik olmamış, ortak alanlar planlı bakımlarla korunmuştur.',
    finance: 'Yıl boyunca aidat tahsilatı hedefin üzerinde seyretmiş, giderler gelirlerle dengeli tutulmuştur. Temmuz ve kasım aylarında yaşanan asansör ve hidrofor arızaları yedek akçeden karşılanmıştır.',
    collections: 'Aidat tahsilat oranı yıl genelinde yüzde 93 civarında gerçekleşmiştir. Birkaç dairenin gecikmeli ödemeleri düzenli takip edilmiştir.',
    works: 'Sakinlerden gelen arıza ve şikayet talepleri kısa sürede sonuçlandırılmıştır.',
    maintenance: 'Asansör, kazan ve hidrofor gibi sistemlerin planlı bakımları yetkili firmalarla yapılmıştır.',
    forecast: 'Enflasyon etkisiyle 2024 yılında giderlerde belirgin artış beklenmektedir; aidatın buna göre güncellenmesi önerilir.',
  },
  2024: {
    general: '2024 yılında asansör modernizasyonu başta olmak üzere bina ortak sistemlerinin yenilenmesine odaklanılmıştır.',
    finance: 'Asansör modernizasyonu için mal sahiplerinden katkı payı toplanmış, çatı yalıtımı ve kazan brülörü onarımı gibi beklenmedik giderler yönetilmiştir. Yıl sonunda gelir ve gider dengeli kapanmıştır.',
    collections: 'Katkı payı tahsilatı iki ay içinde büyük ölçüde tamamlanmıştır. Gecikmeli borçlular için ödeme planı görüşmeleri yapılmıştır.',
    works: 'Yıl içinde toplanan taleplerin çoğu ilk haftada çözülmüştür.',
    maintenance: 'Yeni asansör kumanda sistemiyle arıza sayısı belirgin biçimde azalmıştır.',
    forecast: '2025 için dış cephe boya ve onarım çalışması planlanmıştır; bütçe buna göre hazırlanmalıdır.',
  },
  2025: {
    general: 'Dış cephe boya ve onarım işi 2025 yılının en büyük çalışması olmuştur. İş, ihale usulüyle ve genel kurul kararına uygun yürütülmüştür.',
    finance: 'Dış cephe işi için toplanan katkı payı hakedişlerin ödenmesinde kullanılmıştır. Rutin giderler bütçeyle uyumlu kalmıştır.',
    collections: 'Yıl sonu itibarıyla açık borçlu daire sayısı azalmış, uzun süredir ödeme yapmayan dairelerle yazılı görüşme yapılmıştır.',
    works: 'Dış cephe çalışması süresince sakinlerden gelen talepler öncelikli olarak ele alınmıştır.',
    maintenance: 'Yangın algılama ve otopark bariyeri sistemleri gözden geçirilmiş, gerekli onarımlar yapılmıştır.',
    forecast: '2026 yılı için aidat güncellemesi ve yedek akçe oluşturulması önerilmektedir.',
  },
  2026: {
    general: '2026 yılı devam etmektedir. Bu bölüm yıl sonunda tamamlanacak taslak olarak bırakılmıştır.',
    finance: 'Yılın ilk on ayında gelir ve gider dengesi korunmuştur. Mart ayında yangın algılama sistemi revizyonu ve ağustosta su deposu onarımı yapılmıştır.',
  },
};
const GROWTH = { 2023: 4500, 2024: 3500, 2025: 3000, 2026: 2800 };

export async function seedAnnualReport(ctx) {
  const { site, manager, TODAY, log } = ctx;
  const svc = await ctx.importServer('src/modules/annual_report_service.js');
  const actor = { user_code: manager.user_code, full_name: manager.full_name, role: manager.role };
  const saved = [];
  for (const year of [2023, 2024, 2025, 2026]) {
    if (`${year}-01-01` > TODAY) continue;
    const now = year < Number(TODAY.slice(0, 4)) ? noonIstanbul(`${year + 1}-01-25`) : noonIstanbul(TODAY);
    await svc.saveDraft({ siteCode: site.code, rawYear: String(year), actor, now, body: { edits: TEXTS[year], growth_bp: GROWTH[year] } });
    saved.push(year);
  }
  log(`Faaliyet raporu: ${saved.join(', ')}`);
  return { saved };
}

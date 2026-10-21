// Belgeler (modul: documents): 21 gercek (kucuk, gecerli, Turkce metinli) PDF; belge deposuna uygulamanin kendi servisiyle yuklenir
// (dosya + sha256 + kota tutarli). Diskteki dosyalar registry'ye '@file' olarak yazilir; cleanup siler.
// NOT: depo kok dizini DOCUMENTS_DIR / DOCUMENTS_STORAGE_DIR ortam degiskeninden gelir (varsayilan ~/kapi-documents).

import fs from 'node:fs';
import crypto from 'node:crypto';
import { buildPdf } from '../lib/pdf_min.mjs';
import { trackFile } from '../lib/registry.mjs';
import { fmtTl } from '../lib/util.mjs';

const DOCS = [
  ['regulation', 'residents', 'Site Yönetim Planı', '2023-01-12', 'Yönetim planı; sitenin yönetim şeklini, kat maliklerinin hak ve yükümlülüklerini, ortak giderlerin paylaşımını ve genel kurulun çalışma usulünü düzenler.'],
  ['regulation', 'residents', 'Kat Mülkiyeti Kanunu Özeti', '2023-01-12', 'Bu özet bilgilendirme amaçlıdır; kat maliklerinin temel hak ve görevlerini, ortak gider paylaşımını ve genel kurul nisaplarını kısaca anlatır.'],
  ['regulation', 'residents', 'Site Kuralları ve Ortak Alan Kullanımı', '2023-02-03', 'Sessizlik saatleri 22:00-08:00 arasıdır. Misafir araçları otoparkta en fazla 24 saat kalabilir. Bahçe, toplantı salonu ve havuz kullanımı yönetimin belirlediği saatlerde yapılır.'],
  ['minutes', 'residents', 'Olağan Genel Kurul Tutanağı 2023', '2023-03-18', '2023 yılı olağan genel kurulu yapılmış, faaliyet raporu ve işletme projesi oy çokluğuyla kabul edilmiştir. Aylık aidat 1.500 TL olarak belirlenmiştir.'],
  ['minutes', 'residents', 'Olağan Genel Kurul Tutanağı 2024', '2024-03-16', '2024 yılı olağan genel kurulu yapılmış, aidat 2.400 TL olarak belirlenmiş ve asansör modernizasyonu için katkı payı kararı alınmıştır.'],
  ['minutes', 'residents', 'Olağan Genel Kurul Tutanağı 2025', '2025-03-15', '2025 yılı olağan genel kurulu yapılmış, aidat 3.500 TL olarak belirlenmiş ve dış cephe boya ve onarım işi karara bağlanmıştır.'],
  ['minutes', 'board', 'Yönetim Kurulu Toplantı Tutanağı - Haziran 2025', '2025-06-14', 'Dış cephe boya işinin ilk hakedişi görüşülmüş, firma ile imzalanan sözleşmeye uygun ödemenin yapılmasına karar verilmiştir.'],
  ['minutes', 'board', 'Yönetim Kurulu Toplantı Tutanağı - Eylül 2025', '2025-09-20', 'Kış hazırlıkları, kazan bakımı ve yedek akçe oluşturulması konuları görüşülmüştür.'],
  ['contract', 'managers', 'Bina Yangın Sigortası Poliçesi 2026', '2026-03-01', 'Bina yangın sigortası poliçesi: poliçe süresi 1 yıl, teminat bina yeniden inşa bedelidir. Prim yıllık peşin ödenmiştir. (Sahte demo poliçe)'],
  ['contract', 'managers', 'DASK Zorunlu Deprem Sigortası Poliçesi 2026', '2026-03-01', 'Zorunlu deprem sigortası poliçesi: bina için bir yıl süreyle geçerlidir. (Sahte demo poliçe)'],
  ['other', 'managers', 'Asansör Periyodik Kontrol Raporu 2025', '2025-05-22', 'Asansörlerin yıllık periyodik kontrolü yapılmış, uygunluk etiketi yapıştırılmıştır. Küçük bir ayar notu bakım firmasına iletilmiştir. (Sahte demo rapor)'],
  ['contract', 'managers', 'Asansör Bakım Sözleşmesi', '2024-01-02', 'Aylık asansör bakımı sözleşmesi: ayda bir bakım, 7/24 arıza çağrısı, parça bedelleri ayrıca faturalanır. Sözleşme 2027-06-30 tarihine kadar geçerlidir.'],
  ['contract', 'board', 'Güvenlik ve Danışma Hizmeti Sözleşmesi', '2025-04-01', 'Güvenlik ve danışma hizmeti sözleşmesi: hafta içi ve hafta sonu gündüz görevli, vardiya listesi yönetime bildirilir. Sözleşme 2027-03-31 tarihine kadar geçerlidir.'],
  ['contract', 'board', 'Temizlik Hizmeti Sözleşmesi', '2025-09-01', 'Merdiven, asansör ve ortak alan temizliği haftada beş gün yapılır. Malzeme bedeli yükleniciye aittir. Sözleşme 2027-08-31 tarihine kadar geçerlidir.'],
  ['other', 'board', 'Mali Tablolar 2023', '2024-01-31', '2023 yılı gelir-gider özeti.'],
  ['other', 'board', 'Mali Tablolar 2024', '2025-01-31', '2024 yılı gelir-gider özeti.'],
  ['other', 'board', 'Mali Tablolar 2025', '2026-01-30', '2025 yılı gelir-gider özeti.'],
  ['other', 'managers', 'Kazan Dairesi Bakım Raporu 2025', '2025-10-15', 'Kazan ve baca yıllık bakımı yapılmış, brülör ayarı kontrol edilmiş, emisyon ölçümü uygun bulunmuştur. (Sahte demo rapor)'],
  ['notice', 'residents', 'Kış Dönemi Isıtma Kuralları', '2025-10-10', 'Merkezi ısıtma 15 Ekim - 15 Nisan arasında çalıştırılır. Petek havalandırması yapılmalı, pencereler açık bırakılmamalıdır.'],
  ['notice', 'residents', 'Acil Durum ve Tahliye Planı', '2024-06-05', 'Yangın veya deprem durumunda sakinler merdiven yolunu kullanarak bahçedeki toplanma alanına gitmelidir. Asansör kullanılmamalıdır. Acil numaralar: 112, 110, 155.'],
  ['regulation', 'residents', 'Evcil Hayvan ve Bahçe Kullanım Esasları', '2024-05-10', 'Evcil hayvanlar bahçede tasmalı gezdirilir. Hayvan atıkları sahibi tarafından toplanır. Çocuk oyun alanına hayvan sokulmaz.'],
];

export async function seedDocuments(ctx) {
  const { q, site, manager, finance, batchId, log } = ctx;
  const siteCode = site.code;
  const actor = { user_code: manager.user_code, full_name: manager.full_name, role: manager.role };
  const common = await ctx.importServer('src/modules/document_common.js');
  const service = await ctx.importServer('src/modules/document_service.js');
  const storage = await ctx.importServer('src/modules/document_storage.js');
  const limits = common.documentLimits(process.env);
  const root = storage.resolveStorageRoot().dir;
  await fs.promises.mkdir(root, { recursive: true });
  let created = 0;
  let bytes = 0;
  const fileList = [];
  for (const [i, [category, audience, title, date, text]] of DOCS.entries()) {
    const year = title.match(/20\d\d/)?.[0];
    const blocks = [
      { text: title, size: 18, bold: true },
      { text: site.name, size: 12, gapBefore: 4 },
      { text: `Düzenleme tarihi: ${date.split('-').reverse().join('.')}`, size: 10, gapBefore: 2 },
      { text: text, size: 11, gapBefore: 18 },
    ];
    if (title.startsWith('Mali Tablolar') && finance && year) {
      const collected = finance.collectionsByYear[year] ?? 0;
      const spent = Math.round((finance.rawByYear[year] ?? 0) * (finance.scaleByYear[year] ?? 1));
      blocks.push({ text: `Toplam tahsilat: ${fmtTl(collected)}`, size: 11, gapBefore: 12 });
      blocks.push({ text: `Toplam gider (yaklaşık): ${fmtTl(spent)}`, size: 11, gapBefore: 2 });
      blocks.push({ text: 'Ayrıntılı kalemler Aidat ve Finans modülündeki raporlardadır.', size: 10, gapBefore: 8 });
    }
    blocks.push({ text: 'Bu belge SAHTE demo veridir; gerçek bir kurum, kişi veya sözleşmeyi temsil etmez.', size: 9, gapBefore: 28 });
    const buffer = buildPdf({ blocks, footer: `${site.name} - demo belge` });
    const name = `${title.replace(/[^\p{L}\p{N} -]/gu, '').replace(/\s+/g, '_')}.pdf`;
    const idem = `${batchId}:doc:${i + 1}`.slice(0, 64);
    const res = await service.createDocument({
      siteCode, actor, limits,
      body: { title, description: text.slice(0, 200), category, audience, target: { type: 'site' }, file: { name, size: buffer.length, content_type: 'application/pdf' }, note: null, idempotency_key: idem },
    });
    const documentId = Number(res.document.id);
    const versionRow = (await q(`SELECT storage_key FROM document_versions WHERE document_id = $1 AND version_no = 1`, [documentId])).rows[0];
    await storage.ensureSiteDir(root, siteCode);
    const filePath = storage.pathForKey(root, versionRow.storage_key);
    await fs.promises.writeFile(filePath, buffer);
    await trackFile({ query: q }, batchId, filePath);
    fileList.push(filePath);
    const target = await service.findUploadTarget({ siteCode, rawId: documentId, rawVersionNo: 1, actor, limits });
    const sha256 = crypto.createHash('sha256').update(buffer).digest('hex');
    await service.completeUpload({ siteCode, target, actor, size: buffer.length, sha256, kind: target.kind, limits });
    await q(`UPDATE documents SET created_at = $2::timestamptz, updated_at = $2::timestamptz WHERE id = $1`, [documentId, `${date}T11:00:00+03:00`]);
    await q(`UPDATE document_versions SET created_at = $2::timestamptz, completed_at = $2::timestamptz WHERE document_id = $1`, [documentId, `${date}T11:00:00+03:00`]);
    created += 1;
    bytes += buffer.length;
  }
  log(`Belgeler: ${created} PDF (${(bytes / 1024).toFixed(1)} KB) -> ${root}`);
  return { created, bytes, root, fileCount: fileList.length };
}

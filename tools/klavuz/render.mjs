// Belge üretimi (saf fonksiyonlar; dosya sistemi yok). build.mjs tarafından kullanılır.
//
// Çıktı (renderAll -> Map<yol, içerik>):
//   docs/ARIZA_KLAVUZU.md                  ana sayfa: nasıl kullanılır, doğrulama durumu, bölümler
//   docs/ARIZA_KLAVUZU_INDEKS.md           belirti -> İLK BAKILACAK dosya:satır (giriş başına tek satır)
//   docs/ariza-klavuzu/<alan>.md           alan başına girişler (nedenler, adımlar, günlük, komut, test)
//   docs/ARIZA_KLAVUZU_EKLER.md            otomatik ekler: uç noktalar, uygulama çağrıları, ortam, tablolar, kapsam
//   docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md   mesaj -> kaynak dizini
// Belgeler deterministiktir (zaman damgası yok).

export const DOC_LANDING = 'docs/ARIZA_KLAVUZU.md';
export const DOC_INDEX = 'docs/ARIZA_KLAVUZU_INDEKS.md';
export const DOC_APPENDICES = 'docs/ARIZA_KLAVUZU_EKLER.md';
export const DOC_MESSAGES = 'docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md';
export const AREA_DIR = 'docs/ariza-klavuzu';

const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
const htmlEsc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\|/g, '&#124;');
const clip = (s, n) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);
const cleanLog = (l) => String(l).replace(/^~/, '');

/** `base`: belgenin bulunduğu klasörden depo köküne yol ('../' docs/, '../../' docs/ariza-klavuzu/). */
export function linkOf(file, line, endLine = null, base = '../') {
  const label = endLine ? `${file}:${line}-${endLine}` : `${file}:${line}`;
  const anchor = endLine ? `#L${line}-L${endLine}` : `#L${line}`;
  return `[${label}](${base}${file}${anchor})`;
}

/** Giriş bağlantısı. from: 'docs' (ana/indeks/ekler) ya da 'area' (docs/ariza-klavuzu içi). */
function entryHref(id, idToArea, from, fromArea = null) {
  const area = idToArea.get(id);
  if (from === 'area') return area === fromArea ? `#${id}` : `${area}.md#${id}`;
  return `ariza-klavuzu/${area}.md#${id}`;
}

function statusBanner(areaKey, status) {
  if (status.verified.includes(areaKey)) {
    return '> ✓ **Doğrulandı:** bu bölümün girişleri, yazarından bağımsız bir ajan tarafından koda karşı çürütülmeye çalışıldı.';
  }
  return (
    '> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız ' +
    'çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). ' +
    'Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.'
  );
}

export function renderEntry(entry, ctx) {
  const base = '../../';
  const out = [];
  out.push(`<a id="${entry.id}"></a>`);
  out.push(`### ${entry.id} · ${entry.symptom}`);
  out.push('');
  out.push('| Dosya:satır | Satırdaki kod | Ne işe yarar |');
  out.push('| --- | --- | --- |');
  for (const ref of entry.refs) {
    out.push(
      `| ${linkOf(ref.file, ref.line, ref.endLine, base)} | <code>${htmlEsc(clip(ref.text, 90))}</code> | ${esc(ref.note)} |`,
    );
  }
  out.push('');
  const list = (title, items, code = false) => {
    if (!items?.length) return;
    out.push(`**${title}**`);
    for (const item of items) out.push(code ? `- \`${cleanLog(item)}\`` : `- ${item}`);
    out.push('');
  };
  list('Olası nedenler', entry.causes);
  list('Adım adım kontrol', entry.checks);
  list('Günlükte aranacak ifadeler', entry.logs, true);
  if (entry.commands?.length) {
    out.push('**Komutlar**');
    out.push('```bash');
    for (const c of entry.commands) out.push(c);
    out.push('```');
    out.push('');
  }
  if (entry.tests?.length) {
    out.push(`**İlgili testler:** ${entry.tests.map((t) => `[${t}](${base}${t})`).join(', ')}`);
    out.push('');
  }
  if (entry.related?.length) {
    const links = entry.related.map((r) => `[${r}](${entryHref(r, ctx.idToArea, 'area', entry.area)})`);
    out.push(`**Bkz.:** ${links.join(', ')}`);
    out.push('');
  }
  return out;
}

export function renderAreaDoc(area, ctx) {
  const base = '../../';
  const out = [];
  out.push(`# ${area.title}`);
  out.push('');
  out.push('[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)');
  out.push('');
  out.push(statusBanner(area.key, ctx.status));
  out.push('');
  out.push(area.intro);
  out.push('');
  if (area.files.length) {
    out.push('## Dosya haritası');
    out.push('');
    out.push('| Dosya | Rol |');
    out.push('| --- | --- |');
    for (const f of area.files) out.push(`| [${f.file}](${base}${f.file}) | ${esc(f.note)} |`);
    out.push('');
  }
  out.push(`## Bu bölümdeki girişler (${area.entries.length})`);
  out.push('');
  for (const e of area.entries) out.push(`- [${e.id}](#${e.id}) — ${e.symptom}`);
  out.push('');
  out.push('## Girişler');
  out.push('');
  for (const entry of area.entries) out.push(...renderEntry(entry, ctx));
  return `${out.join('\n')}\n`;
}

export function renderIndex(areas, ctx) {
  const out = [];
  out.push('# Arıza Klavuzu — İndeks (belirti → ilk bakılacak yer)');
  out.push('');
  out.push(
    '> Her satır: **belirti → ilk bağlantı (dosya:satır)** · anahtar sözcükler · giriş. Satırdaki bağlantı, o arıza için ' +
      'önce bakılacak koddur; olası nedenler, adımlar, günlük ifadeleri ve diğer bağlantılar için "giriş"i açın. ' +
      'Ekranda gördüğünüz **hata mesajı** için: [ARIZA_KLAVUZU_HATA_MESAJLARI.md](ARIZA_KLAVUZU_HATA_MESAJLARI.md). Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md).',
  );
  out.push('');
  for (const area of areas) {
    const mark = ctx.status.verified.includes(area.key) ? '✓' : '⚠ doğrulanmadı';
    out.push(`## ${area.title} (${area.entries.length}) — ${mark}`);
    out.push('');
    for (const e of area.entries) {
      const first = e.refs[0];
      const more = e.refs.length > 1 ? ` (+${e.refs.length - 1} bağlantı)` : '';
      const kw = e.keywords?.length ? ` · \`${e.keywords.join(', ')}\`` : '';
      out.push(
        `- **${e.symptom}** → ${linkOf(first.file, first.line, first.endLine, '../')}${more}${kw} · [giriş](${entryHref(e.id, ctx.idToArea, 'docs')})`,
      );
    }
    out.push('');
  }
  return `${out.join('\n')}\n`;
}

export function renderLanding(areas, ctx) {
  const total = areas.reduce((n, a) => n + a.entries.length, 0);
  const totalRefs = areas.reduce((n, a) => n + a.entries.reduce((m, e) => m + e.refs.length, 0), 0);
  const verifiedCount = areas.filter((a) => ctx.status.verified.includes(a.key)).length;
  const out = [];
  out.push('# Site Kapı Kontrol — Arıza Bulma Klavuzu');
  out.push('');
  out.push(
    '> Bu klavuz **elle yazılmış satır numarası içermez**: her `dosya:satır` bağlantısı `tools/klavuz/build.mjs` tarafından ' +
      'koddan çözülür; kod parçası bulunamazsa ya da belirsizse üretim hata verir. Kod değişince belgeleri yenileyin: ' +
      '`node tools/klavuz/build.mjs` (denetim: `node tools/klavuz/build.mjs --check --fresh`).',
  );
  out.push('');
  out.push(`Kapsam: ${areas.length} bölüm, **${total} arıza girişi**, ${totalRefs} kod bağlantısı + otomatik ekler.`);
  out.push('');
  out.push('## Nasıl kullanılır (kişi ya da ajan için)');
  out.push('');
  out.push('1. **Belirtiyi bulun:** [ARIZA_KLAVUZU_INDEKS.md](ARIZA_KLAVUZU_INDEKS.md) — her satır "belirti → ilk bakılacak dosya:satır". `Ctrl+F` ile anahtar sözcük arayın.');
  out.push('2. **Ekranda hata mesajı gördüyseniz:** [ARIZA_KLAVUZU_HATA_MESAJLARI.md](ARIZA_KLAVUZU_HATA_MESAJLARI.md) içinde mesajın bir parçasını arayın (mesaj → dosya:satır).');
  out.push('3. **Girişi açın:** indeksteki "giriş" bağlantısı bölüm dosyasına gider: bağlantılar + "ne işe yarar", olası nedenler, adım adım kontrol, günlükte aranacak ifadeler, komutlar, testler.');
  out.push('4. **Uçtan uca akış gerekiyorsa** "Uçtan uca akış haritaları" bölümlerine bakın (uygulama → sunucu → veritabanı → MQTT → cihaz).');
  out.push('5. **Bulamazsanız:** `node tools/klavuz/build.mjs --where "aranan metin"` (depoda arar), `--explain <giriş-id>` (girişin koddaki satırlarını bağlamıyla yazdırır), [ARIZA_KLAVUZU_EKLER.md](ARIZA_KLAVUZU_EKLER.md) (tüm uç noktalar, uygulama çağrıları, ortam değişkenleri, tablolar, dosya kapsamı).');
  out.push('');
  out.push('**Ajanlar için (dosyalar büyük: baştan okumayın, arayın):**');
  out.push('');
  out.push('```bash');
  out.push('rg -i "kapı açma" docs/ARIZA_KLAVUZU_INDEKS.md          # belirtiyi bul -> ilk dosya:satır + giriş kimliği');
  out.push('rg -n "^### sunucu-giris-401" docs/ariza-klavuzu/        # girişin bulunduğu bölüm dosyası ve satırı (sonra o satırdan okuyun)');
  out.push('node tools/klavuz/build.mjs --explain sunucu-giris-401   # girişin tüm bağlantıları için KODDAN satır bağlamı');
  out.push('rg -i "Giris bilgileri hatali" docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md   # ekranda görülen mesaj -> kaynak');
  out.push('```');
  out.push('');
  out.push('## Doğrulama durumu');
  out.push('');
  out.push(
    `**Mekanik (otomatik) denetim her çalıştırmada:** her bağlantı gerçek ve tekil bir kod satırı; testler/dosyalar var; ` +
      `giriş kimlikleri benzersiz ve \`related\` bağlantıları geçerli; günlük ifadeleri kodda geçiyor; komutlar sır basmıyor ve değiştiriciler etiketli.`,
  );
  out.push('');
  out.push(
    `**Bağımsız çürütücü inceleme (içeriğin doğruluğu):** ${verifiedCount}/${areas.length} bölüm geçti. ` +
      (ctx.status.note ? `${ctx.status.note} ` : '') +
      'Geçmeyen bölümler "⚠ doğrulanmadı" etiketlidir: açıklamayı bağlantıdaki koda bakarak teyit edin.',
  );
  out.push('');
  out.push('## Bölümler');
  out.push('');
  out.push('| Bölüm | Giriş | Bağlantı | İçerik doğrulaması |');
  out.push('| --- | --- | --- | --- |');
  for (const a of areas) {
    const refs = a.entries.reduce((m, e) => m + e.refs.length, 0);
    const ok = ctx.status.verified.includes(a.key) ? '✓ doğrulandı' : '⚠ doğrulanmadı';
    out.push(`| [${esc(a.title)}](ariza-klavuzu/${a.key}.md) | ${a.entries.length} | ${refs} | ${ok} |`);
  }
  out.push('');
  out.push('## İlgili belgeler ve kurallar');
  out.push('');
  out.push(
    '- Proje kuralları: [AGENTS.md](../AGENTS.md) (geriye uyumluluk, ESP32-C3 saha cihazı, taşma yasağı, canlı sunucu güncelleme).\n' +
      '- [PROJE_TEKNIK_NOTLAR.md](../PROJE_TEKNIK_NOTLAR.md), [SAHA_KONTROL_LISTESI.md](../SAHA_KONTROL_LISTESI.md), [BEKLEYEN_ISLER.md](../BEKLEYEN_ISLER.md)\n' +
      '- [docs/codebase/](codebase/), [deploy/README.md](../deploy/README.md), [docs/EPOSTA_DOGRULAMA.md](EPOSTA_DOGRULAMA.md)\n' +
      '- Araç ve giriş biçimi: [tools/klavuz/README.md](../tools/klavuz/README.md)',
  );
  out.push('');
  return `${out.join('\n')}\n`;
}

export function renderAppendices(scans, ctx) {
  const out = [];
  out.push('# Arıza Klavuzu — Ekler (otomatik)');
  out.push('');
  out.push('> Bu ekler koddan otomatik üretilir (elle yazılmaz). Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md) · [İndeks](ARIZA_KLAVUZU_INDEKS.md).');
  out.push('');

  out.push('## Ek A — Sunucu uç noktaları');
  out.push('');
  out.push('Kaynak: `server/src/routes/*.js` ve `server/src/server.js`. Sütunlar: yöntem, yol, o satırdaki ara katmanlar (yetki/hız sınırı).');
  out.push('');
  out.push('| Yöntem | Yol | Ara katmanlar | Dosya:satır |');
  out.push('| --- | --- | --- | --- |');
  for (const r of scans.routes) {
    out.push(`| ${r.method} | \`${esc(r.route)}\` | ${esc(clip(r.middleware, 70))} | ${linkOf(r.file, r.line)} |`);
  }
  out.push('');

  out.push('## Ek B — Uygulama → sunucu çağrıları');
  out.push('');
  out.push('Kaynak: `lib/services/*.dart`. Hangi uygulama metodunun hangi yola istek attığı (yol parametreleri `$` ile gösterilir).');
  out.push('');
  out.push('| Yol | Uygulama metodu | Dosya:satır |');
  out.push('| --- | --- | --- |');
  for (const r of scans.appCalls) {
    out.push(`| \`${esc(r.route)}\` | \`${esc(r.method)}\` | ${linkOf(r.file, r.line)} |`);
  }
  out.push('');

  out.push('## Ek C — Sunucu ortam değişkenleri');
  out.push('');
  out.push('Kaynak: `process.env.*` kullanımları (`server/src`, `server/scripts`). Değerler `server/.env` içindedir (canlıda `/var/www/site_kapi_kontrol/server/.env`); sır içerdiği için belgeye yazılmaz. Şablon: [server/.env.example](../server/.env.example).');
  out.push('');
  out.push('| Değişken | İlk kullanımlar |');
  out.push('| --- | --- |');
  for (const e of scans.env) {
    out.push(`| \`${e.name}\` | ${e.places.map((p) => linkOf(p.file, p.line)).join('<br>')} |`);
  }
  out.push('');

  out.push('## Ek D — Veritabanı tabloları');
  out.push('');
  out.push('Şema iki yerde tanımlanır: açılışta çalışan `server/src/db.js` (`ensureDbSchema`, ekleyici) ve numaralı `server/migrations/*.sql`.');
  out.push('');
  out.push('| Tablo | db.js | İlk migration |');
  out.push('| --- | --- | --- |');
  for (const t of scans.tables) {
    out.push(
      `| \`${t.name}\` | ${t.db ? linkOf('server/src/db.js', t.db) : '—'} | ${t.migration ? linkOf(t.migration.file, t.migration.line) : '—'} |`,
    );
  }
  out.push('');

  if (scans.coverage) {
    const rows = scans.coverage;
    const linked = rows.filter((r) => r.entries.length > 0).length;
    const mappedOnly = rows.filter((r) => r.entries.length === 0 && r.mappedIn.length > 0).length;
    const bare = rows.filter((r) => r.entries.length === 0 && r.mappedIn.length === 0);
    out.push('## Ek E — Kaynak dosya kapsamı');
    out.push('');
    out.push(
      `${rows.length} kaynak dosyanın **${linked}**'i en az bir arıza girişine bağlı, **${mappedOnly}**'i yalnız dosya haritasında, ` +
        `**${bare.length}**'i klavuzda hiç geçmiyor. Bir dosya hiç geçmiyorsa onunla ilgili arızayı \`--where\` ile arayın.`,
    );
    out.push('');
    out.push('| Dosya | Satır | Bağlı girişler | Dosya haritası |');
    out.push('| --- | --- | --- | --- |');
    for (const r of rows) {
      const shown = r.entries
        .slice(0, 5)
        .map((id) => `[${id}](${entryHref(id, ctx.idToArea, 'docs')})`)
        .join(', ');
      const more = r.entries.length > 5 ? ` +${r.entries.length - 5}` : '';
      out.push(
        `| [${r.file}](../${r.file}) | ${r.lines} | ${r.entries.length ? shown + more : '—'} | ${r.mappedIn.length ? r.mappedIn.join(', ') : '—'} |`,
      );
    }
    out.push('');
  }

  out.push('## Bu klavuza nasıl giriş eklenir');
  out.push('');
  out.push('`tools/klavuz/entries/<NN-alan>.mjs` dosyasına giriş ekleyin (biçim: [tools/klavuz/README.md](../tools/klavuz/README.md)). Satır numarası YAZMAYIN: yalnızca dosya ve aranacak kod parçası (`find`). Ardından `node tools/klavuz/build.mjs --check` ile doğrulayıp `node tools/klavuz/build.mjs` ile belgeleri yenileyin.');
  out.push('');
  return `${out.join('\n')}\n`;
}

export function renderMessages(messages) {
  const out = [];
  out.push('# Hata mesajı → kaynak (otomatik)');
  out.push('');
  out.push('> Kullanıcıya/istemciye görünen metinleri üretildikleri `dosya:satır` ile eşler. `Ctrl+F` ile ekranda gördüğünüz mesajın bir parçasını arayın. Koddan otomatik üretilir: `node tools/klavuz/build.mjs`. Ana sayfa: [ARIZA_KLAVUZU.md](ARIZA_KLAVUZU.md) · [İndeks](ARIZA_KLAVUZU_INDEKS.md).');
  out.push('');
  const table = (title, rows, note) => {
    out.push(`## ${title} (${rows.length})`);
    out.push('');
    out.push(note);
    out.push('');
    out.push('| Mesaj | Dosya:satır |');
    out.push('| --- | --- |');
    for (const r of rows) out.push(`| ${esc(clip(r.message, 220))} | ${linkOf(r.file, r.line)} |`);
    out.push('');
  };
  table('Sunucu mesajları', messages.server, 'Kaynak: `server/src` (`error:`, `message:`, `httpError(...)`, `new Error(...)`). Uygulama bu metinleri HTTP yanıt gövdesinde (`error` alanı) alır.');
  table('Uygulama (Flutter) mesajları', messages.app, 'Kaynak: `lib` (`ApiException(...)`, `_errorMessage =`, `lib/services` içindeki `return \'...\'`).');
  return `${out.join('\n')}\n`;
}

/** Tüm belgeler: Map<depo köküne göre yol, içerik>. */
export function renderAll(areas, scans, messages, status = { verified: [], note: '' }) {
  const idToArea = new Map();
  for (const a of areas) for (const e of a.entries) idToArea.set(e.id, a.key);
  const ctx = { idToArea, status: { verified: status.verified ?? [], note: status.note ?? '' } };
  const docs = new Map();
  docs.set(DOC_LANDING, renderLanding(areas, ctx));
  docs.set(DOC_INDEX, renderIndex(areas, ctx));
  docs.set(DOC_APPENDICES, renderAppendices(scans, ctx));
  docs.set(DOC_MESSAGES, renderMessages(messages));
  for (const a of areas) docs.set(`${AREA_DIR}/${a.key}.md`, renderAreaDoc(a, ctx));
  return docs;
}

// Donanım pin belgeleri firmware kaynağıyla çelişmemeli (karşılaştırma programı P1-18, 2026-10-28).
// Tek kaynak: cihaz_kontrol/include/{device_konfig,role_kontrol,display_uart}.h. Karşılaştırılanlar: BEKLEYEN_ISLER.md bölüm 1.1
// pin tablosu ve SAHA_KONTROL_LISTESI.md donanım maddeleri. DB'siz, statik; CRLF ve LF dosyaların ikisini de okur.
// Bir pin değişirse bu test hangi belge satırının güncellenmesi gerektiğini söyler; belgeyi kaynağa uydurun, testi gevşetmeyin.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = join(here, '..', '..');
const INCLUDE = ['cihaz_kontrol', 'include'];
const read = (...parts) => readFileSync(join(ROOT, ...parts), 'utf8').replace(/\r\n/g, '\n');

const BEKLEYEN = read('BEKLEYEN_ISLER.md');
const SAHA = read('SAHA_KONTROL_LISTESI.md');

/** `#if defined(BOARD_ESP32_WROOM_RELAY) ... #else ... #endif` bloğunu WROOM ve C3 gövdesi olarak ayırır. */
function boardBlocks(file) {
  const match = /#if defined\(BOARD_ESP32_WROOM_RELAY\)([\s\S]*?)#else([\s\S]*?)#endif/.exec(read(...INCLUDE, file));
  assert.ok(match, `${file}: kart bloğu bulunamadı`);
  return { wroom: match[1], c3: match[2] };
}

/** `ADI = 25;` biçimindeki sayısal atamayı okur (constexpr / inline / tür önekinden bağımsız). */
function constant(block, name) {
  const match = new RegExp(`\\b${name}\\s*=\\s*(\\d+)\\s*;`).exec(block);
  assert.ok(match, `${name} ataması bulunamadı`);
  return Number(match[1]);
}

const konfig = boardBlocks('device_konfig.h');
const role = boardBlocks('role_kontrol.h');
const displayHeader = read(...INCLUDE, 'display_uart.h');

const PINS = {
  wroom: {
    role: constant(role.wroom, 'ROLE_PIN'),
    led: constant(konfig.wroom, 'WIFI_STATUS_LED_PIN'),
    gm60: [constant(konfig.wroom, 'GM60_RX_PIN'), constant(konfig.wroom, 'GM60_TX_PIN')],
    display: [constant(displayHeader, 'DISPLAY_UART_RX_PIN'), constant(displayHeader, 'DISPLAY_UART_TX_PIN')],
    reset: constant(konfig.wroom, 'WIFI_RESET_BUTTON_PIN'),
  },
  c3: {
    role: constant(role.c3, 'ROLE_PIN'),
    led: constant(konfig.c3, 'WIFI_STATUS_LED_PIN'),
    gm60: [constant(konfig.c3, 'GM60_RX_PIN'), constant(konfig.c3, 'GM60_TX_PIN')],
    reset: constant(konfig.c3, 'WIFI_RESET_BUTTON_PIN'),
  },
};

/** SAHA listesinde `- [ ] **8.1. ...` ile başlayan maddenin satırları (bir sonraki madde, ayırıcı ya da başlığa kadar). */
function sahaMadde(id) {
  const lines = SAHA.split('\n');
  const baslik = new RegExp(`^- \\[[ x]\\] \\*\\*${id.replace(/\./g, '\\.')}\\.`);
  const starts = lines.flatMap((line, index) => (baslik.test(line) ? [index] : []));
  assert.equal(starts.length, 1, `SAHA ${id} maddesi tam bir kez olmalı (bulunan: ${starts.length})`);
  let end = starts[0] + 1;
  while (end < lines.length && !/^(- \[[ x]\] |---$|## )/.test(lines[end])) end += 1;
  return lines.slice(starts[0], end).join('\n');
}

describe('firmware kaynağı: WROOM pinleri çakışmaz (P1-18 kök nedeni)', () => {
  it('röle, durum LED, GM60 ve ekran UART pinleri birbirinden farklıdır; GM60 röle pinine verilmemiştir', () => {
    const { role: roleP, led, gm60, display, reset } = PINS.wroom;
    const all = [roleP, led, ...gm60, ...display, reset];
    assert.equal(new Set(all).size, all.length, `WROOM pinleri çakışıyor: ${all.join(', ')}`);
    assert.ok(!gm60.includes(roleP), 'GM60 UART pini röle pinine verilemez');
  });
});

describe('BEKLEYEN_ISLER.md bölüm 1.1 pin tablosu firmware ile aynı', () => {
  const cells = (row) => row.split('|').slice(1, -1).map((cell) => cell.trim());
  const gpioNumbers = (cell) => [...cell.matchAll(/GPIO (\d+)/g)].map((match) => Number(match[1]));

  function tabloSatiri(label) {
    const rows = BEKLEYEN.split('\n').filter((line) => line.startsWith('|') && (cells(line)[0] ?? '').includes(label));
    assert.equal(rows.length, 1, `pin tablosunda "${label}" satırı tam bir kez olmalı (bulunan: ${rows.length})`);
    const [, wroomCell, c3Cell] = cells(rows[0]);
    return { wroom: gpioNumbers(wroomCell), c3: gpioNumbers(c3Cell) };
  }

  const EXPECTED = [
    ['Röle', { wroom: [PINS.wroom.role], c3: [PINS.c3.role] }],
    ['Durum LED', { wroom: [PINS.wroom.led], c3: [PINS.c3.led] }],
    ['GM60', { wroom: PINS.wroom.gm60, c3: PINS.c3.gm60 }],
    ['Ekran UART', { wroom: PINS.wroom.display, c3: [] }],
    ['sıfırlama', { wroom: [PINS.wroom.reset], c3: [PINS.c3.reset] }],
  ];
  for (const [label, expected] of EXPECTED) {
    it(`"${label}" satırı kaynak sabitleriyle aynı`, () => {
      assert.deepEqual(tabloSatiri(label), expected);
    });
  }
});

describe('SAHA_KONTROL_LISTESI.md donanım maddeleri firmware ile aynı', () => {
  const gpio = (pin) => new RegExp(`GPIO ?${pin}\\b`);

  it('madde numaraları tekildir (eski dosyada 8.1 iki kez vardı); numaralar yeniden verilmez', () => {
    const counts = new Map();
    for (const match of SAHA.matchAll(/^- \[[ x]\] \*\*(\d+\.\d+)\./gm)) counts.set(match[1], (counts.get(match[1]) ?? 0) + 1);
    const duplicates = [...counts].filter(([, count]) => count > 1).map(([id]) => id);
    assert.deepEqual(duplicates, [], `yinelenen madde numaraları: ${duplicates.join(', ')}`);
  });

  it('8.1: GM60 RX/TX firmware ile aynı; GM60\'ı röle pinine bağlatan eski 16/17 maddesi yok', () => {
    const madde = sahaMadde('8.1');
    const [rx, tx] = PINS.wroom.gm60;
    assert.match(madde, gpio(rx));
    assert.match(madde, gpio(tx));
    assert.equal(/GM60 Pin 16\/17/.test(SAHA), false, 'GM60\'ı röle pinine bağlatan eski "Pin 16/17" maddesi geri gelmiş');
  });

  it('8.2: ekran UART RX/TX firmware ile aynı', () => {
    const [rx, tx] = PINS.wroom.display;
    assert.ok(sahaMadde('8.2').includes(`RX=${rx}, TX=${tx}`));
  });

  it('10.3 ve 29.2: röle ve durum LED pini firmware ile aynı', () => {
    for (const id of ['10.3', '29.2']) {
      const madde = sahaMadde(id);
      assert.match(madde, gpio(PINS.wroom.role), `SAHA ${id}: röle pini`);
      assert.match(madde, gpio(PINS.wroom.led), `SAHA ${id}: durum LED pini`);
    }
  });

  it('29.2: GM60 RX/TX firmware ile aynı', () => {
    const [rx, tx] = PINS.wroom.gm60;
    assert.ok(sahaMadde('29.2').includes(`RX: ${rx}, TX: ${tx}`));
  });

  it('29.1: C3 röle ve durum LED pini firmware ile aynı', () => {
    const madde = sahaMadde('29.1');
    assert.match(madde, gpio(PINS.c3.role));
    assert.match(madde, gpio(PINS.c3.led));
  });

  it('51.20 ve 51.31: atölye komutu ve osiloskop maddeleri röle pinini firmware ile aynı yazar', () => {
    assert.match(sahaMadde('51.20'), gpio(PINS.wroom.role));
    assert.ok(sahaMadde('51.31').includes(`C3 GPIO${PINS.c3.role} / WROOM GPIO${PINS.wroom.role}`));
  });

  it('etkilenen donanım maddelerinde "Kod/test kanıtı" kutusu vardır ve üstteki kutunun cihaz/saha kabulü olduğu başta açıklanır', () => {
    for (const id of ['7.3', '8.1', '8.2', '8.3', '8.5', '10.3', '29.1', '29.2']) {
      assert.match(sahaMadde(id), /^ +- \[[ x]\] \*\*Kod\/test kanıtı:\*\*/m, `SAHA ${id}: "Kod/test kanıtı" kutusu eksik`);
    }
    assert.ok(SAHA.includes('Üstteki kutu cihaz/saha kabulüdür'), 'listenin başındaki kanıt türü açıklaması eksik');
  });
});

describe('iki belgede eski çelişkili pin ifadeleri kalmadı', () => {
  const ESKI_IFADELER = [
    /GM60 Pin 16\/17/,
    /GM60 TX -> WROOM GPIO ?16/,
    /GPIO ?18 RX/,
    /GPIO ?17 TX/,
    /GPIO 16`? veya `?GPIO 23/,
    /GPIO ?23 rölesi/,
  ];
  for (const [ad, metin] of [['BEKLEYEN_ISLER.md', BEKLEYEN], ['SAHA_KONTROL_LISTESI.md', SAHA]]) {
    it(`${ad}: eski ifadeler yok`, () => {
      // assert.doesNotMatch başarısızlıkta tüm belgeyi basardı; yalnız ifadeyi bildiriyoruz.
      for (const ifade of ESKI_IFADELER) assert.equal(ifade.test(metin), false, `${ad}: eski pin ifadesi geri gelmiş: ${ifade}`);
    });
  }
});

// Sahte kimlik uretimi: ad-soyad, kullanici adi, e-posta (@demo.invalid), telefon, IBAN, plaka, parola.
// GERCEK kisi/TCKN/telefon uydurulmaz: yalniz yaygin ad ve soyad kombinasyonlari; telefon 0 500 000 xx xx kalibi.

import crypto from 'node:crypto';

export const DEMO_EMAIL_DOMAIN = 'demo.invalid'; // RFC 2606 ayrilmis; teslim edilemez

export const MALE_NAMES = [
  'Ahmet', 'Mehmet', 'Mustafa', 'Ali', 'Hüseyin', 'İbrahim', 'Murat', 'Emre', 'Burak', 'Serkan', 'Hakan', 'Okan', 'Cem', 'Kemal', 'Orhan',
  'Fatih', 'Volkan', 'Selim', 'Tolga', 'Barış', 'Kerem', 'Yusuf', 'Osman', 'Halil', 'Recep', 'Cengiz', 'Erdem', 'Onur', 'Uğur', 'Levent',
];
export const FEMALE_NAMES = [
  'Ayşe', 'Fatma', 'Emine', 'Hatice', 'Zeynep', 'Elif', 'Merve', 'Esra', 'Seda', 'Derya', 'Burcu', 'Gül', 'Selin', 'Pınar', 'Özlem',
  'Sibel', 'Gamze', 'Neslihan', 'Hülya', 'Sevgi', 'Aylin', 'Dilek', 'Songül', 'Yasemin', 'Nur', 'Tuba', 'Ebru', 'Leyla', 'Meltem', 'Canan',
];
export const BOY_NAMES = ['Efe', 'Emir', 'Kaan', 'Arda', 'Yağız', 'Ali Eymen', 'Berat', 'Çağan', 'Deniz', 'Mert', 'Eren', 'Alp', 'Baran', 'Kuzey'];
export const GIRL_NAMES = ['Defne', 'Elif Naz', 'Zehra', 'Ecrin', 'Asya', 'Ela', 'Nehir', 'Melis', 'İpek', 'Duru', 'Azra', 'Sude', 'Mira', 'Irmak'];
export const ELDER_MALE = ['Hasan', 'Ismail', 'Cemal', 'Mahmut', 'Salih', 'Nuri', 'Kadir', 'Veli'];
export const ELDER_FEMALE = ['Hanife', 'Nazlı', 'Saadet', 'Melek', 'Nuriye', 'Zühre', 'Sakine', 'Gülsüm'];
export const SURNAMES = [
  'Yılmaz', 'Kaya', 'Demir', 'Şahin', 'Çelik', 'Yıldız', 'Yıldırım', 'Öztürk', 'Aydın', 'Özdemir', 'Arslan', 'Doğan', 'Kılıç', 'Aslan', 'Çetin',
  'Kara', 'Koç', 'Kurt', 'Özkan', 'Şimşek', 'Polat', 'Erdoğan', 'Güneş', 'Aksoy', 'Tekin', 'Acar', 'Bulut', 'Korkmaz', 'Tunç', 'Bozkurt',
];

const FOLD = { ç: 'c', ğ: 'g', ı: 'i', ö: 'o', ş: 's', ü: 'u', â: 'a', î: 'i', û: 'u', İ: 'i', Ç: 'c', Ğ: 'g', Ö: 'o', Ş: 's', Ü: 'u', I: 'i' };

/** Turkce harfleri katlar, kucuk harf, yalniz a-z0-9 ve nokta. */
export function foldAscii(text) {
  let out = '';
  for (const ch of String(text)) out += FOLD[ch] ?? ch;
  return out.toLowerCase().replace(/[^a-z0-9. ]/g, '').trim();
}

/** 'Ayse Yilmaz' -> 'ayse.yilmaz' ; cok sozcuklu adlar birlestirilir ('Ali Eymen' -> 'alieymen'). */
export function baseUsername(fullName) {
  const parts = String(fullName).trim().split(/\s+/);
  const surname = parts.pop();
  const given = parts.join('');
  return `${foldAscii(given).replace(/\s/g, '')}.${foldAscii(surname).replace(/\s/g, '')}`;
}

/** Cakisma halinde sayi eki ekler. `taken` bir Set (kucuk harf). */
export function uniqueUsername(fullName, taken) {
  const base = baseUsername(fullName);
  let candidate = base;
  let n = 1;
  while (taken.has(candidate)) {
    n += 1;
    candidate = `${base}${n}`;
  }
  taken.add(candidate);
  return candidate;
}

export const emailOf = (username) => `${username}@${DEMO_EMAIL_DOMAIN}`;

// Karisabilen karakterler (i, l, 1, I, O, o, 0) yok.
const PASS_UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const PASS_LOWER = 'abcdefghjkmnpqrstuvwxyz';
const PASS_DIGIT = '23456789';

/** 12 karakter, kriptografik rastgele; en az bir buyuk, kucuk ve rakam. */
export function generatePassword(length = 12) {
  const all = PASS_UPPER + PASS_LOWER + PASS_DIGIT;
  const chars = [
    PASS_UPPER[crypto.randomInt(PASS_UPPER.length)],
    PASS_LOWER[crypto.randomInt(PASS_LOWER.length)],
    PASS_DIGIT[crypto.randomInt(PASS_DIGIT.length)],
  ];
  while (chars.length < length) chars.push(all[crypto.randomInt(all.length)]);
  for (let i = chars.length - 1; i > 0; i -= 1) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

/** Yapay telefon: +90 500 000 XX XX (gercek numara olmasin diye 500 000 blogu). */
export function fakePhone(counter) {
  const n = String(counter % 10000).padStart(4, '0');
  return `+90500000${n}`;
}

/** Gorunum: 0 500 000 12 34 */
export function displayPhone(e164) {
  const d = e164.replace(/^\+90/, '');
  return `0 ${d.slice(0, 3)} ${d.slice(3, 6)} ${d.slice(6, 8)} ${d.slice(8, 10)}`;
}

// --- IBAN (sahte; bicim gecerli mod-97; banka kodu gercek bir bankaya ait degil) ---------------------------------

function iban97(normalized) {
  const moved = normalized.slice(4) + normalized.slice(0, 4);
  let remainder = 0;
  for (const ch of moved) {
    const code = ch >= 'A' && ch <= 'Z' ? String(ch.charCodeAt(0) - 55) : ch;
    for (const digit of code) remainder = (remainder * 10 + Number(digit)) % 97;
  }
  return remainder;
}

/** TR + 2 kontrol + 5 banka kodu + 1 ayrilmis (0) + 16 hesap. Banka kodu 99990 gercek bir bankaya ait degildir. */
export function fakeIban(seed = 1) {
  const bankCode = '99990';
  const account = String(1000000000000000 + (seed * 7919) % 8999999999999999).slice(0, 16);
  const bban = `${bankCode}0${account}`;
  const check = String(98 - iban97(`TR00${bban}`)).padStart(2, '0');
  return `TR${check}${bban}`;
}

// --- plaka --------------------------------------------------------------------------------------------------------

const PLATE_LETTERS = 'ABCDEFGHJKLMNPRSTUVYZ';

/** Gercekci Turk plakasi: il kodu 01-81 + 1-3 harf + 2-4 rakam (toplam harf+rakam kurallarina uygun). */
export function fakePlate(rng) {
  const il = String(rng.int(1, 81)).padStart(2, '0');
  const letterCount = rng.weighted([[1, 2], [2, 5], [3, 3]]);
  const digitCount = letterCount === 1 ? rng.int(3, 4) : letterCount === 2 ? rng.int(3, 4) : rng.int(2, 3);
  let letters = '';
  for (let i = 0; i < letterCount; i += 1) letters += PLATE_LETTERS[rng.int(0, PLATE_LETTERS.length - 1)];
  let digits = '';
  for (let i = 0; i < digitCount; i += 1) digits += String(rng.int(i === 0 ? 1 : 0, 9));
  const norm = `${il}${letters}${digits}`;
  return { normalized: norm, display: `${il} ${letters} ${digits}` };
}

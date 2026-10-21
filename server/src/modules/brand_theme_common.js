// Beyaz etiket tema doğrulaması (SAF; veritabanı yok). Renkler "#RRGGBB" (büyük harfe çevrilir); metin/zemin/yüzey ve vurgu/yüzey
// çiftleri en az 4,5:1 kontrast vermeli (WCAG AA). Logo: png/jpeg/webp base64 veri URL'si, en çok ~150 KB.
import { PlatformError } from './errors.js';

export const COLOR_KEYS = Object.freeze(['primary', 'accent', 'background', 'surface', 'text']);
export const MAX_NAME_LENGTH = 40;
export const MAX_LOGO_CHARS = 200000;
export const MIN_CONTRAST = 4.5;
const HEX_RE = /^#[0-9A-Fa-f]{6}$/;
const LOGO_RE = /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/;

const bad = (message, code = 'INVALID_THEME') => new PlatformError(400, code, message);

export function luminance(hex) {
  const channel = (i) => {
    const v = parseInt(hex.slice(1 + i * 2, 3 + i * 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(0) + 0.7152 * channel(1) + 0.0722 * channel(2);
}

export function contrast(a, b) {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** Ana renk üstündeki yazı rengi: beyaz ya da koyu lacivert, hangisi daha kontrastlıysa. */
export function onColorFor(hex) {
  return contrast(hex, '#FFFFFF') >= contrast(hex, '#0F172A') ? '#FFFFFF' : '#0F172A';
}

function normalizeColor(value, label) {
  if (typeof value !== 'string' || !HEX_RE.test(value.trim())) {
    throw bad(`${label} rengi #RRGGBB biçiminde olmalı.`, 'INVALID_COLOR');
  }
  return value.trim().toUpperCase();
}

/** Gövdeden normalleştirilmiş tema: { display_name, colors:{...}, logo_data } (logo_data: undefined = dokunma, null = kaldır). */
export function validateThemeBody(body) {
  const b = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const colorsIn = b.colors && typeof b.colors === 'object' ? b.colors : {};
  const labels = { primary: 'Ana', accent: 'Vurgu', background: 'Zemin', surface: 'Kart', text: 'Yazı' };
  const colors = {};
  for (const key of COLOR_KEYS) colors[key] = normalizeColor(colorsIn[key], labels[key]);

  if (contrast(colors.text, colors.background) < MIN_CONTRAST || contrast(colors.text, colors.surface) < MIN_CONTRAST) {
    throw bad('Yazı rengi zemin ve kart üzerinde okunaklı değil (en az 4,5:1 karşıtlık gerekir).', 'LOW_CONTRAST');
  }
  if (contrast(colors.accent, colors.surface) < MIN_CONTRAST) {
    throw bad('Vurgu rengi kart üzerinde okunaklı değil (en az 4,5:1 karşıtlık gerekir).', 'LOW_CONTRAST');
  }

  let displayName = null;
  if (b.display_name !== undefined && b.display_name !== null && String(b.display_name).trim() !== '') {
    displayName = String(b.display_name).trim();
    if (displayName.length > MAX_NAME_LENGTH) throw bad(`Uygulama adı en çok ${MAX_NAME_LENGTH} karakter olabilir.`, 'INVALID_NAME');
  }

  let logo;
  if (b.logo_data === null) logo = null;
  else if (b.logo_data !== undefined) {
    if (typeof b.logo_data !== 'string' || b.logo_data.length > MAX_LOGO_CHARS || !LOGO_RE.test(b.logo_data)) {
      throw bad('Logo png, jpeg ya da webp olmalı ve en çok 150 KB olabilir.', 'INVALID_LOGO');
    }
    logo = b.logo_data;
  }
  return { display_name: displayName, colors, logo_data: logo };
}

/** Satır -> istemci gövdesi. `on_primary` sunucuda hesaplanır (istemci aynı kuralı yeniden kontrol eder). */
export function themeFromRow(row, source) {
  if (!row) return null;
  return {
    source,
    scope_type: row.scope_type,
    scope_id: Number(row.scope_id),
    display_name: row.display_name ?? null,
    colors: {
      primary: row.color_primary,
      accent: row.color_accent,
      background: row.color_background,
      surface: row.color_surface,
      text: row.color_text,
    },
    on_primary: onColorFor(row.color_primary),
    logo_data: row.logo_data ?? null,
    updated_at: row.updated_at ?? null,
  };
}

// Online tahsilat sağlayıcı sürücü kaydı. Sürücü arayüzü ve yeni sürücü ekleme rehberi: docs/PLATFORM_ONLINE_TAHSILAT.md.
//
// Sürücü = { code, name, enabled, fields[], validate?(values, mode) -> string[], testConnection?(ctx) -> { ok, message } }.
//  - enabled: GERÇEK sürücü kodu yazılıp sözleşmeyle denenene kadar FALSE kalır. false iken bağlantı sınanamaz (dürüst "etkin değil" sonucu) ve sakine "Online Öde" ASLA çıkmaz.
//  - fields[]: { key, label, secret, required, min, max, pattern (RegExp), hint }. secret:true alanlar şifreli saklanır, API yanıtında ASLA dönmez.
// Bu dosyada ödeme ALMA / "ödendi" yazma kodu yoktur; ödeme sonucu yalnız imzası doğrulanmış sağlayıcı geri çağrısından (sürücüyle birlikte eklenecek) yazılabilir.

const KEY_PATTERN = /^[A-Za-z0-9._-]+$/;

export const PROVIDERS = Object.freeze({
  // Yer tutucu: yönetici henüz sağlayıcı seçmedi / sözleşme yok. Alan yok, sınama yok.
  sanal_pos_hazir_degil: Object.freeze({
    code: 'sanal_pos_hazir_degil',
    name: 'Sanal POS henüz hazır değil',
    enabled: false,
    fields: Object.freeze([]),
  }),
  iyzico: Object.freeze({
    code: 'iyzico',
    name: 'iyzico',
    enabled: false,
    fields: Object.freeze([
      Object.freeze({ key: 'api_key', label: 'API anahtarı', secret: true, required: true, min: 8, max: 128, pattern: KEY_PATTERN, hint: 'iyzico panelindeki API anahtarı' }),
      Object.freeze({ key: 'secret_key', label: 'Gizli anahtar', secret: true, required: true, min: 8, max: 128, pattern: KEY_PATTERN, hint: 'iyzico panelindeki gizli anahtar' }),
      Object.freeze({ key: 'merchant_id', label: 'Üye işyeri no (varsa)', secret: false, required: false, min: 3, max: 30, pattern: /^[0-9]+$/, hint: 'Yalnız rakam' }),
    ]),
    validate(values, mode) {
      // iyzico test (sandbox) anahtarları "sandbox-" ile başlar; canlı modda kullanılamaz.
      return mode === 'live' && String(values.api_key ?? '').toLowerCase().startsWith('sandbox-') ? ['Canlı modda test (sandbox) anahtarı kullanılamaz.'] : [];
    },
  }),
});

export const getProvider = (code) => (Object.hasOwn(PROVIDERS, code) ? PROVIDERS[code] : null);

/** İstemciye giden sağlayıcı listesi (alan tanımları; desen ve sır değeri yok). */
export function listProviders() {
  return Object.values(PROVIDERS).map((p) => ({
    code: p.code,
    name: p.name,
    driver_active: p.enabled === true,
    fields: p.fields.map((f) => ({ key: f.key, label: f.label, secret: f.secret, required: f.required, max: f.max, hint: f.hint ?? null })),
  }));
}

// Daire sahipligi ve yonetimi: SAF (DB'siz) kurallar. Sozlesme: docs/PLATFORM_DAIRE_YONETIMI.md.
//
//  - Admin cozumleme: MEVCUT gosterge (aktif apartment_memberships.role = 'APARTMENT_ADMIN', yoksa eski apartments.resident_user_code) esas alinir;
//    "kiraci yoksa admin maliktir" kurali OKUMA tarafinda turetilir (eski kayitlar degismez).
//  - Imza hakki sahibi: aktif vekil varsa vekil, yoksa malik. Ayni daire icin tek kisi.
//  - Gizlilik: kisi arama sonuclari yalniz maskeli ad / e-posta tasir.

import crypto from 'node:crypto';

export const SCOPES = Object.freeze(['toplanti_imza', 'kurul_uyeligi']);
export const REQUEST_KINDS = Object.freeze(['tenant_invite', 'family_invite', 'disconnect', 'member_removal']);
export const REQUEST_TTL_DAYS = 14;
// Yetiskin uyeyi cikarma istegi: 7 gun yanitsiz kalirsa KAPANIR (otomatik kesme YOK).
export const REMOVAL_TTL_DAYS = 7;
export const SAFETY_REASONS = Object.freeze(['court_order', 'safety', 'other']);
export const SAFETY_CONTACTS = Object.freeze(['app', 'phone', 'email']);
export const SAFETY_STATUSES = Object.freeze(['open', 'in_review', 'resolved']);
export const SEARCH_MIN_CHARS = 3;
export const SEARCH_MAX_RESULTS = 5;
export const SEARCH_HOURLY_LIMIT = 60;
export const CANDIDATE_TTL_MS = 15 * 60 * 1000;
export const FAMILY_MAX_PER_APARTMENT = 12;

const DAY_MS = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Rol ve admin cozumleme
// ---------------------------------------------------------------------------

const asCode = (value) => {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
};

/**
 * Acik yonetim devri (apartment_admin_delegations) admini YALNIZ su durumda belirler; aksi halde kayit BAYAT sayilir ve yok hukmundedir
 * (satir kapatilmadan devralan gitmis / pasiflesmis olabilir; eskiden devir aktif APARTMENT_ADMIN uyeligini kosulsuz eziyordu):
 *  - devralan hesapliysa (admin_user_code) bu dairede AKTIF uyeligi vardir,
 *  - kaynak 'tenant_delegated' ise (malik -> kiraci devri) devralan GUNCEL KIRACIDIR; diger kaynaklarda ('manager' vb.) devralan en az guncel
 *    bir sakindir (site yoneticisi malik / aile uyesini de atayabilir),
 *  - hesapsiz devralanda (pending_account) kisi kaydi guncel iliskilerde bulunur.
 */
function delegationApplies(delegation, { members, residencies, tenant }) {
  if (!delegation || delegation.ended_at != null) return false;
  const delegateCode = asCode(delegation.admin_user_code);
  const delegatePerson = asCode(delegation.admin_person_id);
  if (delegateCode === null && delegatePerson === null) return false;
  if (delegateCode !== null && !members.some((m) => asCode(m.user_code) === delegateCode)) return false;
  const isSame = (r) => Boolean(r) && ((delegateCode !== null && asCode(r.user_code) === delegateCode) || (delegatePerson !== null && asCode(r.person_id) === delegatePerson));
  if ((delegation.source ?? 'tenant_delegated') === 'tenant_delegated') return isSame(tenant);
  return residencies.some(isSame);
}

/**
 * Bir dairenin rol durumu.
 * @param {{
 *   members: Array<{ user_code: number, role: string, is_active?: boolean, created_at?: any }>,
 *   legacyUserCode?: number|null,
 *   residencies: Array<{ id: number, person_id: number, user_code: number|null, relation: string, name?: string|null, sponsor_person_id?: number|null }>,
 * }} state yalniz AKTIF uyelikler ve GUNCEL iliskiler
 */
export function resolveApartmentRoles(state) {
  const members = (state?.members ?? []).filter((m) => m.is_active !== false);
  const residencies = state?.residencies ?? [];
  const delegation = state?.delegation ?? null;
  const owner = residencies.find((r) => r.relation === 'owner') ?? null;
  const tenant = residencies.find((r) => r.relation === 'tenant') ?? null;
  const family = residencies.filter((r) => r.relation === 'family_member');

  // Admin: ilk aktif APARTMENT_ADMIN (eskiden yeniye); yoksa acik devir kaydi; yoksa eski sakin gostergesi.
  const sorted = [...members].sort((a, b) => new Date(a.created_at ?? 0) - new Date(b.created_at ?? 0));
  const adminMember = sorted.find((m) => m.role === 'APARTMENT_ADMIN') ?? null;
  const legacy = asCode(state?.legacyUserCode);
  let adminUserCode = adminMember ? asCode(adminMember.user_code) : null;
  let adminSource = adminMember ? 'membership' : null;

  let adminPersonId = null;
  if (delegationApplies(delegation, { members, residencies, tenant })) {
    if (delegation.admin_user_code) {
      adminUserCode = asCode(delegation.admin_user_code);
      adminSource = delegation.source || 'delegation';
    }
    if (delegation.admin_person_id) {
      adminPersonId = asCode(delegation.admin_person_id);
    }
  }

  if (adminUserCode === null && legacy !== null) {
    adminUserCode = legacy;
    adminSource = 'legacy';
  }

  let adminResidency = adminUserCode === null
    ? (adminPersonId !== null ? residencies.find((r) => asCode(r.person_id) === adminPersonId) ?? null : null)
    : residencies.find((r) => asCode(r.user_code) === adminUserCode) ?? null;

  if (adminPersonId === null && adminResidency) {
    adminPersonId = asCode(adminResidency.person_id);
  }

  // Varsayilan admin (hicbir hesap veya devir yoksa): tenant > owner > ilk sakin
  if (adminUserCode === null && adminPersonId === null && residencies.length > 0) {
    const defaultRes = tenant ?? owner ?? residencies[0];
    if (defaultRes) {
      adminPersonId = asCode(defaultRes.person_id);
      if (defaultRes.user_code) {
        adminUserCode = asCode(defaultRes.user_code);
      }
      adminResidency = defaultRes;
      adminSource = 'default_resident';
    }
  }

  let adminKind = 'none';
  if (adminUserCode !== null || adminPersonId !== null) {
    const isOwnerMatch = (adminUserCode !== null && owner && asCode(owner.user_code) === adminUserCode) ||
                         (adminPersonId !== null && owner && asCode(owner.person_id) === adminPersonId);
    const isTenantMatch = (adminUserCode !== null && tenant && asCode(tenant.user_code) === adminUserCode) ||
                          (adminPersonId !== null && tenant && asCode(tenant.person_id) === adminPersonId);
    if (isOwnerMatch) adminKind = 'owner';
    else if (isTenantMatch) adminKind = 'tenant';
    else if (adminResidency?.relation === 'family_member') adminKind = 'family';
    // Kiraci yoksa ve malik kaydi yoksa admin maliktir (turetilmis); aksi halde ilişkisi belirsiz yonetici.
    else if (!owner && !tenant) adminKind = 'owner_derived';
    else adminKind = 'other';
  }
  return { owner, tenant, family, adminUserCode, adminPersonId, adminSource, adminResidency, adminKind };
}

/** Admin (yonetimi yapan) tarafindan gosterilen etiket: 'owner' | 'tenant' | 'other' | 'none'. */
export function adminSideOf(roles) {
  if (roles.adminKind === 'owner' || roles.adminKind === 'owner_derived') return 'owner';
  if (roles.adminKind === 'tenant') return 'tenant';
  return roles.adminKind === 'none' ? 'none' : 'other';
}

/**
 * Bir kullanicinin dairedeki rolu ve yapabilecekleri.
 * `pendingTenantInvite` / `pendingDisconnect`: bekleyen talep var mi (tekrar acilmasin).
 */
export function rolesOfUser(roles, userCode, { pendingTenantInvite = false, pendingDisconnect = false, hasMembership = true } = {}) {
  const uc = asCode(userCode);
  const isAdmin = uc !== null && roles.adminUserCode === uc;
  const ownerReal = Boolean(roles.owner && asCode(roles.owner.user_code) === uc && uc !== null);
  const ownerDerived = !roles.owner && !roles.tenant && isAdmin;
  const isOwner = ownerReal || ownerDerived;
  const isTenant = Boolean(roles.tenant && asCode(roles.tenant.user_code) === uc && uc !== null);
  const mine = uc === null ? null : (roles.family.find((r) => asCode(r.user_code) === uc) ?? null);
  const isFamily = Boolean(mine) && !isOwner && !isTenant;

  let myRole = 'resident';
  if (isOwner) myRole = 'owner';
  else if (isTenant) myRole = 'tenant';
  else if (isFamily) myRole = 'family_member';
  else if (!isAdmin && hasMembership) myRole = 'family_member';

  const tenantExists = Boolean(roles.tenant);
  const can = {
    manage_family: isAdmin,
    add_tenant: isOwner && !tenantExists && !pendingTenantInvite,
    // Kiraci HER ZAMAN daire admini (kullanici karari 2026-10-26): "yonetimi devret" secenegi kalkti. Alan eski istemciler icin sabit false kalir.
    delegate_management: false,
    exit: isTenant,
    request_disconnect: (isOwner || isTenant) && tenantExists && !pendingDisconnect,
    manage_proxy: isOwner && tenantExists,
    search_people: isOwner || isAdmin,
  };
  return { is_admin: isAdmin, is_owner: isOwner, is_owner_derived: ownerDerived, is_tenant: isTenant, is_family: isFamily, my_role: myRole, can };
}

/** Karsilikli bag kesme talebinin karsi tarafi (kullanici kodu); karsi tarafin hesabi yoksa null. */
export function disconnectCounterpart(roles, userCode) {
  const state = rolesOfUser(roles, userCode);
  if (state.is_tenant) {
    // Kiraci acti: onaylayacak taraf malik (turetilmis malik de olabilir: kiraci varken turetilmez, yani gercek malik kaydi gerekir).
    return asCode(roles.owner?.user_code);
  }
  if (state.is_owner) {
    return asCode(roles.tenant?.user_code);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Talep (durum makinesi)
// ---------------------------------------------------------------------------

export function requestExpiresAt(now = new Date(), kind = 'tenant_invite') {
  const days = kind === 'member_removal' ? REMOVAL_TTL_DAYS : REQUEST_TTL_DAYS;
  return new Date(now.getTime() + days * DAY_MS);
}

/**
 * Koruma politikasi: daire admini bir uyenin baglarini TEK TARAFLI yalniz su durumlarda keser: uye 18 yasindan kucuk isaretliyse ya da
 * uyenin hesabi yoksa (kesilecek bir kapi erisimi / uygulama yetkisi yok). Hesabi olan YETISKIN uye icin onay istegi gerekir.
 */
export function adminMayRemoveWithoutConsent(residency) {
  return Boolean(residency) && (residency.is_minor === true || asCode(residency.user_code) === null);
}

/** Talep gercek durumu: bekleyen ama suresi dolmus talep 'expired' sayilir. */
export function effectiveRequestStatus(request, now = new Date()) {
  if (request?.status === 'pending' && new Date(request.expires_at) <= now) return 'expired';
  return request?.status ?? 'cancelled';
}

/** Yanita izin: yalniz bekleyen, suresi dolmamis ve hedef kullanici. */
export function canRespondToRequest(request, userCode, now = new Date()) {
  return effectiveRequestStatus(request, now) === 'pending' && asCode(request?.target_user_code) === asCode(userCode) && asCode(userCode) !== null;
}

/** Geri cekme izni: yalniz bekleyen ve talebi acan. */
export function canCancelRequest(request, userCode, now = new Date()) {
  return effectiveRequestStatus(request, now) === 'pending' && asCode(request?.requested_by) === asCode(userCode) && asCode(userCode) !== null;
}

// ---------------------------------------------------------------------------
// Vekalet ve imza hakki
// ---------------------------------------------------------------------------

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export function isIsoDate(value) {
  if (typeof value !== 'string' || !ISO_DATE.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

/** Bir takvim yili sonrasi (29 Subat -> 28 Subat). */
export function addOneYear(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  const target = new Date(Date.UTC(y + 1, m - 1, d));
  if (target.getUTCMonth() !== m - 1) {
    return new Date(Date.UTC(y + 1, m, 0)).toISOString().slice(0, 10);
  }
  return target.toISOString().slice(0, 10);
}

/**
 * Vekalet gecerlilik penceresi: baslangic varsayilan bugun (gecmis olamaz, en cok 1 yil ileri), bitis varsayilan baslangic + 1 yil,
 * bitis baslangictan once olamaz ve baslangic + 1 yili asamaz. @returns {{ valid_from: string, valid_until: string }}
 */
export function resolveProxyWindow({ validFrom, validUntil, today }) {
  const from = validFrom ?? today;
  if (!isIsoDate(from)) return { error: 'valid_from', message: 'Başlangıç tarihi geçersiz.' };
  if (from < today) return { error: 'valid_from', message: 'Başlangıç tarihi geçmişte olamaz.' };
  if (from > addOneYear(today)) return { error: 'valid_from', message: 'Başlangıç tarihi en fazla bir yıl ileride olabilir.' };
  const until = validUntil ?? addOneYear(from);
  if (!isIsoDate(until)) return { error: 'valid_until', message: 'Bitiş tarihi geçersiz.' };
  if (until < from) return { error: 'valid_until', message: 'Bitiş tarihi başlangıçtan önce olamaz.' };
  if (until > addOneYear(from)) return { error: 'valid_until', message: 'Vekalet en fazla bir yıl geçerli olabilir.' };
  return { valid_from: from, valid_until: until };
}

/** Vekalet o gun gecerli mi (iptal edilmemis, pencere icinde). `today` ISO tarih. */
export function proxyIsActive(proxy, today) {
  if (!proxy || proxy.revoked_at) return false;
  const from = typeof proxy.valid_from === 'string' ? proxy.valid_from.slice(0, 10) : null;
  const until = typeof proxy.valid_until === 'string' ? proxy.valid_until.slice(0, 10) : null;
  return Boolean(from && until && from <= today && today <= until);
}

/** "Ali Yilmaz" -> "Ali Y."; tek sozcukte ad aynen. */
export function shortName(fullName) {
  const parts = String(fullName ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '';
  if (parts.length === 1) return parts[0];
  const last = Array.from(parts[parts.length - 1])[0] ?? '';
  return `${parts.slice(0, -1).join(' ')} ${last.toLocaleUpperCase('tr-TR')}.`;
}

/**
 * Imza hakki sahibi: aktif `toplanti_imza` vekili (vekilin hala kiraci/sakin olmasi cagiran tarafindan `proxy.holder_ok` ile bildirilir)
 * varsa vekil, yoksa malik. Ayni daire icin TEK kisi doner.
 * @param {{ owner: {person_id:number,name:string}|null, proxies: Array<object>, today: string }} input
 */
export function pickSigningHolder({ owner, proxies, today }) {
  const active = (proxies ?? []).filter((p) => p.scope === 'toplanti_imza' && p.holder_ok !== false && proxyIsActive(p, today));
  // Tekillik DB'de (uq_apartment_proxies_open); yine de belirleyici olsun: en son baslayan.
  active.sort((a, b) => String(b.valid_from).localeCompare(String(a.valid_from)) || Number(b.id ?? 0) - Number(a.id ?? 0));
  const proxy = active[0] ?? null;
  if (proxy) {
    return { kind: 'proxy', person_id: proxy.proxy_person_id, name: proxy.proxy_name ?? '', valid_until: String(proxy.valid_until).slice(0, 10), owner_name: owner?.name ?? '' };
  }
  if (owner) {
    return { kind: 'owner', person_id: owner.person_id, name: owner.name ?? '', valid_until: null, owner_name: owner.name ?? '' };
  }
  return { kind: 'none', person_id: null, name: '', valid_until: null, owner_name: '' };
}

/** Katilim / imza satiri metni: "Daire 5 - vekil: Ali Y. (malik: Veli K.)" ya da "Daire 5 - malik: Veli K.". */
export function signingLabel(apartmentLabel, holder) {
  const label = String(apartmentLabel ?? '').trim();
  if (holder.kind === 'proxy') return `${label} - vekil: ${shortName(holder.name)} (malik: ${shortName(holder.owner_name)})`;
  if (holder.kind === 'owner') return `${label} - malik: ${shortName(holder.name)}`;
  return `${label} - malik kaydı yok`;
}

// ---------------------------------------------------------------------------
// Kisi arama gizliligi
// ---------------------------------------------------------------------------

/** "Ahmet Yilmaz" -> "Ahmet Y***"; tek sozcuk "Ahmet" -> "Ah***". */
export function maskName(fullName) {
  const parts = String(fullName ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '***';
  if (parts.length === 1) return `${Array.from(parts[0]).slice(0, 2).join('')}***`;
  const first = parts.slice(0, -1).join(' ');
  const initial = Array.from(parts[parts.length - 1])[0] ?? '';
  return `${first} ${initial.toLocaleUpperCase('tr-TR')}***`;
}

/** "ahmet.yilmaz@gmail.com" -> "ah***@gmail.com". */
export function maskEmail(email) {
  const text = String(email ?? '').trim();
  const at = text.lastIndexOf('@');
  if (at < 1) return '***';
  const local = Array.from(text.slice(0, at)).slice(0, 2).join('');
  return `${local}***${text.slice(at)}`;
}

/** Arama metni: kirpilir, bosluklar tekillestirilir; kisa ise null. */
export function normalizeSearchQuery(value) {
  // eslint-disable-next-line no-control-regex
  const text = String(value ?? '').replace(/[\x00-\x1f\x7f]/g, ' ').replace(/\s+/g, ' ').trim();
  return Array.from(text).length >= SEARCH_MIN_CHARS && text.length <= 100 ? text : null;
}

/** Arama sonucu secim belirteci: HMAC imzali, ararin kullanicisina ve hedefe bagli, kisa omurlu. */
export function signCandidateHandle(secret, searcherUserCode, targetUserCode, now = Date.now()) {
  const exp = now + CANDIDATE_TTL_MS;
  const body = `${asCode(searcherUserCode)}.${asCode(targetUserCode)}.${exp}`;
  const mac = crypto.createHmac('sha256', String(secret)).update(`apt-candidate:${body}`).digest('base64url');
  return Buffer.from(`${body}.${mac}`).toString('base64url');
}

/** Belirteci dogrular; gecerliyse hedef kullanici kodunu, degilse null dondurur. */
export function verifyCandidateHandle(secret, searcherUserCode, handle, now = Date.now()) {
  if (typeof handle !== 'string' || handle.length < 10 || handle.length > 300) return null;
  let decoded;
  try {
    decoded = Buffer.from(handle, 'base64url').toString('utf8');
  } catch {
    return null;
  }
  const parts = decoded.split('.');
  if (parts.length !== 4) return null;
  const [searcher, target, exp, mac] = parts;
  if (asCode(searcher) !== asCode(searcherUserCode) || asCode(target) === null) return null;
  if (!/^\d{1,16}$/.test(exp) || Number(exp) < now) return null;
  const expected = crypto.createHmac('sha256', String(secret)).update(`apt-candidate:${searcher}.${target}.${exp}`).digest('base64url');
  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  return asCode(target);
}

/** Kiraci cikisinda bitecek aile uyeleri: yalniz ekleyeni (sponsor) kiraci olanlar. Malikin / sponsorsuz aile KALIR. */
export function familyEndingWithTenant(family, tenantPersonId) {
  const tid = asCode(tenantPersonId);
  if (tid === null) return [];
  return family.filter((r) => asCode(r.sponsor_person_id) === tid);
}

/** Aile uyesini kimler yonetebilir: admin ya da o kaydi ekleyen (sponsor) kisi. */
export function canManageFamilyMember({ isAdmin, actorPersonId, residency }) {
  if (isAdmin) return true;
  return asCode(actorPersonId) !== null && asCode(residency?.sponsor_person_id) === asCode(actorPersonId);
}

// ---------------------------------------------------------------------------
// Kisi arama: tam eslesme / gorunurluk ayari
// ---------------------------------------------------------------------------

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Arama metninin turu. E-posta ve telefon YALNIZ TAM ESLESME ile aranir; ad-soyad bulanik aramasi yalniz "Beni aramalarda goster"i
 * acmis kisileri doner. @returns {{ kind: 'email'|'phone'|'name', value: string }}
 */
export function classifySearchQuery(q) {
  const text = String(q ?? '').trim();
  if (EMAIL_SHAPE.test(text)) return { kind: 'email', value: text.toLowerCase() };
  const digits = text.replace(/\D/g, '');
  if (digits.length >= 10 && /^[+\d\s()\-.]+$/.test(text)) return { kind: 'phone', value: digits.slice(-10) };
  return { kind: 'name', value: text };
}

/** Denetim kaydi icin MASKELI arama metni (ne arandigi anlasilir, tam deger saklanmaz). */
export function maskSearchQuery(q) {
  const { kind, value } = classifySearchQuery(q);
  if (kind === 'email') return maskEmail(value);
  if (kind === 'phone') return `+90 *** *** ** ${value.slice(-2)}`;
  return `${Array.from(value).slice(0, 2).join('')}***`;
}

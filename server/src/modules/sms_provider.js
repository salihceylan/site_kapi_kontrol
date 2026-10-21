// SMS saglayici arayuzu (adaptor deseni). Ilk adaptor: Netgsm. Anahtar yoksa saglayici YOK (null) -> SMS ozellikleri kapali.
//   SMS_PROVIDER=netgsm  NETGSM_USERCODE  NETGSM_PASSWORD  NETGSM_HEADER (onayli mesaj basligi)
// Adaptor sozlesmesi: { name, send(phoneE164, text) -> Promise<{ ok, code }> }. Mesaj metni/telefon GUNLUGE yazilmaz.

const FETCH_TIMEOUT_MS = 10_000;
const rawOf = (env, name) => String(env?.[name] ?? '').trim();

/** Netgsm HTTP GET adaptoru (yanit "00 <jobid>" ise basarili). */
export function createNetgsmAdapter({ usercode, password, header, fetchImpl = fetch }) {
  return {
    name: 'netgsm',
    async send(phone, text) {
      const gsm = String(phone).replace(/\D/g, '').replace(/^90/, '');
      const params = new URLSearchParams({ usercode, password, gsmno: gsm, message: text, msgheader: header, dil: 'TR' });
      const response = await fetchImpl(`https://api.netgsm.com.tr/sms/send/get?${params.toString()}`, {
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      });
      const body = (await response.text()).trim();
      const code = body.split(/\s+/)[0] || 'EMPTY';
      return { ok: response.ok && (code === '00' || code === '01' || code === '02'), code };
    },
  };
}

const ADAPTERS = Object.freeze({
  netgsm: (env) => {
    const usercode = rawOf(env, 'NETGSM_USERCODE');
    const password = rawOf(env, 'NETGSM_PASSWORD');
    const header = rawOf(env, 'NETGSM_HEADER');
    return usercode && password && header ? createNetgsmAdapter({ usercode, password, header }) : null;
  },
});

/** Yapilandirilmis saglayici ya da null (kapali). */
export function getSmsProvider(env = process.env) {
  const factory = ADAPTERS[rawOf(env, 'SMS_PROVIDER').toLowerCase()];
  return factory ? factory(env) : null;
}

export const isSmsEnabled = (env = process.env) => getSmsProvider(env) !== null;

/** Test icin degistirilebilir. */
export const smsHooks = { provider: () => getSmsProvider() };

// Odeme ve Kamera (kart odemesi: Aidat ve Finans temel modulu "finance"; kamera: plate_cameras modulu): odeme saglayici bilgisi (sahte/kapali), kamera cihazlari, ~100 plaka olayi.
// Gercek sir/anahtar YAZILMAZ: kamera parolasi acik sahte bir metindir ve uygulamanin kendi islemiyle sifrelenir; yerel IP'ler ozel aralikta.

import { addDays } from '../lib/util.mjs';
import { fakePlate } from '../lib/identity.mjs';

export async function seedDevices(ctx) {
  const { q, rng, site, manager, peopleResult, TODAY } = ctx;
  const siteCode = site.code;
  const out = { providers: 0, cameras: 0, plateEvents: 0, skipped: [] };
  const mod = await ctx.importServer('src/modules/device_integrations_service.js');

  if (ctx.enabled.finance) {
    for (const provider of ['iyzico', 'paytr']) {
      await mod.savePaymentProviderInfo({
        siteCode, provider, userCode: manager.user_code,
        body: { commission_info: 'DEMO: sağlayıcı bağlı değil, gerçek komisyon bilgisi yoktur (sahte veri).' },
      });
      out.providers += 1;
    }
  } else {
    out.skipped.push('finance kapali');
  }

  if (ctx.enabled.plate_cameras) {
    const specs = [
      { brand: 'hikvision', name: 'Giriş Kapısı Plaka Kamerası', host: '192.168.1.64', port: 80 },
      { brand: 'tiandy', name: 'Otopark Çıkış Kamerası', host: '192.168.1.65', port: 80 },
      { brand: 'onvif', name: 'Bariyer Kamerası', host: '192.168.1.66', port: 8080 },
    ];
    const cameras = [];
    for (const s of specs) {
      const created = await mod.createCamera({ siteCode, userCode: manager.user_code, body: { ...s, username: 'demo_kamera', password: 'SahteDemoSifre-123' } });
      cameras.push(Number(created.camera.id));
      out.cameras += 1;
    }
    const vehicles = peopleResult.vehicles;
    for (let i = 0; i < 104; i += 1) {
      const deviceId = cameras[i % cameras.length];
      const day = addDays(TODAY, -rng.int(0, 60));
      const seen = `${day}T${String(rng.int(6, 23)).padStart(2, '0')}:${String(rng.int(0, 59)).padStart(2, '0')}:${String(rng.int(0, 59)).padStart(2, '0')}+03:00`;
      let plate;
      let matched = false;
      let vehicleId = null;
      const roll = rng.next();
      if (roll < 0.62 && vehicles.length) {
        const v = rng.pick(vehicles);
        plate = v.plate;
        matched = true;
        vehicleId = v.id;
      } else if (roll < 0.9) {
        plate = fakePlate(rng).normalized; // kayitli olmayan (yetkisiz) arac
      } else {
        const v = vehicles.length ? rng.pick(vehicles).plate : fakePlate(rng).normalized;
        plate = v.length > 5 ? v.slice(0, v.length - 1) : v; // eksik okunan (tanimsiz) plaka
        plate = plate.replace(/[0O]/, 'Q').replace(/[^A-Z0-9]/g, '').padEnd(5, 'X').slice(0, 10);
      }
      await q(`INSERT INTO plate_events (site_code, device_id, plate, matched, vehicle_id, seen_at, created_at) VALUES ($1, $2, $3, $4, $5, $6::timestamptz, $6::timestamptz)`, [siteCode, deviceId, plate, matched, vehicleId, seen]);
      out.plateEvents += 1;
    }
    await q(`UPDATE camera_devices SET last_event_at = (SELECT MAX(seen_at) FROM plate_events WHERE device_id = camera_devices.id) WHERE site_code = $1`, [siteCode]);
  } else {
    out.skipped.push('plate_cameras kapali');
  }
  return out;
}

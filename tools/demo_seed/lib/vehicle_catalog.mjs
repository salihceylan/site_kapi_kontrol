// Demo arac katalogu: Turkiye'de yaygin marka / model / renk. Arac notu "<Renk> <Marka> <Model>" biciminde yazilir (ornek: "Beyaz Renault Clio").
// Marka-model agirliklari yaklasik pazar payidir (Fiat Egea, Renault Clio, VW, Toyota, Hyundai, Dacia, Skoda...). Hepsi SAHTE demo verisidir.

/** [marka, model, agirlik] */
export const CAR_MODELS = [
  ['Renault', 'Clio', 8], ['Renault', 'Megane', 4], ['Renault', 'Taliant', 3], ['Renault', 'Captur', 2], ['Renault', 'Austral', 1],
  ['Fiat', 'Egea', 9], ['Fiat', 'Egea Cross', 3], ['Fiat', 'Doblo', 3], ['Fiat', 'Linea', 2], ['Fiat', '500', 1],
  ['Volkswagen', 'Passat', 4], ['Volkswagen', 'Golf', 4], ['Volkswagen', 'Polo', 4], ['Volkswagen', 'Tiguan', 3], ['Volkswagen', 'T-Roc', 2], ['Volkswagen', 'Caddy', 2],
  ['Toyota', 'Corolla', 5], ['Toyota', 'Yaris', 3], ['Toyota', 'C-HR', 3],
  ['Hyundai', 'i20', 4], ['Hyundai', 'Bayon', 2], ['Hyundai', 'Tucson', 3], ['Hyundai', 'Elantra', 2], ['Hyundai', 'i10', 1],
  ['Dacia', 'Duster', 4], ['Dacia', 'Sandero', 3], ['Dacia', 'Jogger', 2], ['Dacia', 'Lodgy', 1],
  ['Ford', 'Focus', 3], ['Ford', 'Fiesta', 2], ['Ford', 'Puma', 2], ['Ford', 'Kuga', 2], ['Ford', 'Courier', 1],
  ['Peugeot', '208', 3], ['Peugeot', '301', 2], ['Peugeot', '2008', 2], ['Peugeot', '3008', 2], ['Peugeot', 'Rifter', 1],
  ['Opel', 'Astra', 3], ['Opel', 'Corsa', 3], ['Opel', 'Mokka', 2], ['Opel', 'Insignia', 1],
  ['Honda', 'Civic', 3], ['Honda', 'CR-V', 1], ['Honda', 'HR-V', 1],
  ['Skoda', 'Octavia', 4], ['Skoda', 'Superb', 2], ['Skoda', 'Fabia', 2], ['Skoda', 'Kamiq', 2], ['Skoda', 'Karoq', 1], ['Skoda', 'Scala', 2],
  ['Seat', 'Leon', 2], ['Citroen', 'C3', 2], ['Citroen', 'C4', 1], ['Citroen', 'C-Elysee', 2], ['Citroen', 'Berlingo', 1],
  ['Nissan', 'Qashqai', 3], ['Nissan', 'Juke', 2], ['Kia', 'Sportage', 2], ['Kia', 'Ceed', 1], ['Kia', 'Rio', 1], ['Kia', 'Picanto', 1],
  ['BMW', '3 Serisi', 2], ['BMW', '5 Serisi', 1], ['BMW', 'X1', 1],
  ['Mercedes-Benz', 'C 180', 2], ['Mercedes-Benz', 'A 180', 1], ['Mercedes-Benz', 'E 200', 1], ['Mercedes-Benz', 'CLA', 1],
  ['Audi', 'A3', 2], ['Audi', 'A4', 1], ['Audi', 'Q3', 1],
  ['Togg', 'T10X', 2], ['Suzuki', 'Vitara', 1], ['Suzuki', 'Swift', 1], ['Mazda', 'CX-5', 1], ['Volvo', 'XC40', 1],
];

/** [renk, agirlik] */
export const CAR_COLORS = [
  ['Beyaz', 30], ['Gri', 20], ['Siyah', 17], ['Gümüş gri', 8], ['Lacivert', 6], ['Kırmızı', 6], ['Mavi', 4], ['Bordo', 3], ['Füme', 3], ['Kahverengi', 1], ['Yeşil', 1], ['Turuncu', 1],
];

/**
 * Cesitli bir arac secer: ayni renk+marka+model ikinci kez cikmaz; ayni model, secenek varken `maxPerModel` kereden fazla cikmaz.
 * @param {object} rng util.makeRng() ciktisi
 * @param {Map<string, number>} used "marka model" -> adet; Map EKLENIR
 * @param {Set<string>} usedFull "renk marka model"; Set EKLENIR
 */
export function pickCar(rng, used = new Map(), usedFull = new Set(), maxPerModel = 2) {
  for (let attempt = 0; attempt < 400; attempt += 1) {
    const [brand, model] = rng.weighted(CAR_MODELS.map((m) => [[m[0], m[1]], m[2]]));
    const color = rng.weighted(CAR_COLORS);
    const key = `${brand} ${model}`;
    const full = `${color} ${key}`;
    if (usedFull.has(full)) continue;
    if ((used.get(key) ?? 0) >= maxPerModel && attempt < 300) continue;
    used.set(key, (used.get(key) ?? 0) + 1);
    usedFull.add(full);
    return { brand, model, color, note: full };
  }
  // cok kalabalik bir site: tekrar kabul
  const [brand, model] = rng.weighted(CAR_MODELS.map((m) => [[m[0], m[1]], m[2]]));
  const color = rng.weighted(CAR_COLORS);
  return { brand, model, color, note: `${color} ${brand} ${model}` };
}

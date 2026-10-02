// Gelistirme betikleri (apply_*.js, check_*.js, test_*.js) gercek veritabanina/brokera dokunabilir.
// Bu modul betiklerde ILK import olarak yer alir; ALLOW_DEV_SCRIPTS=1 yoksa betik hicbir sey yapmadan cikar.
if (process.env.ALLOW_DEV_SCRIPTS !== '1') {
  console.error(
    'Bu gelistirme betigi gercek veritabanina dokunabilir. Bilerek calistirmak icin ALLOW_DEV_SCRIPTS=1 ayarlayin.',
  );
  process.exit(1);
}

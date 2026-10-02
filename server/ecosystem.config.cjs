// PM2 surec tanimi (kapi-api).
//
// Dosya uzantisi .cjs: server/package.json "type": "module" oldugu icin
// ".js" uzantili bir ecosystem dosyasi ESM sayilir ve PM2'nin require()'i ile
// yuklenemez ("module is not defined in ES module scope").
//
// Ilk gecis (mevcut surec "pm2 start npm --name kapi-api -- run start" ile baslatildiysa):
//   cd /var/www/site_kapi_kontrol/server
//   pm2 delete kapi-api
//   pm2 start ecosystem.config.cjs
//   pm2 save
// Sonraki guncellemelerde:
//   pm2 reload ecosystem.config.cjs --update-env   (veya: pm2 restart kapi-api --update-env)
//
// Gizli degerler BURAYA yazilmaz; server/.env dosyasindan dotenv ile okunur
// (cwd = bu klasor oldugu icin .env bulunur).
module.exports = {
  apps: [
    {
      name: 'kapi-api',
      script: 'src/server.js',
      cwd: __dirname,

      // Tek kopya: MQTT koprusu ve bellek ici sayaclar/rate limiter'lar
      // birden fazla kopyada tutarsiz calisir; cluster moduna GECME.
      instances: 1,
      exec_mode: 'fork',

      env: {
        NODE_ENV: 'production',
      },

      // Kararlilik
      autorestart: true,
      watch: false,
      max_memory_restart: '400M',
      exp_backoff_restart_delay: 200,
      min_uptime: '15s',
      max_restarts: 30,
      // server.js duzgun kapanma suresi (SHUTDOWN_GRACE_MS=8000) + pay: PM2 SIGKILL'i bundan SONRA gondermeli.
      kill_timeout: 10000,

      // Log
      time: true,
      merge_logs: true,
    },
  ],
};

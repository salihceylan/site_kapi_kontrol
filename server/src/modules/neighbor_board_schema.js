// Komşu panosu şeması: 064. migrations/064_neighbor_board.sql ile AYNI ifadeler, AYNI sırayla (test: neighbor_board_schema).
// Yeni tablolar (ekleyici); mevcut tablolara dokunulmaz. Tablolar varsa hiçbir ifade gönderilmez (kilit alınmaz). db.js'i İÇE AKTARMAZ.

export const NEIGHBOR_BOARD_DDL = Object.freeze({
  postsTable: `
    CREATE TABLE IF NOT EXISTS neighbor_posts (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
      author_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      decision_note TEXT,
      decided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
      decided_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_neighbor_posts_status CHECK (status IN ('pending', 'published', 'rejected', 'removed', 'withdrawn')),
      CONSTRAINT chk_neighbor_posts_title CHECK (char_length(title) BETWEEN 3 AND 120),
      CONSTRAINT chk_neighbor_posts_body CHECK (char_length(body) BETWEEN 3 AND 2000),
      CONSTRAINT chk_neighbor_posts_note CHECK (decision_note IS NULL OR char_length(decision_note) <= 300)
    )
  `,
  siteStatusIndex: `CREATE INDEX IF NOT EXISTS idx_neighbor_posts_site_status ON neighbor_posts (site_code, status, id DESC)`,
  authorIndex: `CREATE INDEX IF NOT EXISTS idx_neighbor_posts_author ON neighbor_posts (author_user_code, id DESC) WHERE author_user_code IS NOT NULL`,
  reportsTable: `
    CREATE TABLE IF NOT EXISTS neighbor_post_reports (
      id BIGSERIAL PRIMARY KEY,
      post_id BIGINT NOT NULL REFERENCES neighbor_posts(id) ON DELETE CASCADE,
      reporter_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
      reason TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_neighbor_post_reports_reason CHECK (char_length(reason) BETWEEN 1 AND 200)
    )
  `,
  reportsOnceIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_neighbor_post_reports_once ON neighbor_post_reports (post_id, reporter_user_code) WHERE reporter_user_code IS NOT NULL`,
});

export async function ensureNeighborBoardSchema(client) {
  const found = await client.query(
    `SELECT to_regclass('public.neighbor_posts') IS NOT NULL AS posts, to_regclass('public.neighbor_post_reports') IS NOT NULL AS reports`,
  );
  if (found.rows[0]?.posts && found.rows[0]?.reports) {
    return;
  }
  await client.query("SET lock_timeout = '5s'");
  try {
    for (const sql of Object.values(NEIGHBOR_BOARD_DDL)) {
      await client.query(sql);
    }
  } finally {
    await client.query('RESET lock_timeout');
  }
}

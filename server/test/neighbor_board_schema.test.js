import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NEIGHBOR_BOARD_DDL } from '../src/modules/neighbor_board_schema.js';

const norm = (s) => s.replace(/--.*$/gm, '').replace(/\s+/g, ' ').replace(/ ?\( ?/g, '(').replace(/ ?\) ?/g, ')').replace(/ ?, ?/g, ',').trim();
const migration = readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations', '064_neighbor_board.sql'), 'utf8');

describe('064 komsu panosu DDL', () => {
  it('her db.js ifadesi migration icinde birebir bulunur ve idempotenttir', () => {
    const all = norm(migration);
    for (const [name, sql] of Object.entries(NEIGHBOR_BOARD_DDL)) {
      assert.match(sql, /IF NOT EXISTS/, name);
      assert.ok(all.includes(norm(sql)), `${name} migration ile ayni degil`);
    }
  });
});

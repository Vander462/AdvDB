import { Pool } from 'pg';

// One shared connection pool (reused across hot reloads in dev)
const pool =
  globalThis._pgPool ||
  new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 5,
    connectionTimeoutMillis: 15000,
    keepAlive: true,
  });
globalThis._pgPool = pool;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Only retry failures where the query never reached the server (connect/timeout),
// never query errors — CALL sp_* writes must not be applied twice.
const isConnError = (e) =>
  e.code?.startsWith('08') ||
  ['ECONNRESET', 'ETIMEDOUT', 'EPIPE', 'ENOTFOUND', 'EAI_AGAIN'].includes(e.code) ||
  /connection|timeout|terminated|ECONN/i.test(e.message || '');

export async function query(sql, params = []) {
  // Neon free-tier computes suspend when idle; the first query after wake-up
  // can fail or take a while, so retry once before giving up.
  for (let attempt = 0; ; attempt++) {
    try {
      const res = await pool.query(sql, params);
      return res.rows;
    } catch (e) {
      if (attempt >= 2 || !isConnError(e)) throw e;
      await sleep(1000 * (attempt + 1));
    }
  }
}

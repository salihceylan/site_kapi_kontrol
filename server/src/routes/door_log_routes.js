import express from 'express';
import { pool } from '../db.js';
import { authRequired, requireSuperUser, requireSiteManager } from '../middlewares/auth_middleware.js';
import { mapDoorAccessLogRow } from '../utils/helpers.js';

export const doorLogRouter = express.Router();

async function getManagedSiteCodes(authUser) {
  if (!authUser) return new Set();
  if (authUser.role === 'super_user') {
    const res = await pool.query('SELECT site_code FROM sites');
    return new Set(res.rows.map(r => Number(r.site_code)));
  }
  const res = await pool.query(
    'SELECT site_code FROM site_manager_sites WHERE manager_user_code = $1',
    [Number(authUser.id)]
  );
  return new Set(res.rows.map(r => Number(r.site_code)));
}

// GET /admin/door-logs
doorLogRouter.get('/admin/door-logs', authRequired, requireSuperUser, async (req, res) => {
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(200, Math.max(1, Number(req.query.page_size || 50)));
  const offset = (page - 1) * pageSize;
  const siteCode = req.query.site_code ? Number(req.query.site_code) : null;
  const doorId = req.query.door_id ? Number(req.query.door_id) : null;
  const search = req.query.search ? String(req.query.search).trim() : null;
  const startDate = req.query.start_date ? new Date(req.query.start_date) : null;
  const endDate = req.query.end_date ? new Date(req.query.end_date) : null;

  try {
    const conditions = [];
    const params = [];

    if (siteCode && Number.isInteger(siteCode)) {
      params.push(siteCode);
      conditions.push(`l.site_code = $${params.length}`);
    }
    if (doorId && Number.isInteger(doorId)) {
      params.push(doorId);
      conditions.push(`l.door_id = $${params.length}`);
    }
    if (startDate && !isNaN(startDate.getTime())) {
      params.push(startDate);
      conditions.push(`l.opened_at >= $${params.length}`);
    }
    if (endDate && !isNaN(endDate.getTime())) {
      params.push(endDate);
      conditions.push(`l.opened_at <= $${params.length}`);
    }
    if (search) {
      params.push(`%${search}%`);
      conditions.push(`(l.user_name ILIKE $${params.length} OR l.door_name ILIKE $${params.length} OR l.apartment_label ILIKE $${params.length} OR s.name ILIKE $${params.length})`);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const countResult = await pool.query(
      `
        SELECT COUNT(*) AS total
        FROM door_access_logs l
        JOIN sites s ON s.site_code = l.site_code
        ${whereClause}
      `,
      params,
    );
    const total = Number(countResult.rows[0]?.total || 0);

    const listParams = [...params, pageSize, offset];
    const listResult = await pool.query(
      `
        SELECT
          l.*,
          s.name AS site_name
        FROM door_access_logs l
        JOIN sites s ON s.site_code = l.site_code
        ${whereClause}
        ORDER BY l.opened_at DESC
        LIMIT $${listParams.length - 1} OFFSET $${listParams.length}
      `,
      listParams,
    );

    return res.status(200).json({
      ok: true,
      logs: listResult.rows.map(mapDoorAccessLogRow),
      total,
      page,
      page_size: pageSize,
      total_pages: Math.ceil(total / pageSize) || 1,
    });
  } catch (error) {
    console.error('Error fetching admin door logs:', error);
    return res.status(500).json({ error: 'Kapi loglari alinamadi.' });
  }
});

// GET /manager/door-logs
doorLogRouter.get('/manager/door-logs', authRequired, requireSiteManager, async (req, res) => {
  const page = Math.max(1, Number(req.query.page || 1));
  const pageSize = Math.min(200, Math.max(1, Number(req.query.page_size || 50)));
  const offset = (page - 1) * pageSize;
  const siteCode = req.query.site_code ? Number(req.query.site_code) : null;
  const doorId = req.query.door_id ? Number(req.query.door_id) : null;
  const search = req.query.search ? String(req.query.search).trim() : null;
  const startDate = req.query.start_date ? new Date(req.query.start_date) : null;
  const endDate = req.query.end_date ? new Date(req.query.end_date) : null;

  try {
    const managedSiteSet = await getManagedSiteCodes(req.authUser);
    if (!managedSiteSet || managedSiteSet.size === 0) {
      return res.status(200).json({
        ok: true,
        logs: [],
        total: 0,
        page: 1,
        page_size: pageSize,
        total_pages: 1,
      });
    }

    const managedSiteCodes = Array.from(managedSiteSet);
    const conditions = [];
    const params = [managedSiteCodes];
    conditions.push(`l.site_code = ANY($1)`);

    if (siteCode && Number.isInteger(siteCode)) {
      if (!managedSiteSet.has(siteCode)) {
        return res.status(403).json({ error: 'Bu sitenin loglarini gorme yetkiniz yok.' });
      }
      params.push(siteCode);
      conditions.push(`l.site_code = $${params.length}`);
    }
    if (doorId && Number.isInteger(doorId)) {
      params.push(doorId);
      conditions.push(`l.door_id = $${params.length}`);
    }
    if (startDate && !isNaN(startDate.getTime())) {
      params.push(startDate);
      conditions.push(`l.opened_at >= $${params.length}`);
    }
    if (endDate && !isNaN(endDate.getTime())) {
      params.push(endDate);
      conditions.push(`l.opened_at <= $${params.length}`);
    }
    if (search) {
      params.push(`%${search}%`);
      conditions.push(`(l.user_name ILIKE $${params.length} OR l.door_name ILIKE $${params.length} OR l.apartment_label ILIKE $${params.length} OR s.name ILIKE $${params.length})`);
    }

    const whereClause = `WHERE ${conditions.join(' AND ')}`;

    const countResult = await pool.query(
      `
        SELECT COUNT(*) AS total
        FROM door_access_logs l
        JOIN sites s ON s.site_code = l.site_code
        ${whereClause}
      `,
      params,
    );
    const total = Number(countResult.rows[0]?.total || 0);

    const listParams = [...params, pageSize, offset];
    const listResult = await pool.query(
      `
        SELECT
          l.*,
          s.name AS site_name
        FROM door_access_logs l
        JOIN sites s ON s.site_code = l.site_code
        ${whereClause}
        ORDER BY l.opened_at DESC
        LIMIT $${listParams.length - 1} OFFSET $${listParams.length}
      `,
      listParams,
    );

    return res.status(200).json({
      ok: true,
      logs: listResult.rows.map(mapDoorAccessLogRow),
      total,
      page,
      page_size: pageSize,
      total_pages: Math.ceil(total / pageSize) || 1,
    });
  } catch (error) {
    console.error('Error fetching manager door logs:', error);
    return res.status(500).json({ error: 'Kapi loglari alinamadi.' });
  }
});

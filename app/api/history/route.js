import { query } from '@/lib/db';
import { getActor } from '@/lib/users';

export const dynamic = 'force-dynamic';

// GET /api/history?id=12  -> rows from the view v_request_history
export async function GET(req) {
  try {
    const p = new URL(req.url).searchParams;
    const id = p.get('id');
    const role = p.get('role');
    if (!['admin', 'technician', 'requester'].includes(role)) {
      return Response.json({ error: 'Choose a valid demo role.' }, { status: 400 });
    }
    const actor = await getActor(role, p.get('user_id'));
    const rows = await query(
      `SELECT h.* FROM v_request_history h
        JOIN maintenance_request m ON m.request_id = h.request_id
       WHERE h.request_id = $1
         AND ($2 = 'admin'
              OR ($2 = 'requester' AND m.requester_id = $3)
              OR ($2 = 'technician' AND m.personnel_id = $4))
       ORDER BY h.changed_at, h.history_id`,
      [id, role, actor.requester_id || null, actor.personnel_id || null]);
    return Response.json(rows);
  } catch (e) {
    return Response.json({ error: e.message }, { status: 500 });
  }
}

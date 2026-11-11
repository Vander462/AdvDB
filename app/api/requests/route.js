import { query } from '@/lib/db';
import { getActor } from '@/lib/users';

export const dynamic = 'force-dynamic';

// GET /api/requests?role=admin|technician|requester&q=&status=&category=&priority=
// Reads from the view v_request_details.
export async function GET(req) {
  try {
    const p = new URL(req.url).searchParams;
    const role = p.get('role');
    if (!['admin', 'technician', 'requester'].includes(role)) {
      return Response.json({ error: 'Choose a valid demo role.' }, { status: 400 });
    }
    const actor = await getActor(role, p.get('user_id'));

    const where = [];
    const params = [];
    const add = (cond, value) => { params.push(value); where.push(cond.replace('?', '$' + params.length)); };

    if (role === 'technician') add('personnel_id = ?', actor.personnel_id);
    if (role === 'requester') add('requester_id = ?', actor.requester_id);

    // Search: matches id, title, description, room, building, requester or technician
    const q = (p.get('q') || '').trim();
    if (q) {
      params.push('%' + q + '%', q);
      const i = '$' + (params.length - 1);  // the %q% pattern
      const j = '$' + params.length;        // exact text, for the id
      where.push(`(request_id::text = ${j} OR title ILIKE ${i} OR description ILIKE ${i}
                   OR room_no ILIKE ${i} OR building ILIKE ${i} OR requester_name ILIKE ${i}
                   OR technician_name ILIKE ${i})`);
    }
    if (p.get('status')) add('status_name = ?', p.get('status'));
    if (p.get('category')) add('category_id = ?', p.get('category'));
    if (p.get('priority')) add('priority_name = ?', p.get('priority'));

    const rows = await query(
      `SELECT * FROM v_request_details
       ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
       ORDER BY request_id DESC`, params);
    return Response.json(rows);
  } catch (e) {
    return Response.json({ error: e.message }, { status: 500 });
  }
}

import { query } from '@/lib/db';

export const dynamic = 'force-dynamic';

// GET /api/technicians?category_id=3 -> fn_team_technicians (least busy first)
export async function GET(req) {
  try {
    const id = new URL(req.url).searchParams.get('category_id');
    return Response.json(await query(`SELECT * FROM fn_team_technicians($1)`, [id]));
  } catch (e) {
    return Response.json({ error: e.message }, { status: 500 });
  }
}

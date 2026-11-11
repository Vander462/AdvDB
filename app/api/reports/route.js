import { query } from '@/lib/db';
import { getActor } from '@/lib/users';

export const dynamic = 'force-dynamic';

export async function GET(req) {
  try {
    const userId = new URL(req.url).searchParams.get('user_id');
    await getActor('admin', userId);
    const [categories, teams, workload] = await Promise.all([
      query(`SELECT * FROM v_category_summary ORDER BY total DESC, category_name`),
      query(`SELECT * FROM v_team_summary ORDER BY team_name`),
      query(`SELECT * FROM v_technician_workload ORDER BY team_name, technician_name`),
    ]);
    return Response.json({ categories, teams, workload });
  } catch (e) {
    return Response.json({ error: e.message }, { status: 500 });
  }
}

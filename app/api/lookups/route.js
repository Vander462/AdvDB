import { query } from '@/lib/db';
import { getUsers } from '@/lib/users';

export const dynamic = 'force-dynamic';

// Dropdown data + who each tab is acting as
export async function GET() {
  try {
    const [users, statuses, categories, priorities, locations] = await Promise.all([
      getUsers(),
      query(`SELECT status_id, status_name FROM status WHERE is_active ORDER BY status_id`),
      query(`SELECT c.category_id, c.category_name, t.team_name
               FROM category c JOIN maintenance_team t ON t.team_id = c.team_id
              WHERE c.is_active ORDER BY c.category_name`),
      query(`SELECT priority_id, priority_name FROM priority WHERE is_active ORDER BY sort_rank`),
      query(`SELECT location_id, building, floor, room_no FROM location ORDER BY building, floor, room_no`),
    ]);
    return Response.json({ users, statuses, categories, priorities, locations });
  } catch (e) {
    return Response.json({ error: e.message }, { status: 500 });
  }
}

import { query } from '@/lib/db';
import { getActor } from '@/lib/users';

export const dynamic = 'force-dynamic';

// POST /api/action  { action, ...fields }
// Every change goes through a stored procedure; the procedure checks the rules
// and the trigger writes the status history.
export async function POST(req) {
  try {
    const b = await req.json();
    switch (b.action) {
      case 'submit': {
        const requester = await getActor('requester', b.actor_user_id);
        await query(`CALL sp_submit_request($1, $2, $3, $4, $5, $6)`,
          [requester.requester_id, b.title, b.description, b.category_id, b.priority_id, b.location_id]);
        break;
      }
      case 'assign': {
        const admin = await getActor('admin', b.actor_user_id);
        await query(`CALL sp_assign_request($1, $2, $3)`,
          [b.request_id, b.personnel_id, admin.user_id]);
        break;
      }
      case 'priority': {
        const admin = await getActor('admin', b.actor_user_id);
        await query(`CALL sp_set_priority($1::bigint, $2::bigint, $3::bigint)`,
          [b.request_id, b.priority_id, admin.user_id]);
        break;
      }
      case 'status': {
        const technician = await getActor('technician', b.actor_user_id);
        await query(`CALL sp_update_status($1, $2, $3, $4)`,
          [b.request_id, technician.personnel_id, b.new_status, b.remarks || null]);
        break;
      }
      case 'complete': {
        const technician = await getActor('technician', b.actor_user_id);
        await query(`CALL sp_complete_request($1, $2, $3, $4)`,
          [b.request_id, technician.personnel_id, b.repair_details, b.notes || null]);
        break;
      }
      case 'cancel': {
        const role = b.as === 'admin' ? 'admin' : 'requester';
        const actor = await getActor(role, b.actor_user_id);
        const userId = actor.user_id;
        await query(`CALL sp_cancel_request($1, $2, $3)`, [b.request_id, userId, b.reason]);
        break;
      }
      default:
        return Response.json({ error: 'Unknown action' }, { status: 400 });
    }
    return Response.json({ ok: true });
  } catch (e) {
    // Errors raised by the procedures (RAISE EXCEPTION) are shown to the user
    return Response.json({ error: e.message }, { status: 400 });
  }
}

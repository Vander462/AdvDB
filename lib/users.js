import { query } from './db';

// This app is a local/demo role switcher, not an authentication system.
// The selected demo actor is validated against the profile tables on each API call.
export const DEFAULT_ADMIN_EMAIL = 'admin.estate@cst.edu.bt';
export const DEFAULT_TECHNICIAN_EMAIL = 'tech.jamyang@cst.edu.bt';
export const DEFAULT_REQUESTER_EMAIL = 'pema.ece@cst.edu.bt';

export async function getUsers() {
  const [admins, technicians, requesters] = await Promise.all([
    query(`SELECT user_id, email FROM app_user
            WHERE system_role = 'admin' AND is_active ORDER BY email`),
    query(`SELECT p.personnel_id, p.user_id, u.email, p.name, t.team_name
             FROM maintenance_personnel p
             JOIN app_user u ON u.user_id = p.user_id
             JOIN maintenance_team t ON t.team_id = p.team_id
            WHERE u.system_role = 'technician' AND u.is_active
            ORDER BY t.team_name, p.name`),
    query(`SELECT r.requester_id, r.user_id, u.email, r.name, r.requester_type
             FROM requester r JOIN app_user u ON u.user_id = r.user_id
            WHERE u.system_role = 'requester' AND u.is_active
            ORDER BY r.name`),
  ]);
  return { admins, technicians, requesters };
}

export async function getActor(role, userId) {
  const users = await getUsers();
  const key = { admin: 'admins', technician: 'technicians', requester: 'requesters' }[role];
  if (!key) throw new Error('Unknown demo role');

  const list = users[key];
  const actor = userId
    ? list.find((user) => String(user.user_id) === String(userId))
    : list[0];
  if (!actor) throw new Error(`No active ${role} account is available`);
  return actor;
}

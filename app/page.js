'use client';
import { useEffect, useMemo, useState } from 'react';
import { api } from '@/components/shared';
import AdminTab from '@/components/AdminTab';
import TechnicianTab from '@/components/TechnicianTab';
import RequesterTab from '@/components/RequesterTab';

const ROLES = [
  { id: 'requester', label: 'Requester', plural: 'requesters', defaultEmail: 'pema.ece@cst.edu.bt' },
  { id: 'technician', label: 'Technician', plural: 'technicians', defaultEmail: 'tech.jamyang@cst.edu.bt' },
  { id: 'admin', label: 'Admin', plural: 'admins', defaultEmail: 'admin.estate@cst.edu.bt' },
];

export default function Home() {
  const [tab, setTab] = useState('requester');
  const [lookups, setLookups] = useState(null);
  const [actorIds, setActorIds] = useState({});
  const [error, setError] = useState('');

  useEffect(() => {
    api('/api/lookups').then((data) => {
      setLookups(data);
      setActorIds((current) => {
        const next = { ...current };
        for (const role of ROLES) {
          const list = data.users[role.plural] || [];
          next[role.id] = next[role.id] || list.find((u) => u.email.toLowerCase() === role.defaultEmail)?.user_id || list[0]?.user_id || '';
        }
        return next;
      });
    }).catch((e) => setError(e.message));
  }, []);

  const activeRole = ROLES.find((r) => r.id === tab);
  const actor = useMemo(() => {
    if (!lookups || !activeRole) return null;
    return (lookups.users[activeRole.plural] || []).find((u) => String(u.user_id) === String(actorIds[tab]));
  }, [lookups, activeRole, actorIds, tab]);

  return (
    <main className="shell">
      <header className="hero">
        <div>
          <p className="eyebrow">CAMPUS OPERATIONS</p>
          <h1>Maintenance requests</h1>
          <p className="intro">Report issues, follow progress, and keep campus maintenance moving.</p>
        </div>
        <span className="demo-tag">Demo mode · no sign-in</span>
      </header>

      {error && <div className="notice error" role="alert"><b>Couldn’t connect to the database.</b><span>{error} Check DATABASE_URL in .env.local.</span></div>}
      {!lookups && !error && <div className="empty-state" role="status"><span className="spinner" /> Connecting to the database…</div>}

      {lookups && (
        <>
          <nav className="tabs" aria-label="Choose a role">
            {ROLES.map((role) => (
              <button key={role.id} className={tab === role.id ? 'active' : ''} onClick={() => setTab(role.id)}>
                {role.label}
              </button>
            ))}
          </nav>

          <section className="workspace">
            <div className="actor-bar">
              <div>
                <span className="eyebrow">TEST AS</span>
                <strong>{activeRole.label}</strong>
              </div>
              <label className="actor-select">
                <span>Demo account</span>
                <select value={actorIds[tab] || ''} onChange={(e) => setActorIds({ ...actorIds, [tab]: e.target.value })}>
                  {(lookups.users[activeRole.plural] || []).map((user) => (
                    <option key={user.user_id} value={user.user_id}>
                      {user.name ? `${user.name} · ${user.email}` : user.email}{user.team_name ? ` · ${user.team_name}` : ''}
                    </option>
                  ))}
                </select>
              </label>
              <p className="demo-note">Switch accounts to try the app as different seeded users. This selector is for local demonstration only.</p>
            </div>

            {!actor && <div className="empty-state">No active {activeRole.label.toLowerCase()} accounts found. Add accounts in the database seed data.</div>}
            {actor && tab === 'requester' && <RequesterTab lookups={lookups} actorUserId={actor.user_id} />}
            {actor && tab === 'technician' && <TechnicianTab lookups={lookups} actorUserId={actor.user_id} />}
            {actor && tab === 'admin' && <AdminTab lookups={lookups} actorUserId={actor.user_id} />}
          </section>
        </>
      )}
      <footer>College Maintenance Request Management · PostgreSQL</footer>
    </main>
  );
}

'use client';
import { useEffect, useState, Fragment } from 'react';

export async function api(url, body) {
  const res = await fetch(url, body
    ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
    : { cache: 'no-store' });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

export const fmt = (d) =>
  d ? new Date(d).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' }) : '';

// Load the request list for a role, re-loading whenever the filters change
export function useRequests(role, filters, actorUserId) {
  const [rows, setRows] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);
  const key = JSON.stringify(filters);
  useEffect(() => {
    let active = true;
    const qs = new URLSearchParams({ role, user_id: String(actorUserId || ''), ...filters });
    const t = setTimeout(() => {
      setLoading(true);
      api('/api/requests?' + qs)
        .then((r) => { if (active) { setRows(r); setError(''); } })
        .catch((e) => { if (active) setError(e.message); })
        .finally(() => { if (active) setLoading(false); });
    }, 250); // small delay so typing in search doesn't fire on every key
    return () => { active = false; clearTimeout(t); };
  }, [role, key, tick, actorUserId]);
  return { rows, error, loading, reload: () => setTick((x) => x + 1) };
}

// Search box + optional dropdown filters
export function Filters({ lookups, filters, setFilters, show = ['status'] }) {
  const set = (k) => (e) => setFilters({ ...filters, [k]: e.target.value });
  return (
    <div className="filters">
      <input aria-label="Search requests" placeholder="Search ID, title, room, name..." value={filters.q} onChange={set('q')} />
      {show.includes('status') && (
        <select value={filters.status} onChange={set('status')}>
          <option value="">All statuses</option>
          {lookups.statuses.map((s) => <option key={s.status_id}>{s.status_name}</option>)}
        </select>
      )}
      {show.includes('category') && (
        <select value={filters.category} onChange={set('category')}>
          <option value="">All categories</option>
          {lookups.categories.map((c) => (
            <option key={c.category_id} value={c.category_id}>{c.category_name}</option>
          ))}
        </select>
      )}
      {show.includes('priority') && (
        <select value={filters.priority} onChange={set('priority')}>
          <option value="">All priorities</option>
          {lookups.priorities.map((p) => <option key={p.priority_id}>{p.priority_name}</option>)}
        </select>
      )}
      <button onClick={() => setFilters({ q: '', status: '', category: '', priority: '' })}>Clear</button>
    </div>
  );
}

export function History({ requestId, role, actorUserId }) {
  const [rows, setRows] = useState(null);
  useEffect(() => {
    setRows(null);
    api(`/api/history?id=${requestId}&role=${role}&user_id=${actorUserId}`)
      .then(setRows).catch(() => setRows([]));
  }, [requestId, role, actorUserId]);
  if (!rows) return <p>Loading history...</p>;
  return (
    <table className="inner">
      <thead><tr><th>When</th><th>From</th><th>To</th><th>By</th><th>Remarks</th></tr></thead>
      <tbody>
        {rows.map((h) => (
          <tr key={h.history_id}>
            <td>{fmt(h.changed_at)}</td><td>{h.old_status || '-'}</td><td>{h.new_status}</td>
            <td>{h.changed_by_name} ({h.changed_by_role})</td><td>{h.remarks}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// Generic request table. columns: [{label, get(row)}]; actions(row) returns buttons.
// Clicking "Details" opens description, repair info and status history under the row.
export function RequestTable({ rows, columns, actions, loading = false, role, actorUserId }) {
  const [open, setOpen] = useState(null);
  if (loading) return <div className="empty-state" role="status"><span className="spinner" /> Loading requests…</div>;
  if (!rows.length) return <div className="empty-state"><b>No requests found</b><span>Try clearing a filter or use a different search.</span></div>;
  return (
    <div className="table-wrap"><table>
      <thead>
        <tr>{columns.map((c) => <th key={c.label}>{c.label}</th>)}<th>Actions</th></tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <Fragment key={r.request_id}>
            <tr>
              {columns.map((c) => <td key={c.label}>{c.get(r)}</td>)}
              <td className="actions">
                <button onClick={() => setOpen(open === r.request_id ? null : r.request_id)}>
                  {open === r.request_id ? 'Hide details' : 'View details'}
                </button>
                {actions && actions(r)}
              </td>
            </tr>
            {open === r.request_id && (
              <tr className="details">
                <td colSpan={columns.length + 1}>
                  <p><b>Description:</b> {r.description}</p>
                  <p><b>Location:</b> {r.building}, floor {r.floor}, room {r.room_no}</p>
                  {r.repair_details && <p><b>Repair details:</b> {r.repair_details}</p>}
                  {r.completion_notes && <p><b>Completion notes:</b> {r.completion_notes}</p>}
                  {r.completed_on && <p><b>Completed on:</b> {fmt(r.completed_on)}</p>}
                  <b>Status history</b>
                  <History requestId={r.request_id} role={role} actorUserId={actorUserId} />
                </td>
              </tr>
            )}
          </Fragment>
        ))}
      </tbody>
    </table></div>
  );
}

export const emptyFilters = { q: '', status: '', category: '', priority: '' };

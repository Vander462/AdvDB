'use client';
import { useEffect, useState } from 'react';
import { api, fmt, useRequests, Filters, RequestTable, emptyFilters } from './shared';

export default function AdminTab({ lookups, actor, actorUserId }) {
  const [view, setView] = useState('requests');
  const [notice, setNotice] = useState(null);
  return (
    <div>
      <div className="subtabs">
        <button className={view === 'requests' ? 'active' : ''} onClick={() => setView('requests')}>All requests</button>
        <button className={view === 'reports' ? 'active' : ''} onClick={() => setView('reports')}>Reports</button>
      </div>
      {view === 'requests' ? <Requests lookups={lookups} actorUserId={actorUserId} notice={notice} setNotice={setNotice} /> : <Reports actorUserId={actorUserId} />}
    </div>
  );
}

function Requests({ lookups, actorUserId, notice, setNotice }) {
  const [filters, setFilters] = useState(emptyFilters);
  const { rows, error, loading, reload } = useRequests('admin', filters, actorUserId);
  const [busyId, setBusyId] = useState(null);

  async function cancel(r) {
    const reason = prompt('Reason for cancelling request #' + r.request_id + ':');
    if (!reason) return;
    setBusyId(r.request_id); setNotice(null);
    try { await api('/api/action', { action: 'cancel', as: 'admin', actor_user_id: actorUserId, request_id: r.request_id, reason }); setNotice({ type: 'success', text: `Request #${r.request_id} was cancelled.` }); reload(); }
    catch (err) { setNotice({ type: 'error', text: err.message }); }
    finally { setBusyId(null); }
  }

  const pending = rows.filter((r) => r.status_name === 'Pending').length;

  return (
    <div>
      <Filters lookups={lookups} filters={filters} setFilters={setFilters} show={['status', 'category', 'priority']} />
      <p className="section-intro">{rows.length} request{rows.length === 1 ? '' : 's'} shown · {pending} waiting for assignment.</p>
      {notice && <div className={`notice ${notice.type}`} role={notice.type === 'error' ? 'alert' : 'status'}>{notice.text}</div>}
      {error && <p className="notice error" role="alert">{error}</p>}
      <RequestTable
        rows={rows}
        loading={loading}
        role="admin"
        actorUserId={actorUserId}
        columns={[
          { label: 'ID', get: (r) => r.request_id },
          { label: 'Title', get: (r) => r.title },
          { label: 'Requester', get: (r) => r.requester_name },
          { label: 'Category / Team', get: (r) => <>{r.category_name}<br /><small>{r.team_name}</small></> },
          { label: 'Suggested urgency', get: (r) => r.suggested_priority_name || <small>Not specified</small> },
          { label: 'Official priority', get: (r) => <PriorityEditor request={r} lookups={lookups} actorUserId={actorUserId} onDone={(text) => { setNotice({ type: 'success', text }); reload(); }} onError={(text) => setNotice({ type: 'error', text })} /> },
          { label: 'Room', get: (r) => r.room_no },
          { label: 'Status', get: (r) => <span className={'st st-' + r.status_name.replace(' ', '')}>{r.status_name}</span> },
          { label: 'Technician', get: (r) => r.technician_name || '-' },
          { label: 'Reported', get: (r) => fmt(r.reported_on) },
        ]}
        actions={(r) => (
          <>
            {r.status_name === 'Pending' && <Assign request={r} actorUserId={actorUserId} onDone={(text) => { setNotice({ type: 'success', text }); reload(); }} onError={(text) => setNotice({ type: 'error', text })} disabled={busyId !== null} />}
            {!['Completed', 'Cancelled'].includes(r.status_name) && (
              <button disabled={busyId !== null} onClick={() => cancel(r)}>{busyId === r.request_id ? 'Saving…' : 'Cancel'}</button>
            )}
          </>
        )}
      />
    </div>
  );
}

function PriorityEditor({ request, lookups, actorUserId, onDone, onError }) {
  const [pick, setPick] = useState(String(request.priority_id));
  const [saving, setSaving] = useState(false);
  useEffect(() => setPick(String(request.priority_id)), [request.priority_id]);

  if (['Completed', 'Cancelled'].includes(request.status_name)) return <span>{request.priority_name}</span>;

  async function save() {
    setSaving(true);
    try {
      await api('/api/action', { action: 'priority', actor_user_id: actorUserId, request_id: request.request_id, priority_id: pick });
      const label = lookups.priorities.find((p) => String(p.priority_id) === String(pick))?.priority_name;
      onDone(`Official priority for request #${request.request_id} set to ${label}.`);
    } catch (err) { onError(err.message); }
    finally { setSaving(false); }
  }

  return (
    <span className="priority-editor">
      <select aria-label={`Official priority for request ${request.request_id}`} value={pick} onChange={(e) => setPick(e.target.value)} disabled={saving}>
        {lookups.priorities.map((p) => <option key={p.priority_id} value={p.priority_id}>{p.priority_name}</option>)}
      </select>
      <button onClick={save} disabled={saving || String(request.priority_id) === String(pick)}>{saving ? 'Saving…' : 'Set'}</button>
    </span>
  );
}

// Dropdown of technicians from the team that handles this category (least busy first)
function Assign({ request, actorUserId, onDone, onError, disabled }) {
  const [techs, setTechs] = useState([]);
  const [pick, setPick] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    let active = true;
    setLoading(true);
    api('/api/technicians?category_id=' + request.category_id).then((t) => {
      if (active) { setTechs(t); if (t[0]) setPick(String(t[0].personnel_id)); }
    }).catch((e) => { if (active) onError(e.message); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [request.category_id]);

  async function assign() {
    setSaving(true);
    try {
      await api('/api/action', { action: 'assign', actor_user_id: actorUserId, request_id: request.request_id, personnel_id: pick });
      onDone(`Request #${request.request_id} assigned to ${techs.find((t) => String(t.personnel_id) === String(pick))?.technician_name || 'the selected technician'}.`);
    } catch (err) { onError(err.message); }
    finally { setSaving(false); }
  }

  return (
    <span className="assign">
      <select aria-label={`Assign request ${request.request_id} to technician`} value={pick} onChange={(e) => setPick(e.target.value)} disabled={loading || !techs.length || disabled || saving}>
        {!techs.length && <option value="">{loading ? 'Loading technicians…' : 'No team technicians'}</option>}
        {techs.map((t) => (
          <option key={t.personnel_id} value={t.personnel_id}>{t.technician_name} · {t.open_jobs} open</option>
        ))}
      </select>
      <button className="primary" onClick={assign} disabled={!pick || loading || disabled || saving}>{saving ? 'Assigning…' : 'Assign'}</button>
    </span>
  );
}

function Reports({ actorUserId }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  useEffect(() => { api('/api/reports?user_id=' + actorUserId).then(setData).catch((e) => setError(e.message)); }, [actorUserId]);
  if (error) return <p className="notice error" role="alert">{error}</p>;
  if (!data) return <div className="empty-state" role="status"><span className="spinner" /> Loading reports…</div>;
  return (
    <div>
      <h2>Requests per category</h2>
      <Simple rows={data.categories}
        cols={['category_name', 'team_name', 'total', 'pending', 'open', 'completed', 'cancelled']} />
      <h2>Work per team</h2>
      <Simple rows={data.teams} cols={['team_name', 'pending', 'open', 'completed', 'avg_hours_to_complete']} />
      <h2>Technician workload</h2>
      <Simple rows={data.workload}
        cols={['technician_name', 'team_name', 'assigned', 'in_progress', 'on_hold', 'open_total', 'completed']} />
    </div>
  );
}

function Simple({ rows, cols }) {
  return (
    <div className="table-wrap"><table>
      <thead><tr>{cols.map((c) => <th key={c}>{c.replaceAll('_', ' ')}</th>)}</tr></thead>
      <tbody>
        {rows.map((r, i) => <tr key={i}>{cols.map((c) => <td key={c}>{r[c] ?? '-'}</td>)}</tr>)}
      </tbody>
    </table></div>
  );
}

'use client';
import { useState } from 'react';
import { api, fmt, useRequests, Filters, RequestTable, emptyFilters } from './shared';

export default function TechnicianTab({ lookups, actor, actorUserId }) {
  const [filters, setFilters] = useState(emptyFilters);
  const { rows, error, loading, reload } = useRequests('technician', filters, actorUserId);
  const [completing, setCompleting] = useState(null); // request being completed
  const [done, setDone] = useState({ repair_details: '', notes: '' });
  const [busyId, setBusyId] = useState(null);
  const [notice, setNotice] = useState(null);

  const open = rows.filter((r) => ['Assigned', 'In Progress', 'On Hold'].includes(r.status_name)).length;

  async function move(r, new_status, askReason) {
    let remarks = '';
    if (askReason) {
      remarks = prompt(askReason);
      if (remarks === null) return;
    }
    setBusyId(r.request_id); setNotice(null);
    try { await api('/api/action', { action: 'status', actor_user_id: actorUserId, request_id: r.request_id, new_status, remarks }); setNotice({ type: 'success', text: `Request #${r.request_id} moved to ${new_status}.` }); reload(); }
    catch (err) { setNotice({ type: 'error', text: err.message }); }
    finally { setBusyId(null); }
  }

  async function complete(e) {
    e.preventDefault();
    setBusyId(completing.request_id); setNotice(null);
    try {
      await api('/api/action', { action: 'complete', actor_user_id: actorUserId, request_id: completing.request_id, ...done });
      setNotice({ type: 'success', text: `Request #${completing.request_id} was completed.` });
      setCompleting(null); setDone({ repair_details: '', notes: '' }); reload();
    } catch (err) { setNotice({ type: 'error', text: err.message }); }
    finally { setBusyId(null); }
  }

  return (
    <div>
      <p className="section-intro">You have <b>{open}</b> active job{open === 1 ? '' : 's'}. Update progress or record completed repairs.</p>
      {notice && <div className={`notice ${notice.type}`} role={notice.type === 'error' ? 'alert' : 'status'}>{notice.text}</div>}

      {completing && (
        <form onSubmit={complete} className="form box">
          <b>Complete request #{completing.request_id}: {completing.title}</b>
          <label>Repair details<textarea placeholder="Describe the repair work completed." required value={done.repair_details}
            onChange={(e) => setDone({ ...done, repair_details: e.target.value })} />
          </label>
          <label>Completion notes<textarea placeholder="Testing results or follow-up (optional)" value={done.notes}
            onChange={(e) => setDone({ ...done, notes: e.target.value })} /></label>
          <div>
            <button className="primary" type="submit" disabled={busyId !== null}>{busyId === completing.request_id ? 'Saving…' : 'Mark completed'}</button>{' '}
            <button type="button" onClick={() => setCompleting(null)}>Close</button>
          </div>
        </form>
      )}

      <h2>My assigned requests</h2>
      <Filters lookups={lookups} filters={filters} setFilters={setFilters} show={['status', 'priority']} />
      {error && <p className="notice error" role="alert">{error}</p>}
      <RequestTable
        rows={rows}
        loading={loading}
        role="technician"
        actorUserId={actorUserId}
        columns={[
          { label: 'ID', get: (r) => r.request_id },
          { label: 'Title', get: (r) => r.title },
          { label: 'Priority', get: (r) => r.priority_name },
          { label: 'Location', get: (r) => `${r.room_no} (${r.building})` },
          { label: 'Requester', get: (r) => r.requester_name },
          { label: 'Status', get: (r) => <span className={'st st-' + r.status_name.replace(' ', '')}>{r.status_name}</span> },
          { label: 'Reported', get: (r) => fmt(r.reported_on) },
        ]}
        actions={(r) => (
          <>
            {r.status_name === 'Assigned' && (
              <button disabled={busyId !== null} onClick={() => move(r, 'In Progress', 'Remarks (optional):')}>{busyId === r.request_id ? 'Saving…' : 'Start work'}</button>
            )}
            {r.status_name === 'In Progress' && (
              <>
                <button disabled={busyId !== null} onClick={() => move(r, 'On Hold', 'Reason for putting On Hold:')}>Put on hold</button>
                <button className="primary" disabled={busyId !== null} onClick={() => setCompleting(r)}>Complete</button>
              </>
            )}
            {r.status_name === 'On Hold' && (
              <button disabled={busyId !== null} onClick={() => move(r, 'In Progress', 'Remarks (optional):')}>Resume work</button>
            )}
          </>
        )}
      />
    </div>
  );
}

'use client';
import { useState } from 'react';
import { api, fmt, useRequests, Filters, RequestTable, emptyFilters } from './shared';

export default function RequesterTab({ lookups, actor, actorUserId }) {
  const [filters, setFilters] = useState(emptyFilters);
  const { rows, error, loading, reload } = useRequests('requester', filters, actorUserId);
  const blank = { title: '', description: '', category_id: '', priority_id: '', location_id: '' };
  const [form, setForm] = useState(blank);
  const [notice, setNotice] = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const [cancellingId, setCancellingId] = useState(null);
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  async function submit(e) {
    e.preventDefault();
    setSubmitting(true); setNotice(null);
    try {
      await api('/api/action', { action: 'submit', actor_user_id: actorUserId, ...form });
      setForm(blank); setNotice({ type: 'success', text: 'Your request was submitted and saved.' }); reload();
    } catch (err) { setNotice({ type: 'error', text: err.message }); }
    finally { setSubmitting(false); }
  }

  async function cancel(r) {
    const reason = prompt('Why do you want to cancel request #' + r.request_id + '?');
    if (!reason) return;
    setCancellingId(r.request_id); setNotice(null);
    try { await api('/api/action', { action: 'cancel', as: 'requester', actor_user_id: actorUserId, request_id: r.request_id, reason }); setNotice({ type: 'success', text: `Request #${r.request_id} was cancelled.` }); reload(); }
    catch (err) { setNotice({ type: 'error', text: err.message }); }
    finally { setCancellingId(null); }
  }

  return (
    <div>
      <p className="section-intro">Submit a campus issue and follow its status from here.</p>

      <h2>New maintenance request</h2>
      <form onSubmit={submit} className="form">
        <label>Issue title<input placeholder="e.g. Light not working in room 204" value={form.title} onChange={set('title')} required maxLength={150} /></label>
        <label>Description<textarea placeholder="Tell us what happened and any details that may help." value={form.description} onChange={set('description')} required /></label>
        <label>Category<select value={form.category_id} onChange={set('category_id')} required>
          <option value="">Choose a category…</option>
          {lookups.categories.map((c) => (
            <option key={c.category_id} value={c.category_id}>{c.category_name} ({c.team_name})</option>
          ))}
        </select></label>
        <label>Suggested urgency<select value={form.priority_id} onChange={set('priority_id')} required>
          <option value="">Choose how urgent it seems…</option>
          {lookups.priorities.map((p) => <option key={p.priority_id} value={p.priority_id}>{p.priority_name}</option>)}
        </select><small>This is a suggestion. The maintenance admin confirms the official priority.</small></label>
        <label>Location<select value={form.location_id} onChange={set('location_id')} required>
          <option value="">Choose a location…</option>
          {lookups.locations.map((l) => (
            <option key={l.location_id} value={l.location_id}>{l.room_no} - {l.building}, floor {l.floor}</option>
          ))}
        </select></label>
        <button className="primary" type="submit" disabled={submitting}>{submitting ? <><span className="spinner small" /> Submitting…</> : 'Submit request'}</button>
      </form>
      {notice && <div className={`notice ${notice.type}`} role={notice.type === 'error' ? 'alert' : 'status'}>{notice.text}</div>}

      <h2>My requests</h2>
      <Filters lookups={lookups} filters={filters} setFilters={setFilters} show={['status', 'category']} />
      {error && <p className="error">{error}</p>}
      <RequestTable
        rows={rows}
        loading={loading}
        role="requester"
        actorUserId={actorUserId}
        columns={[
          { label: 'ID', get: (r) => r.request_id },
          { label: 'Title', get: (r) => r.title },
          { label: 'Category', get: (r) => r.category_name },
          { label: 'Priority', get: (r) => r.priority_name },
          { label: 'Room', get: (r) => r.room_no },
          { label: 'Status', get: (r) => <span className={'st st-' + r.status_name.replace(' ', '')}>{r.status_name}</span> },
          { label: 'Technician', get: (r) => r.technician_name || '-' },
          { label: 'Reported', get: (r) => fmt(r.reported_on) },
        ]}
        actions={(r) => r.status_name === 'Pending' && <button disabled={cancellingId !== null} onClick={() => cancel(r)}>{cancellingId === r.request_id ? 'Cancelling…' : 'Cancel'}</button>}
      />
    </div>
  );
}

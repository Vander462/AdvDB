# College Maintenance Requests

A small Next.js demonstration app for the College Maintenance Request database. It connects to PostgreSQL through server-side API routes.

## Demo roles

Use the account selector at the top of each role tab to switch between active database users:

- **Requester:** submit a request, view its history, and cancel it while Pending.
- **Technician:** see work assigned to that technician, update progress, and complete a repair.
- **Admin:** view all requests, confirm or change official priority, assign Pending work to a technician from the category's team, and review reports.

Requesters may suggest an urgency when submitting. The saved operational priority starts at Medium; the admin chooses the official priority during triage. Suggested and official priority appear separately in the admin request list.

The account selector is for local classroom demonstration only; it is **not authentication**. Do not expose this demo publicly until real sign-in and server-side authorization are implemented. A visitor can change demo user IDs sent to these API routes.

## Database setup

Run these scripts in the Neon PostgreSQL SQL editor, in order:

1. `sql/01_schema.sql` (safe to re-run; adds the suggested priority column to an older schema)
2. `sql/01_verify.sql` (confirm every check says `PASS`)
3. `sql/02_seed.sql` (skip if the sample rows are already loaded)
4. `sql/03_rollback_old_logic.sql` (only if replacing the previous workflow objects)
5. `sql/03_simple_logic.sql`
6. `sql/04_priority_admin_migration.sql` (safe to re-run; installs the admin priority action)
7. `sql/03_simple_test.sql` (optional; its test transaction rolls back)

`sql/03_simple_logic.sql` creates the app's views, trigger, helper functions, and stored procedures. Run the scripts in a PostgreSQL SQL editor, not MySQL.

## Run locally

```powershell
npm install
Copy-Item .env.example .env.local
```

Open `.env.local`, paste the PostgreSQL connection string from Neon as `DATABASE_URL`, then start the app:

```powershell
npm run dev
```

Open `http://localhost:3000`.

Keep `.env.local` private and never expose the database connection string to browser code. The app uses the connection string only in its server API routes.

## Database integration

- Reads come from the request and reporting views and `fn_team_technicians()`.
- Writes go through the `sp_*` stored procedures.
- `trg_log_status_change` adds a history row when a request is created or its status changes.
- Admin assignment only offers technicians from the team responsible for the request category, ordered by current open workload.
- Procedure-level row locks serialize assignment and workflow changes so concurrent actions cannot silently overwrite one another.



# Database Logic Guide

A reference guide to the database views, helper functions, trigger, stored procedures, and verification queries.

## 1. Summary count of database objects (from 03_simple_logic.sql)
| Object type | How many | Names | Main purpose |
| --- | --- | --- | --- |
| Views | 5 | v_request_details, v_request_history, v_technician_workload, v_category_summary, v_team_summary | Simplify retrieval / reports |
| Helper functions | 2 | fn_status_id(text), fn_team_technicians(bigint) | Lookups used by procedures |
| Trigger | 1 | trg_log_status_change on maintenance_request (function trg_log_status_change()) | Auto‑log every status change |
| Stored procedures | 5 | sp_submit_request, sp_assign_request, sp_update_status, sp_complete_request, sp_cancel_request | Enforce workflow / business rules |
| Total | 13 objects |  |  |
These match the report/presentation: 5 views, 2 helper functions, 1 trigger + trigger function, 5 stored procedures.

## 2. How to check that an object exists
All checks are read‑only SELECTs you can run in the Neon SQL editor.

```sql
-- Views
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name IN ('v_request_details','v_request_history',
                     'v_technician_workload','v_category_summary','v_team_summary');

-- Functions (helper functions + trigger function)
SELECT proname, pg_get_function_identity_arguments(oid) AS args
FROM pg_proc
WHERE proname IN ('fn_status_id','fn_team_technicians','trg_log_status_change');

-- Procedures (PostgreSQL 11+ separate catalogue: pg_proc with prokind = 'p')
SELECT proname, pg_get_function_identity_arguments(oid) AS args
FROM pg_proc
WHERE prokind = 'p'
  AND proname IN ('sp_submit_request','sp_assign_request','sp_update_status',
                  'sp_complete_request','sp_cancel_request');

-- Trigger
SELECT event_object_table AS table_name, trigger_name, event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name = 'trg_log_status_change';
```

Expected results:

| Check | Expected |
| --- | --- |
| Views | 5 rows |
| Helper/trigger functions | 3 rows (fn_status_id, fn_team_technicians, trg_log_status_change) |
| Procedures | 5 rows |
| Trigger | 1–2 rows (INSERT, UPDATE or combined) |
## 3. Views (5)
### 3.1 v_request_details
What it does: Joins 7 tables and returns every request with readable names instead of numeric IDs (requester name + type, category, team, priority + rank, location, status, technician name). Used by all three tabs of the web interface and the admin list.

Why LEFT JOIN on technician: Pending requests have no technician; an inner join would hide them.

```sql
CREATE OR REPLACE VIEW v_request_details AS
SELECT m.request_id,
       m.title,
       m.description,
       m.reported_on,
       m.completed_on,
       m.repair_details,
       m.completion_notes,
       m.requester_id,
       rq.name            AS requester_name,
       rq.requester_type,
       m.category_id,
       c.category_name,
       t.team_id,
       t.team_name,
       m.priority_id,
       p.priority_name,
       p.sort_rank        AS priority_rank,
       m.location_id,
       l.building,
       l.floor,
       l.room_no,
       m.status_id,
       s.status_name,
       m.personnel_id,
       mp.name            AS technician_name
FROM maintenance_request m
JOIN requester rq                  ON rq.requester_id = m.requester_id
JOIN category c                    ON c.category_id   = m.category_id
JOIN maintenance_team t            ON t.team_id       = c.team_id
JOIN priority p                    ON p.priority_id   = m.priority_id
JOIN location l                    ON l.location_id   = m.location_id
JOIN status s                      ON s.status_id     = m.status_id
LEFT JOIN maintenance_personnel mp ON mp.personnel_id = m.personnel_id;
```

How to check it works / see data:

```sql
SELECT request_id, title, requester_name, status_name, technician_name
FROM v_request_details
ORDER BY request_id
LIMIT 10;
```

You should see 42 rows (from the seed) with names, no NULL requester/category/status, and technician_name empty only for Pending requests.

### 3.2 v_request_history
What it does: Shows each status change with old/new status names, who changed it (falls back to technician name → requester name → email), the role, time and remarks. Used for the history panel in all three tabs.

```sql
CREATE OR REPLACE VIEW v_request_history AS
SELECT h.history_id,
       h.request_id,
       m.title,
       h.changed_at,
       so.status_name AS old_status,
       sn.status_name AS new_status,
       COALESCE(mp.name, rq.name, u.email) AS changed_by_name,
       u.system_role  AS changed_by_role,
       h.remarks
FROM request_status_history h
JOIN maintenance_request m         ON m.request_id    = h.request_id
JOIN status sn                     ON sn.status_id    = h.new_status_id
LEFT JOIN status so                ON so.status_id    = h.old_status_id
JOIN app_user u                    ON u.user_id       = h.changed_by
LEFT JOIN maintenance_personnel mp ON mp.user_id      = u.user_id
LEFT JOIN requester rq             ON rq.user_id      = u.user_id;
```

How to check it works / see data:

```sql
SELECT old_status, new_status, changed_by_name, changed_by_role, remarks
FROM v_request_history
WHERE request_id = 1
ORDER BY history_id;
```

For request 1 (Oscilloscope Channel 2 Calib Failure) you should see the sequence Pending → Assigned → In Progress → Completed.

### 3.3 v_technician_workload
What it does: Counts Assigned, In Progress, On Hold, open total and Completed per technician using count(*) FILTER (WHERE …) — a single pass over the data. Used by fn_team_technicians and the admin reports.

```sql
CREATE OR REPLACE VIEW v_technician_workload AS
SELECT mp.personnel_id,
       mp.name AS technician_name,
       t.team_name,
       count(*) FILTER (WHERE s.status_name = 'Assigned')    AS assigned,
       count(*) FILTER (WHERE s.status_name = 'In Progress') AS in_progress,
       count(*) FILTER (WHERE s.status_name = 'On Hold')     AS on_hold,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open_total,
       count(*) FILTER (WHERE s.status_name = 'Completed')   AS completed
FROM maintenance_personnel mp
JOIN maintenance_team t          ON t.team_id = mp.team_id
LEFT JOIN maintenance_request m  ON m.personnel_id = mp.personnel_id
LEFT JOIN status s               ON s.status_id = m.status_id
GROUP BY mp.personnel_id, mp.name, t.team_name;
```

How to check it works / see data:

```sql
SELECT * FROM v_technician_workload ORDER BY open_total DESC, technician_name;
```

Every technician appears exactly once (8 rows from seed), and assigned + in_progress + on_hold = open_total.

### 3.4 v_category_summary
What it does: Reports total / pending / open / completed / cancelled requests per category + team. Used by the admin report tab.

```sql
CREATE OR REPLACE VIEW v_category_summary AS
SELECT c.category_name,
       t.team_name,
       count(m.request_id) AS total,
       count(*) FILTER (WHERE s.status_name = 'Pending')   AS pending,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open,
       count(*) FILTER (WHERE s.status_name = 'Completed') AS completed,
       count(*) FILTER (WHERE s.status_name = 'Cancelled') AS cancelled
FROM category c
JOIN maintenance_team t         ON t.team_id = c.team_id
LEFT JOIN maintenance_request m ON m.category_id = c.category_id
LEFT JOIN status s              ON s.status_id = m.status_id
GROUP BY c.category_name, t.team_name;
```

How to check it works / see data:

```sql
SELECT * FROM v_category_summary ORDER BY total DESC;
```

All 10 categories should appear (even ones with 0 requests). Columns pending + open + completed + cancelled should equal total.

### 3.5 v_team_summary
What it does: Pending / open / completed per team plus the average hours to complete (using EXTRACT(EPOCH FROM (completed_on - reported_on))). Used for the admin reports.

```sql
CREATE OR REPLACE VIEW v_team_summary AS
SELECT t.team_name,
       count(*) FILTER (WHERE s.status_name = 'Pending') AS pending,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open,
       count(*) FILTER (WHERE s.status_name = 'Completed') AS completed,
       round(avg(EXTRACT(EPOCH FROM (m.completed_on - m.reported_on)) / 3600)
             FILTER (WHERE s.status_name = 'Completed'), 1) AS avg_hours_to_complete
FROM maintenance_team t
LEFT JOIN category c            ON c.team_id = t.team_id
LEFT JOIN maintenance_request m ON m.category_id = c.category_id
LEFT JOIN status s              ON s.status_id = m.status_id
GROUP BY t.team_name;
```

How to check it works / see data:

```sql
SELECT * FROM v_team_summary ORDER BY avg_hours_to_complete DESC NULLS LAST;
```

All 5 teams appear. avg_hours_to_complete is NULL only for teams that have no completed requests (shouldn't happen after seed).

## 4. Helper functions (2)
### 4.1 fn_status_id(text)
What it does: Returns the numeric status_id for a status name. Lets procedures refer to statuses by name ('Pending') instead of hard‑coded IDs.

```sql
CREATE OR REPLACE FUNCTION fn_status_id(p_name text)
RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT status_id FROM status WHERE status_name = p_name
$$;
How to check it exists / works:

sql
SELECT fn_status_id('Pending')    AS pending_id,
       fn_status_id('In Progress') AS in_progress_id,
       fn_status_id('Completed')   AS completed_id,
       fn_status_id('DoesNotExist') AS missing;   -- NULL
```

Expected: 3 numbers and NULL for the missing one.

### 4.2 fn_team_technicians(bigint)
What it does: Given a category_id, returns the technicians of the team that handles that category, with each technician's open‑job count, sorted least busy first. This is what fills the admin's "Assign" dropdown so work is shared fairly.

```sql
CREATE OR REPLACE FUNCTION fn_team_technicians(p_category_id bigint)
RETURNS TABLE (personnel_id bigint, technician_name text, open_jobs bigint)
LANGUAGE sql STABLE AS $$
    SELECT w.personnel_id, w.technician_name::text, w.open_total
    FROM v_technician_workload w
    JOIN maintenance_personnel mp ON mp.personnel_id = w.personnel_id
    JOIN category c               ON c.team_id = mp.team_id
    WHERE c.category_id = p_category_id
    ORDER BY w.open_total, w.technician_name
$$;
How to check it exists / works:

sql
-- What technicians can be assigned to a "Scientific & Test Equipment" request?
SELECT *
FROM fn_team_technicians(
  (SELECT category_id FROM category WHERE category_name = 'Scientific & Test Equipment')
);
```

You should get back Jamyang Tenzin and Choki Wangmo (the two technicians of the Lab & Precision Instruments Unit), ordered by their open jobs.

Negative check:

```sql
SELECT count(*) FROM fn_team_technicians(-1);  -- 0 rows
```

## 5. Trigger (1) — trg_log_status_change
What it does: Every time a row is inserted into maintenance_request or its status_id is updated, this trigger inserts a row into request_status_history with:

the old status (NULL for the insert),

the new status,

who made the change (read from app.user_id),

the remarks (read from app.remarks),

the time (defaults to now()).

How the procedures communicate the actor: each procedure calls

```sql
PERFORM set_config('app.user_id', <user_id>::text, true);
PERFORM set_config('app.remarks', '<text>', true);
before the UPDATE. The true means "local to transaction". The trigger reads these with current_setting('app.user_id', true).

Two branches:

IF TG_OP = 'INSERT' — new request; the actor falls back to the requester if no app.user_id was set, and the remark defaults to 'Request submitted'.

ELSIF NEW.status_id <> OLD.status_id — any status change must set app.user_id or the trigger raises an exception, forcing callers to go through the procedures.

sql
CREATE OR REPLACE FUNCTION trg_log_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user    bigint := NULLIF(current_setting('app.user_id', true), '')::bigint;
    v_remarks text   := NULLIF(current_setting('app.remarks', true), '');
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_user := COALESCE(v_user,
                  (SELECT user_id FROM requester WHERE requester_id = NEW.requester_id));
        INSERT INTO request_status_history (request_id, old_status_id, new_status_id, changed_by, remarks)
        VALUES (NEW.request_id, NULL, NEW.status_id, v_user, COALESCE(v_remarks, 'Request submitted'));

    ELSIF NEW.status_id <> OLD.status_id THEN
        IF v_user IS NULL THEN
            RAISE EXCEPTION 'Change status through the procedures (who made the change is unknown)';
        END IF;
        INSERT INTO request_status_history (request_id, old_status_id, new_status_id, changed_by, remarks)
        VALUES (NEW.request_id, OLD.status_id, NEW.status_id, v_user, v_remarks);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_status_change ON maintenance_request;
CREATE TRIGGER trg_log_status_change
    AFTER INSERT OR UPDATE OF status_id ON maintenance_request
    FOR EACH ROW EXECUTE FUNCTION trg_log_status_change();
How to check it exists / works:
```

Check existence:

```sql
SELECT trigger_name, event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'maintenance_request';
```

Positive test (round‑trip through a procedure — the automatic path):

```sql
-- Count history rows before
SELECT count(*) FROM request_status_history;

-- Run the whole automated test (creates + moves one request, then rolls back)
-- The test script prints "PASS T6 ... history rows = 6".
```

Negative test — try to bypass the procedures. As a manual UPDATE without setting app.user_id, the trigger should refuse:

```sql
BEGIN;
SET LOCAL app.user_id = '';   -- empty
UPDATE maintenance_request
SET status_id = (SELECT status_id FROM status WHERE status_name = 'Cancelled')
WHERE request_id = 42;        -- a Pending request
-- Expected: ERROR: Change status through the procedures (who made the change is unknown)
ROLLBACK;
```

Check a specific request's history (proves the trigger wrote it):

```sql
SELECT old_status, new_status, changed_by_name, changed_by_role, remarks
FROM v_request_history
WHERE request_id = 1
ORDER BY history_id;
```

What happens if you run it twice? CREATE OR REPLACE FUNCTION overwrites the function; DROP TRIGGER IF EXISTS + CREATE TRIGGER is safe. No data is touched.

## 6. Stored procedures (5)
All are called with CALL sp_name(...). Each does four things:

Read the current status.

Check the business rules (raise EXCEPTION on violation — nothing is changed).

Record who is acting (set_config('app.user_id', …, true) + remarks).

Let the trigger log the change and update the row.


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


# College Maintenance Request Database — Logic Guide

A practical, copy-and-paste guide for the **PostgreSQL database hosted on Neon**. It explains the views, functions, trigger, and stored procedures in the supplied project SQL files, how to install them, how to verify them, and what should be improved before presenting the project.

> **Scope:** This guide is based on the supplied `01_schema.sql`, `02_seed.sql`, `03_simple_logic.sql`, `03_simple_test.sql`, and the earlier `makeit(1).md`. The SQL blocks below are intended for the Neon SQL Editor. Run one complete block at a time unless a section explicitly says otherwise.

## 1. What is a trigger? (simple explanation)

**trigger automatically invokes database code when a specified event happens**. The event is usually an `INSERT`, `UPDATE`, or `DELETE` on a table (or, in some cases, an event on a view).

Think of a trigger as an automatic reaction:

1. Something happens to a database row (the event).
2. PostgreSQL detects that the event matches a trigger definition.
3. PostgreSQL automatically runs the trigger function.
4. The function performs the configured action, often inserting or updating another table.

A trigger is not the code that does the work by itself. In PostgreSQL, the **trigger is the rule that says when to run**, and the **trigger function contains the code that runs**.

### Example from this project

When a maintenance request is inserted, or its `status_id` is changed, `trg_log_status_change` runs `trg_log_status_change()` and adds a row to `request_status_history`.

```text
UPDATE maintenance_request
        |
        | status_id changes
        v
trg_log_status_change (trigger)
        |
        | invokes
        v
trg_log_status_change() (trigger function)
        |
        | INSERTs an audit row
        v
request_status_history
```

For example, when a technician changes a request from `Assigned` to `In Progress`, the trigger function records the old status, new status, actor, remarks, and timestamp. The procedure does not need to write a separate history `INSERT`; the trigger handles that automatically.

### Important PostgreSQL terms

| Term | Meaning | In this project |
|---|---|---|
| Event | The database operation that happens | `INSERT` or `UPDATE OF status_id` |
| Trigger | The rule attached to a table that decides when code runs | `trg_log_status_change` |
| Trigger function | The function automatically called by the trigger | `trg_log_status_change()` |
| `NEW` | The row values after an INSERT or UPDATE | `NEW.status_id` |
| `OLD` | The row values before an UPDATE or DELETE | `OLD.status_id` |
| `AFTER` | Run after the row operation | Used by this project's audit trigger |
| `FOR EACH ROW` | Run once for every affected row | Each request row is handled separately |

`NEW` is available for INSERT/UPDATE triggers; `OLD` is available for UPDATE/DELETE triggers. An `AFTER` trigger can write to another table after the original row operation. If its function raises an error, the statement/transaction is still rolled back.

## 2. Database object inventory

The following counts come from `03_simple_logic.sql`.

| Object type | Count | Names | Main purpose |
|---|---:|---|---|
| Views | **5** | `v_request_details`, `v_request_history`, `v_technician_workload`, `v_category_summary`, `v_team_summary` | Readable request data and reports |
| Regular helper functions | **2** | `fn_status_id`, `fn_team_technicians` | Return lookup values / result rows |
| Trigger functions | **1** | `trg_log_status_change()` | Contains automatic history-logging logic |
| Triggers | **1** | `trg_log_status_change` | Runs after request insert or status update |
| Stored procedures | **5** | `sp_submit_request`, `sp_assign_request`, `sp_update_status`, `sp_complete_request`, `sp_cancel_request` | Perform workflow operations and enforce business rules |
| **Total physical database objects** | **14** |  | Counts the trigger and its trigger function separately |

**Counting note:** Some reports say **13 logical features** because they count the trigger and its trigger function together as one feature: 5 views + 2 helper functions + 1 trigger feature + 5 procedures = 13. If counting actual PostgreSQL objects, count the trigger and its trigger function separately: **14 objects**. The trigger function is also technically a PostgreSQL function, so a query for all functions will return **3 functions**, not 2.

## 3. Recommended execution order in Neon

Use the supplied SQL files in this order:

| Order | File | What it does |
|---:|---|---|
| 1 | `01_schema.sql` | Creates the 10 tables, constraints, and indexes |
| 2 | `01_verify.sql` | Read-only check that the schema objects exist |
| 3 | `02_seed.sql` | Inserts sample users, teams, categories, locations, requests, and sample history |
| 4 | `03_simple_logic.sql` | Creates the 5 views, 2 helper functions, trigger function, trigger, and 5 procedures |
| 5 | `03_simple_test.sql` | Runs a workflow test inside a transaction and rolls it back |

**Important:** `02_seed.sql` is designed to run before the trigger is installed. The seed script inserts sample request/history data itself. The trigger then records future request inserts and status changes. The current `03_simple_logic.sql` header mentions `03_rollback_old_logic`; that file was not among the supplied files, so do not run an unknown cleanup script unless your project team has separately provided and explained it.

### One comment in the schema file needs updating

The comment above `maintenance_request` in `01_schema.sql` says a **BEFORE INSERT trigger** sets the status to `Pending`. That does not match the supplied logic file: `sp_submit_request` explicitly sets the status to `Pending`, and the supplied trigger is an **AFTER INSERT OR UPDATE OF status_id** audit trigger. The comment is outdated; it does not change the table definition. Update that comment in your project copy to avoid confusing your presentation.

## 4. Check whether all objects were created

Run this after `03_simple_logic.sql` succeeds. These queries are read-only.

### 4.1 Check the five views

```sql
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name IN (
    'v_request_details', 'v_request_history',
    'v_technician_workload', 'v_category_summary', 'v_team_summary'
  )
ORDER BY table_name;
```

Expected: **5 rows**.

### 4.2 Check all three functions (two helpers + one trigger function)

```sql
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       CASE WHEN p.prorettype = 'trigger'::regtype
            THEN 'trigger function'
            ELSE 'regular function'
       END AS function_type
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.proname IN (
    'fn_status_id', 'fn_team_technicians', 'trg_log_status_change'
  )
ORDER BY p.proname;
```

Expected: **3 rows**. The trigger function is included in PostgreSQL's function catalogue.

### 4.3 Check the five stored procedures

```sql
SELECT p.proname AS procedure_name,
       pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'p'
  AND p.proname IN (
    'sp_submit_request', 'sp_assign_request', 'sp_update_status',
    'sp_complete_request', 'sp_cancel_request'
  )
ORDER BY p.proname;
```

Expected: **5 rows**. PostgreSQL stores procedures in `pg_proc` with `prokind = 'p'`.

### 4.4 Check the trigger

```sql
SELECT trigger_name, event_manipulation, action_timing,
       event_object_table AS table_name
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table = 'maintenance_request'
  AND trigger_name = 'trg_log_status_change'
ORDER BY event_manipulation;
```

Expected: usually **2 rows**, one for `INSERT` and one for `UPDATE`. This is one trigger configured for two events, not two separate triggers.

## 5. Views (5)

A **view is a saved SQL query**. It normally does not store a second copy of the result data; when you query the view, PostgreSQL runs its underlying query against the current tables. Use `SELECT` to read from a view.

### 5.1 `v_request_details` — readable request information

**What it does:** Joins the request table to requester, category, team, priority, location, status, and technician tables. It replaces many numeric foreign-key IDs with names that are easier for the application and admin to display.

**Why the `LEFT JOIN` for the technician?** A new `Pending` request has no assigned technician yet. A normal `JOIN` would hide that request. `LEFT JOIN` keeps it visible and shows `NULL` for the technician until assignment.

```sql
CREATE OR REPLACE VIEW v_request_details AS
SELECT m.request_id, m.title, m.description,
       m.reported_on, m.completed_on,
       m.repair_details, m.completion_notes,
       m.requester_id, rq.name AS requester_name, rq.requester_type,
       m.category_id, c.category_name,
       t.team_id, t.team_name,
       m.priority_id, p.priority_name, p.sort_rank AS priority_rank,
       m.location_id, l.building, l.floor, l.room_no,
       m.status_id, s.status_name,
       m.personnel_id, mp.name AS technician_name
FROM maintenance_request m
JOIN requester rq ON rq.requester_id = m.requester_id
JOIN category c ON c.category_id = m.category_id
JOIN maintenance_team t ON t.team_id = c.team_id
JOIN priority p ON p.priority_id = m.priority_id
JOIN location l ON l.location_id = m.location_id
JOIN status s ON s.status_id = m.status_id
LEFT JOIN maintenance_personnel mp ON mp.personnel_id = m.personnel_id;
```

**Check the data:**

```sql
SELECT request_id, title, requester_name, category_name,
       team_name, priority_name, status_name, technician_name
FROM v_request_details
ORDER BY request_id
LIMIT 10;
```

Expected: request titles and readable names. A request without an assigned technician should have `technician_name = NULL`.

### 5.2 `v_request_history` — readable status history

**What it does:** Shows each history entry with the request title, old and new status names, timestamp, remarks, and the person/role that made the change. It joins `request_status_history` to the related tables so the UI does not have to translate IDs itself.

`COALESCE(mp.name, rq.name, u.email)` returns the first available actor label: technician name, requester name, or email.

```sql
CREATE OR REPLACE VIEW v_request_history AS
SELECT h.history_id, h.request_id, m.title, h.changed_at,
       so.status_name AS old_status,
       sn.status_name AS new_status,
       COALESCE(mp.name, rq.name, u.email) AS changed_by_name,
       u.system_role AS changed_by_role,
       h.remarks
FROM request_status_history h
JOIN maintenance_request m ON m.request_id = h.request_id
JOIN status sn ON sn.status_id = h.new_status_id
LEFT JOIN status so ON so.status_id = h.old_status_id
JOIN app_user u ON u.user_id = h.changed_by
LEFT JOIN maintenance_personnel mp ON mp.user_id = u.user_id
LEFT JOIN requester rq ON rq.user_id = u.user_id;
```

**Check the data:**

```sql
SELECT request_id, title, old_status, new_status,
       changed_by_name, changed_by_role, changed_at, remarks
FROM v_request_history
ORDER BY request_id, changed_at
LIMIT 30;
```

For a newly submitted request, the first history row has `old_status = NULL` and `new_status = 'Pending'`.

### 5.3 `v_technician_workload` — workload per technician

**What it does:** Counts how many requests each technician has in `Assigned`, `In Progress`, `On Hold`, and `Completed` status. `open_total` adds the three active-work statuses together. It includes technicians with zero requests because it uses `LEFT JOIN`.

```sql
CREATE OR REPLACE VIEW v_technician_workload AS
SELECT mp.personnel_id,
       mp.name AS technician_name,
       t.team_name,
       count(*) FILTER (WHERE s.status_name = 'Assigned') AS assigned,
       count(*) FILTER (WHERE s.status_name = 'In Progress') AS in_progress,
       count(*) FILTER (WHERE s.status_name = 'On Hold') AS on_hold,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open_total,
       count(*) FILTER (WHERE s.status_name = 'Completed') AS completed
FROM maintenance_personnel mp
JOIN maintenance_team t ON t.team_id = mp.team_id
LEFT JOIN maintenance_request m ON m.personnel_id = mp.personnel_id
LEFT JOIN status s ON s.status_id = m.status_id
GROUP BY mp.personnel_id, mp.name, t.team_name;
```

**Check the data:**

```sql
SELECT *
FROM v_technician_workload
ORDER BY open_total DESC, technician_name;
```

Expected: one row per technician. For every row, `assigned + in_progress + on_hold` should equal `open_total`.

### 5.4 `v_category_summary` — request totals per category

**What it does:** Groups requests by category and team, showing total, pending, open, completed, and cancelled counts. Categories with no requests remain visible because the request join is a `LEFT JOIN`.

```sql
CREATE OR REPLACE VIEW v_category_summary AS
SELECT c.category_name, t.team_name,
       count(m.request_id) AS total,
       count(*) FILTER (WHERE s.status_name = 'Pending') AS pending,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open,
       count(*) FILTER (WHERE s.status_name = 'Completed') AS completed,
       count(*) FILTER (WHERE s.status_name = 'Cancelled') AS cancelled
FROM category c
JOIN maintenance_team t ON t.team_id = c.team_id
LEFT JOIN maintenance_request m ON m.category_id = c.category_id
LEFT JOIN status s ON s.status_id = m.status_id
GROUP BY c.category_name, t.team_name;
```

**Check the data:**

```sql
SELECT * FROM v_category_summary ORDER BY total DESC, category_name;
```

Expected: all seeded categories, including categories with zero requests. `pending + open + completed + cancelled` should equal `total` for each category, assuming every request uses one of those workflow statuses.

### 5.5 `v_team_summary` — request totals and completion time per team

**What it does:** Summarizes pending, open, and completed requests per maintenance team. It also calculates average completion time in hours for completed requests.

`EXTRACT(EPOCH FROM (completed_on - reported_on)) / 3600` converts the time interval into hours. `AVG` ignores `NULL` values, so a team with no completed requests has a `NULL` average.

```sql
CREATE OR REPLACE VIEW v_team_summary AS
SELECT t.team_name,
       count(*) FILTER (WHERE s.status_name = 'Pending') AS pending,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open,
       count(*) FILTER (WHERE s.status_name = 'Completed') AS completed,
       round(avg(EXTRACT(EPOCH FROM (m.completed_on - m.reported_on)) / 3600)
             FILTER (WHERE s.status_name = 'Completed'), 1) AS avg_hours_to_complete
FROM maintenance_team t
LEFT JOIN category c ON c.team_id = t.team_id
LEFT JOIN maintenance_request m ON m.category_id = c.category_id
LEFT JOIN status s ON s.status_id = m.status_id
GROUP BY t.team_name;
```

**Check the data:**

```sql
SELECT *
FROM v_team_summary
ORDER BY avg_hours_to_complete DESC NULLS LAST;
```

Expected: all seeded teams. `avg_hours_to_complete` can legitimately be `NULL` if a team has no completed requests.

## 6. Helper functions (2)

A PostgreSQL function is called inside an SQL expression, often with `SELECT`. These two functions return values/results and do not perform the main workflow updates.

### 6.1 `fn_status_id(text)`

**What it does:** Looks up the numeric `status_id` for a status name. This avoids hard-coding identity values such as `1` or `2`, which may differ between databases.

```sql
CREATE OR REPLACE FUNCTION fn_status_id(p_name text)
RETURNS bigint
LANGUAGE sql STABLE AS $$
    SELECT status_id
    FROM status
    WHERE status_name = p_name
$$;
```

**Check the function:**

```sql
SELECT fn_status_id('Pending') AS pending_id,
       fn_status_id('In Progress') AS in_progress_id,
       fn_status_id('Completed') AS completed_id,
       fn_status_id('DoesNotExist') AS missing;
```

Expected: the first three return matching IDs; the unknown status returns `NULL`.

### 6.2 `fn_team_technicians(bigint)`

**What it does:** Accepts a category ID and returns technicians belonging to the team responsible for that category. It includes each technician's open-job count and sorts the least busy technician first. This can supply the admin's assignment dropdown.

```sql
CREATE OR REPLACE FUNCTION fn_team_technicians(p_category_id bigint)
RETURNS TABLE (
    personnel_id bigint,
    technician_name text,
    open_jobs bigint
)
LANGUAGE sql STABLE AS $$
    SELECT w.personnel_id, w.technician_name::text, w.open_total
    FROM v_technician_workload w
    JOIN maintenance_personnel mp ON mp.personnel_id = w.personnel_id
    JOIN category c ON c.team_id = mp.team_id
    WHERE c.category_id = p_category_id
    ORDER BY w.open_total, w.technician_name
$$;
```

**Check the function:**

```sql
SELECT *
FROM fn_team_technicians(
    (SELECT category_id
     FROM category
     WHERE category_name = 'Scientific & Test Equipment')
);
```

Expected: technicians from the team responsible for that category, ordered by open jobs. The exact order depends on current workload.

**Check an invalid category ID:**

```sql
SELECT * FROM fn_team_technicians(-1);
```

Expected: zero rows, not an error.

## 7. Trigger and trigger function (1 + 1)

### 7.1 What the trigger listens for

The trigger is attached to `maintenance_request` and is configured as:

- `AFTER INSERT`: when a new request row is inserted.
- `AFTER UPDATE OF status_id`: when an UPDATE statement targets the `status_id` column.
- `FOR EACH ROW`: the trigger function is called for each affected row.

A subtle point: `UPDATE OF status_id` means the column was included in the `SET` list. It does not guarantee the value actually changed. The function's `NEW.status_id <> OLD.status_id` check prevents a duplicate history row when the value remains the same.

### 7.2 What the trigger function does

The trigger function reads two transaction-local settings:

- `app.user_id`: the ID of the user who performed the action.
- `app.remarks`: a note describing the action.

The stored procedures set these values with `set_config(..., true)`. The final `true` means the setting is local to the current transaction.

On INSERT, the function uses the requester account as the actor if `app.user_id` is blank, and defaults the remarks to `Request submitted`.

On a real status change, it inserts the old and new status IDs, actor, and remarks into `request_status_history`. If the actor setting is missing, it raises an exception.

### 7.3 Trigger function code

```sql
CREATE OR REPLACE FUNCTION trg_log_status_change()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_user bigint := NULLIF(current_setting('app.user_id', true), '')::bigint;
    v_remarks text := NULLIF(current_setting('app.remarks', true), '');
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_user := COALESCE(
            v_user,
            (SELECT user_id
             FROM requester
             WHERE requester_id = NEW.requester_id)
        );

        INSERT INTO request_status_history
            (request_id, old_status_id, new_status_id, changed_by, remarks)
        VALUES
            (NEW.request_id, NULL, NEW.status_id, v_user,
             COALESCE(v_remarks, 'Request submitted'));

    ELSIF NEW.status_id <> OLD.status_id THEN
        IF v_user IS NULL THEN
            RAISE EXCEPTION
                'Change status through the procedures (who made the change is unknown)';
        END IF;

        INSERT INTO request_status_history
            (request_id, old_status_id, new_status_id, changed_by, remarks)
        VALUES
            (NEW.request_id, OLD.status_id, NEW.status_id, v_user, v_remarks);
    END IF;

    RETURN NULL; -- AFTER trigger: return value is ignored
END;
$$;
```

### 7.4 Create the trigger

```sql
DROP TRIGGER IF EXISTS trg_log_status_change ON maintenance_request;

CREATE TRIGGER trg_log_status_change
AFTER INSERT OR UPDATE OF status_id ON maintenance_request
FOR EACH ROW
EXECUTE FUNCTION trg_log_status_change();
```

### 7.5 Check that the trigger exists

```sql
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table = 'maintenance_request'
  AND trigger_name = 'trg_log_status_change'
ORDER BY event_manipulation;
```

Expected: two event rows (`INSERT` and `UPDATE`), representing one trigger.

### 7.6 Check that the trigger is doing its job

After calling one of the procedures that changes a request's status, query:

```sql
SELECT request_id, title, old_status, new_status,
       changed_by_name, changed_by_role, changed_at, remarks
FROM v_request_history
ORDER BY changed_at DESC
LIMIT 20;
```

You should see the latest status transition. The history row is inserted automatically by the trigger function.

### 7.7 Important limitation: this trigger is an audit mechanism, not complete security

The function checks that `app.user_id` is supplied for status changes. However, a database session that has permission to run arbitrary SQL can also set a custom setting such as `app.user_id` itself. Therefore, this trigger **does not prove that the supplied actor is genuinely logged in**, and it does not technically force every caller to use a stored procedure.

For a real application, the backend must authenticate the user, derive the user ID from the verified session (not trust an ID sent by the browser), and restrict direct table updates through database privileges. The procedures should also validate the actor's role and active status. This is an important point to mention in your project defense.

## 8. Stored procedures (5)

A stored procedure is a named set of SQL statements stored in PostgreSQL. Unlike a function, it is invoked with `CALL` and is commonly used to perform operations such as INSERT or UPDATE.

Your procedures implement the request workflow:

```text
Pending
   |
   | Admin assigns technician
   v
Assigned
   |
   | Technician starts
   v
In Progress <------> On Hold
   |
   | Technician completes
   v
Completed

Any open status can be cancelled by admin.
A requester can cancel only their own Pending request.
```

### 8.1 `sp_submit_request` — submit a new request

**Who:** Requester.

**What it does:** Inserts a maintenance request and sets its initial status to `Pending`. The trigger automatically creates the first history row and identifies the requester as the actor.

```sql
CREATE OR REPLACE PROCEDURE sp_submit_request(
    p_requester_id bigint, p_title text, p_description text,
    p_category_id bigint, p_priority_id bigint, p_location_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    -- the trigger will record the requester as the person who made the change
    PERFORM set_config('app.user_id', '', true);
    PERFORM set_config('app.remarks', '', true);

    INSERT INTO maintenance_request
        (title, description, requester_id, category_id, priority_id, location_id, status_id)
    VALUES
        (p_title, p_description, p_requester_id, p_category_id, p_priority_id, p_location_id,
         fn_status_id('Pending'));
END;
$$;
```

**Example call:** Use IDs that exist in your database. This query finds them by name rather than assuming identity values.

```sql
CALL sp_submit_request(
    (SELECT requester_id FROM requester r JOIN app_user u USING (user_id)
     WHERE u.email = 'pema.ece@cst.edu.bt'),
    'Test request from Neon',
    'Testing the stored procedure and automatic history trigger.',
    (SELECT category_id FROM category WHERE category_name = 'Scientific & Test Equipment'),
    (SELECT priority_id FROM priority WHERE priority_name = 'Medium'),
    (SELECT location_id FROM location WHERE room_no = 'ECE-LAB1')
);
```

**Check:**

```sql
SELECT request_id, title, requester_name, status_name
FROM v_request_details
WHERE title = 'Test request from Neon'
ORDER BY request_id DESC;
```

Then check its first history row in `v_request_history`; it should show `NULL -> Pending`.

### 8.2 `sp_assign_request` — admin assigns a technician

**Who:** Active admin.

**What it does:** Checks that the request exists and is Pending, checks that the selected technician belongs to the team responsible for the request category, records the admin and assignment remark, then updates the technician and status to `Assigned`.

**Improvement included below:** The original procedure trusted the supplied `p_admin_user_id` without checking that the account was actually an active admin. The version below adds that check. It still assumes the application passes the authenticated user's ID securely.

```sql
CREATE OR REPLACE PROCEDURE sp_assign_request(
    p_request_id bigint, p_personnel_id bigint, p_admin_user_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_ok     boolean;
    v_role   text;
    v_active boolean;
BEGIN
    -- Confirm the supplied actor is an active admin.
    SELECT system_role, is_active INTO v_role, v_active
    FROM app_user WHERE user_id = p_admin_user_id;

    IF v_role IS DISTINCT FROM 'admin' OR v_active IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'An active admin account is required to assign requests';
    END IF;

    SELECT s.status_name INTO v_status
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    ELSIF v_status <> 'Pending' THEN
        RAISE EXCEPTION 'Only Pending requests can be assigned (this one is %)', v_status;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM maintenance_request m
        JOIN category c ON c.category_id = m.category_id
        JOIN maintenance_personnel mp ON mp.team_id = c.team_id
        WHERE m.request_id = p_request_id AND mp.personnel_id = p_personnel_id
    ) INTO v_ok;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'This technician is not in the team that handles this category';
    END IF;

    PERFORM set_config('app.user_id', p_admin_user_id::text, true);
    PERFORM set_config('app.remarks',
        'Assigned to ' || (SELECT name FROM maintenance_personnel WHERE personnel_id = p_personnel_id), true);

    UPDATE maintenance_request
    SET personnel_id = p_personnel_id, status_id = fn_status_id('Assigned')
    WHERE request_id = p_request_id;
END;
$$;
```

**Example call:** Replace the request title if you are using a different Pending request.

```sql
CALL sp_assign_request(
    (SELECT request_id FROM maintenance_request
     WHERE title = 'Test request from Neon'
     ORDER BY request_id DESC LIMIT 1),
    (SELECT personnel_id FROM maintenance_personnel
     WHERE name = 'Jamyang Tenzin'),
    (SELECT user_id FROM app_user
     WHERE email = 'admin.estate@cst.edu.bt' AND is_active = TRUE)
);
```

**Check:**

```sql
SELECT request_id, title, status_name, technician_name
FROM v_request_details
WHERE title = 'Test request from Neon'
ORDER BY request_id DESC;
```

Expected: status `Assigned` and the selected technician's name.

### 8.3 `sp_update_status` — technician starts, pauses, or resumes work

**Who:** Technician assigned to the request.

**Allowed transitions:** `Assigned -> In Progress`, `In Progress -> On Hold`, and `On Hold -> In Progress`. A reason is mandatory when moving to `On Hold`.

```sql
CREATE OR REPLACE PROCEDURE sp_update_status(
    p_request_id bigint, p_personnel_id bigint, p_new_status text, p_remarks text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_owner  bigint;
BEGIN
    SELECT s.status_name, m.personnel_id INTO v_status, v_owner
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;
    IF v_owner IS DISTINCT FROM p_personnel_id THEN
        RAISE EXCEPTION 'Request % is not assigned to you', p_request_id;
    END IF;
    IF NOT ((v_status = 'Assigned'    AND p_new_status = 'In Progress') OR
            (v_status = 'In Progress' AND p_new_status = 'On Hold')     OR
            (v_status = 'On Hold'     AND p_new_status = 'In Progress')) THEN
        RAISE EXCEPTION 'Cannot move from % to %', v_status, p_new_status;
    END IF;
    IF p_new_status = 'On Hold' AND coalesce(btrim(p_remarks), '') = '' THEN
        RAISE EXCEPTION 'Give a reason for putting the request On Hold';
    END IF;

    PERFORM set_config('app.user_id',
        (SELECT user_id FROM maintenance_personnel WHERE personnel_id = p_personnel_id)::text, true);
    PERFORM set_config('app.remarks', coalesce(p_remarks, ''), true);

    UPDATE maintenance_request SET status_id = fn_status_id(p_new_status)
    WHERE request_id = p_request_id;
END;
$$;
```

**Example calls:**

```sql
-- Start the assigned job
CALL sp_update_status(
    (SELECT request_id FROM maintenance_request
     WHERE title = 'Test request from Neon'
     ORDER BY request_id DESC LIMIT 1),
    (SELECT personnel_id FROM maintenance_personnel WHERE name = 'Jamyang Tenzin'),
    'In Progress',
    'Started inspection'
);

-- Pause the job (a reason is required)
CALL sp_update_status(
    (SELECT request_id FROM maintenance_request
     WHERE title = 'Test request from Neon'
     ORDER BY request_id DESC LIMIT 1),
    (SELECT personnel_id FROM maintenance_personnel WHERE name = 'Jamyang Tenzin'),
    'On Hold',
    'Waiting for replacement component'
);
```

**Check:** Query `v_request_details` for the request and `v_request_history` for its history. Each successful transition should add one history row.

### 8.4 `sp_complete_request` — technician completes work

**Who:** Technician assigned to the request.

**What it does:** Allows completion only when the request is `In Progress` and assigned to that technician. Requires non-empty repair details, records completion notes and the completion timestamp, and changes status to `Completed`.

**Improvement included below:** The original code did not explicitly raise a “request not found” error when the request ID did not exist. This version adds that check.

```sql
CREATE OR REPLACE PROCEDURE sp_complete_request(
    p_request_id bigint, p_personnel_id bigint, p_repair_details text, p_notes text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_owner  bigint;
BEGIN
    SELECT s.status_name, m.personnel_id INTO v_status, v_owner
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;
    IF v_owner IS DISTINCT FROM p_personnel_id THEN
        RAISE EXCEPTION 'Request % is not assigned to you', p_request_id;
    END IF;
    IF v_status <> 'In Progress' THEN
        RAISE EXCEPTION 'Only In Progress requests can be completed (this one is %)', v_status;
    END IF;
    IF coalesce(btrim(p_repair_details), '') = '' THEN
        RAISE EXCEPTION 'Repair details are required';
    END IF;

    PERFORM set_config('app.user_id',
        (SELECT user_id FROM maintenance_personnel WHERE personnel_id = p_personnel_id)::text, true);
    PERFORM set_config('app.remarks', coalesce(nullif(btrim(p_notes), ''), 'Work completed'), true);

    UPDATE maintenance_request
    SET status_id        = fn_status_id('Completed'),
        repair_details   = p_repair_details,
        completion_notes = p_notes,
        completed_on     = now()
    WHERE request_id = p_request_id;
END;
$$;
```

**Example call:** The request must currently be `In Progress`.

```sql
CALL sp_complete_request(
    (SELECT request_id FROM maintenance_request
     WHERE title = 'Test request from Neon'
     ORDER BY request_id DESC LIMIT 1),
    (SELECT personnel_id FROM maintenance_personnel WHERE name = 'Jamyang Tenzin'),
    'Replaced the faulty component and tested the equipment.',
    'All checks passed.'
);
```

**Check:**

```sql
SELECT request_id, title, status_name, repair_details,
       completion_notes, completed_on
FROM v_request_details
WHERE title = 'Test request from Neon'
ORDER BY request_id DESC;
```

Expected: `Completed`, with repair details and a completion timestamp. The trigger should also have logged the transition.

### 8.5 `sp_cancel_request` — admin or requester cancels a request

**Who:** An active admin can cancel any open request. A requester can cancel only their own request and only while it is Pending.

**What it does:** Requires a reason, prevents cancellation of already Completed or Cancelled requests, checks requester ownership/status or admin role, and changes the status to `Cancelled`.

**Improvements included below:** The original version did not explicitly reject a nonexistent request ID and used a normal `<>` comparison for ownership. The revised version checks for a missing request and uses `IS DISTINCT FROM`, which handles `NULL` safely. It also rejects missing/inactive user accounts.

```sql
CREATE OR REPLACE PROCEDURE sp_cancel_request(
    p_request_id bigint, p_user_id bigint, p_reason text)
LANGUAGE plpgsql AS $$
DECLARE
    v_role      text;
    v_status    text;
    v_requester bigint;
    v_active    boolean;
BEGIN
    SELECT system_role, is_active INTO v_role, v_active
    FROM app_user WHERE user_id = p_user_id;

    IF v_role IS NULL OR v_active IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'User does not exist or is inactive';
    END IF;
    SELECT s.status_name, m.requester_id INTO v_status, v_requester
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;

    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to cancel';
    END IF;
    IF v_status IN ('Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Request is already %', v_status;
    END IF;
    IF v_role = 'requester' THEN
        IF v_requester IS DISTINCT FROM (SELECT requester_id FROM requester WHERE user_id = p_user_id) THEN
            RAISE EXCEPTION 'You can only cancel your own requests';
        END IF;
        IF v_status <> 'Pending' THEN
            RAISE EXCEPTION 'Work has started; ask the admin to cancel';
        END IF;
    ELSIF v_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Only the requester or an admin can cancel';
    END IF;

    PERFORM set_config('app.user_id', p_user_id::text, true);
    PERFORM set_config('app.remarks', 'Cancelled: ' || p_reason, true);

    UPDATE maintenance_request SET status_id = fn_status_id('Cancelled')
    WHERE request_id = p_request_id;
END;
$$;
```

**Check:**

```sql
SELECT request_id, title, status_name
FROM v_request_details
WHERE title = 'Test request from Neon'
ORDER BY request_id DESC;
```

Then check `v_request_history` for the cancellation reason.

## 9. Testing the trigger and complete workflow

The supplied `03_simple_test.sql` is designed to test a request through the workflow inside a transaction and finish with `ROLLBACK`. This means the test data is temporary and should not remain in the database.

### 9.1 Run the supplied workflow test

Open `03_simple_test.sql` in Neon and run the entire script. It tests:

1. New request starts as Pending and gets a history row.
2. A technician from the wrong team is rejected.
3. The correct technician can be assigned.
4. A request cannot be completed directly from Assigned.
5. On Hold requires a reason.
6. A request can be paused, resumed, and completed.
7. A Completed request cannot be cancelled.
8. A requester cannot cancel another person's request.

The script prints `NOTICE` messages. Review them for PASS/FAIL. The final `ROLLBACK` removes the test request and its history rows.

### 9.2 Important improvement to the supplied test script

The supplied test uses `SELECT max(request_id)` to find the request it just inserted. This is not reliable if another user inserts a request at the same time. A safer approach is to find the row by a unique test title:

```sql
SELECT request_id
FROM maintenance_request
WHERE title = 'TEST: Multimeter display faulty'
ORDER BY request_id DESC
LIMIT 1;
```

Also, the original negative tests catch `WHEN OTHERS`, which can report PASS for an unexpected error (for example, a missing seed row). For a strong demonstration, confirm that the expected error message is the one raised, and verify that the relevant test data exists before starting the test.

### 9.3 Read the history after a test that is not rolled back

If you run a normal procedure call outside a test transaction, inspect the latest history rows with:

```sql
SELECT request_id, title, old_status, new_status,
       changed_by_name, changed_by_role, remarks, changed_at
FROM v_request_history
ORDER BY history_id DESC
LIMIT 20;
```

The supplied test script ends with `ROLLBACK`, so its test history will not be visible afterward. That is expected behavior, not a trigger failure.

## 10. Important fixes and limitations to understand

| Finding | Why it matters | Recommendation |
|---|---|---|
| Object count in the earlier guide said 13 | It grouped the trigger and trigger function together | Report 14 physical objects, or explain 13 logical features with the trigger/function grouped |
| Earlier Markdown stopped after introducing stored procedures | It did not include the five procedure explanations/code/checks | This guide completes those sections |
| Schema comment describes a BEFORE INSERT trigger | It conflicts with the supplied AFTER INSERT/UPDATE audit trigger | Update the comment; the current procedure explicitly supplies Pending |
| Original `sp_assign_request` did not verify admin role | A caller could supply another user's ID as the supposed admin actor | Revised procedure checks active admin role |
| Original `sp_complete_request` did not explicitly handle missing request IDs | Error could be misleading or the update could affect zero rows | Revised procedure checks `v_status IS NULL` first |
| Original `sp_cancel_request` did not explicitly handle missing requests and had a NULL-sensitive ownership comparison | Missing data could slip through parts of the decision logic | Revised procedure checks the request and uses `IS DISTINCT FROM` |
| Trigger reads `app.user_id` from a custom setting | A SQL client with direct database access can set that value too | Treat this as audit metadata, not proof of authentication; enforce auth and privileges in the backend/database |
| Test uses `MAX(request_id)` | Another concurrent insert could cause it to select the wrong request | Find the inserted row by a unique test title or return its ID explicitly |

### Security note for your project defense

The procedures contain useful **business-rule checks**, but parameter values such as `p_admin_user_id` and `p_personnel_id` are not proof of identity by themselves. A real web application must obtain the logged-in user's identity from a verified server-side session/token, not accept a role or user ID directly from an untrusted browser request. Restrict direct `UPDATE` access to the base tables and grant the application only the permissions it needs. For stronger database-level enforcement, consider using a carefully designed trusted database role/security model.

## 11. Useful quick checks for Neon

### Count requests by status

```sql
SELECT s.status_name, count(*) AS request_count
FROM maintenance_request m
JOIN status s ON s.status_id = m.status_id
GROUP BY s.status_name
ORDER BY request_count DESC;
```

### Show latest requests with readable names

```sql
SELECT request_id, title, requester_name, team_name,
       priority_name, status_name, technician_name, reported_on
FROM v_request_details
ORDER BY reported_on DESC
LIMIT 20;
```

### Show one request's full status history

```sql
SELECT *
FROM v_request_history
WHERE request_id = 1
ORDER BY changed_at, history_id;
```

### Show technicians from a category's team

```sql
SELECT *
FROM fn_team_technicians(
    (SELECT category_id FROM category
     WHERE category_name = 'Scientific & Test Equipment')
);
```

### Check whether any completed requests are missing completion timestamps

```sql
SELECT m.request_id, m.title, s.status_name, m.completed_on
FROM maintenance_request m
JOIN status s ON s.status_id = m.status_id
WHERE s.status_name = 'Completed'
  AND m.completed_on IS NULL;
```

Expected: zero rows for correctly completed requests.

## 12. Quick revision: how to explain each object in your presentation

- **View:** “A view is a saved SELECT query. We use views to combine related tables and present readable information without repeatedly writing long joins.”
- **Function:** “A function is reusable database code that returns a value or a set of rows. Our helper functions look up status IDs and list eligible technicians.”
- **Trigger:** “A trigger automatically runs when a configured database event occurs. Our trigger reacts to new requests and status updates.”
- **Trigger function:** “This contains the actual logic called by the trigger. It inserts an audit row into `request_status_history`.”
- **Stored procedure:** “A stored procedure is called with `CALL` and performs database operations. Our procedures implement the maintenance workflow and validate allowed status transitions.”

**The key difference to remember:** a view is for retrieving data; a function returns a value/result; a stored procedure performs an operation when called; a trigger automatically invokes a trigger function when its database event occurs.

## Appendix A. Complete supplied logic installation script

The following is the original `03_simple_logic.sql` supplied with the project. The individually documented objects above are the easier sections to study and paste separately. For installation, run this full script after schema and seed setup. **Then run the revised procedure definitions in Sections 8.2, 8.4, and 8.5 again** to apply the recommended fixes. If you rerun this original appendix afterward, it will replace those three revised procedures with the original versions.

```sql
-- =====================================================================
-- 03_simple_logic.sql   Views, one trigger, stored procedures
-- Run order: 01_schema -> 02_seed -> 03_rollback_old_logic -> 03_simple_logic
-- Safe to re-run (CREATE OR REPLACE). Tables and data are not changed.
--
-- Status workflow used by the procedures:
--   Pending -> Assigned          (admin assigns a technician)
--   Assigned -> In Progress      (technician starts)
--   In Progress <-> On Hold      (technician pauses / resumes, reason needed to pause)
--   In Progress -> Completed     (technician completes, repair details needed)
--   any open status -> Cancelled (admin; requester only while Pending)
-- =====================================================================
BEGIN;

-- ---------------------------------------------------------------------
-- 1. VIEWS
-- ---------------------------------------------------------------------

-- 1a. Every request with readable names instead of ids (used by all 3 tabs)
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

-- 1b. Status history with names (who changed what, when)
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

-- 1c. Workload per technician
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

-- 1d. Report: requests per category
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

-- 1e. Report: pending / open work per team
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

-- ---------------------------------------------------------------------
-- 2. SMALL HELPER FUNCTIONS
-- ---------------------------------------------------------------------

-- Status id from its name, e.g. fn_status_id('Pending')
CREATE OR REPLACE FUNCTION fn_status_id(p_name text)
RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT status_id FROM status WHERE status_name = p_name
$$;

-- Technicians who can take a request of this category (same team),
-- least busy first. Used by the admin's "assign" dropdown.
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

-- ---------------------------------------------------------------------
-- 3. TRIGGER: log every status change into request_status_history
--    Who made the change is passed in by the procedures below through
--    the transaction setting 'app.user_id' (and 'app.remarks').
--    New requests fall back to the requester.
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 4. STORED PROCEDURES (call with CALL ...)
-- ---------------------------------------------------------------------

-- 4a. Requester submits a request (always starts as Pending)
CREATE OR REPLACE PROCEDURE sp_submit_request(
    p_requester_id bigint, p_title text, p_description text,
    p_category_id bigint, p_priority_id bigint, p_location_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    -- the trigger will record the requester as the person who made the change
    PERFORM set_config('app.user_id', '', true);
    PERFORM set_config('app.remarks', '', true);

    INSERT INTO maintenance_request
        (title, description, requester_id, category_id, priority_id, location_id, status_id)
    VALUES
        (p_title, p_description, p_requester_id, p_category_id, p_priority_id, p_location_id,
         fn_status_id('Pending'));
END;
$$;

-- 4b. Admin assigns a Pending request to a technician of the right team
CREATE OR REPLACE PROCEDURE sp_assign_request(
    p_request_id bigint, p_personnel_id bigint, p_admin_user_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_ok     boolean;
BEGIN
    SELECT s.status_name INTO v_status
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    ELSIF v_status <> 'Pending' THEN
        RAISE EXCEPTION 'Only Pending requests can be assigned (this one is %)', v_status;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM maintenance_request m
        JOIN category c ON c.category_id = m.category_id
        JOIN maintenance_personnel mp ON mp.team_id = c.team_id
        WHERE m.request_id = p_request_id AND mp.personnel_id = p_personnel_id
    ) INTO v_ok;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'This technician is not in the team that handles this category';
    END IF;

    PERFORM set_config('app.user_id', p_admin_user_id::text, true);
    PERFORM set_config('app.remarks',
        'Assigned to ' || (SELECT name FROM maintenance_personnel WHERE personnel_id = p_personnel_id), true);

    UPDATE maintenance_request
    SET personnel_id = p_personnel_id, status_id = fn_status_id('Assigned')
    WHERE request_id = p_request_id;
END;
$$;

-- 4c. Technician moves his own request: Assigned -> In Progress,
--     In Progress -> On Hold (reason needed), On Hold -> In Progress
CREATE OR REPLACE PROCEDURE sp_update_status(
    p_request_id bigint, p_personnel_id bigint, p_new_status text, p_remarks text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_owner  bigint;
BEGIN
    SELECT s.status_name, m.personnel_id INTO v_status, v_owner
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;
    IF v_owner IS DISTINCT FROM p_personnel_id THEN
        RAISE EXCEPTION 'Request % is not assigned to you', p_request_id;
    END IF;
    IF NOT ((v_status = 'Assigned'    AND p_new_status = 'In Progress') OR
            (v_status = 'In Progress' AND p_new_status = 'On Hold')     OR
            (v_status = 'On Hold'     AND p_new_status = 'In Progress')) THEN
        RAISE EXCEPTION 'Cannot move from % to %', v_status, p_new_status;
    END IF;
    IF p_new_status = 'On Hold' AND coalesce(btrim(p_remarks), '') = '' THEN
        RAISE EXCEPTION 'Give a reason for putting the request On Hold';
    END IF;

    PERFORM set_config('app.user_id',
        (SELECT user_id FROM maintenance_personnel WHERE personnel_id = p_personnel_id)::text, true);
    PERFORM set_config('app.remarks', coalesce(p_remarks, ''), true);

    UPDATE maintenance_request SET status_id = fn_status_id(p_new_status)
    WHERE request_id = p_request_id;
END;
$$;

-- 4d. Technician completes his own In Progress request
CREATE OR REPLACE PROCEDURE sp_complete_request(
    p_request_id bigint, p_personnel_id bigint, p_repair_details text, p_notes text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_owner  bigint;
BEGIN
    SELECT s.status_name, m.personnel_id INTO v_status, v_owner
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF v_owner IS DISTINCT FROM p_personnel_id THEN
        RAISE EXCEPTION 'Request % is not assigned to you', p_request_id;
    END IF;
    IF v_status <> 'In Progress' THEN
        RAISE EXCEPTION 'Only In Progress requests can be completed (this one is %)', v_status;
    END IF;
    IF coalesce(btrim(p_repair_details), '') = '' THEN
        RAISE EXCEPTION 'Repair details are required';
    END IF;

    PERFORM set_config('app.user_id',
        (SELECT user_id FROM maintenance_personnel WHERE personnel_id = p_personnel_id)::text, true);
    PERFORM set_config('app.remarks', coalesce(nullif(btrim(p_notes), ''), 'Work completed'), true);

    UPDATE maintenance_request
    SET status_id        = fn_status_id('Completed'),
        repair_details   = p_repair_details,
        completion_notes = p_notes,
        completed_on     = now()
    WHERE request_id = p_request_id;
END;
$$;

-- 4e. Cancel: admin can cancel any open request,
--     a requester only his own and only while it is Pending
CREATE OR REPLACE PROCEDURE sp_cancel_request(
    p_request_id bigint, p_user_id bigint, p_reason text)
LANGUAGE plpgsql AS $$
DECLARE
    v_role      text;
    v_status    text;
    v_requester bigint;
BEGIN
    SELECT system_role INTO v_role FROM app_user WHERE user_id = p_user_id;
    SELECT s.status_name, m.requester_id INTO v_status, v_requester
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id;

    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to cancel';
    END IF;
    IF v_status IN ('Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Request is already %', v_status;
    END IF;
    IF v_role = 'requester' THEN
        IF v_requester <> (SELECT requester_id FROM requester WHERE user_id = p_user_id) THEN
            RAISE EXCEPTION 'You can only cancel your own requests';
        END IF;
        IF v_status <> 'Pending' THEN
            RAISE EXCEPTION 'Work has started; ask the admin to cancel';
        END IF;
    ELSIF v_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Only the requester or an admin can cancel';
    END IF;

    PERFORM set_config('app.user_id', p_user_id::text, true);
    PERFORM set_config('app.remarks', 'Cancelled: ' || p_reason, true);

    UPDATE maintenance_request SET status_id = fn_status_id('Cancelled')
    WHERE request_id = p_request_id;
END;
$$;

COMMIT;
```

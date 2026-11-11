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

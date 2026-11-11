-- =====================================================================
-- 01_schema.sql   College Maintenance Request Management Database
-- Target : PostgreSQL 15+ (tested on 16; Neon runs 15-18)
-- Safe to re-run: creates only what is missing and adds the optional
-- suggested_priority_id column to older maintenance_request tables.
-- It never drops, truncates or deletes existing data.
-- Runs as ONE transaction: if any statement fails, nothing is applied.
-- =====================================================================
BEGIN;

SET LOCAL lock_timeout = '10s';   -- fail fast instead of hanging on a lock

-- ---------------------------------------------------------------------
-- 1. app_user : login account for every actor
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_user (
    user_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    email          VARCHAR(255) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    system_role    VARCHAR(20)  NOT NULL,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_user       PRIMARY KEY (user_id),
    CONSTRAINT ck_app_user_email CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT ck_app_user_role  CHECK (system_role IN ('requester', 'technician', 'admin'))
);

-- ---------------------------------------------------------------------
-- 2. requester
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS requester (
    requester_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    name            VARCHAR(100) NOT NULL,
    phone           VARCHAR(20),
    requester_type  VARCHAR(10)  NOT NULL,
    user_id         BIGINT       NOT NULL,
    CONSTRAINT pk_requester       PRIMARY KEY (requester_id),
    CONSTRAINT uq_requester_user  UNIQUE (user_id),
    CONSTRAINT fk_requester_user  FOREIGN KEY (user_id) REFERENCES app_user (user_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_requester_name  CHECK (btrim(name) <> ''),
    CONSTRAINT ck_requester_phone CHECK (phone IS NULL OR phone ~ '^\+?[0-9 ()-]{7,20}$'),
    CONSTRAINT ck_requester_type  CHECK (requester_type IN ('student', 'staff'))
);

-- ---------------------------------------------------------------------
-- 3. maintenance_team
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maintenance_team (
    team_id      BIGINT GENERATED ALWAYS AS IDENTITY,
    team_name    VARCHAR(100) NOT NULL,
    description  VARCHAR(255),
    CONSTRAINT pk_maintenance_team      PRIMARY KEY (team_id),
    CONSTRAINT uq_maintenance_team_name UNIQUE (team_name),
    CONSTRAINT ck_maintenance_team_name CHECK (btrim(team_name) <> '')
);

-- ---------------------------------------------------------------------
-- 4. maintenance_personnel
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maintenance_personnel (
    personnel_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    name          VARCHAR(100) NOT NULL,
    phone         VARCHAR(20)  NOT NULL,
    team_id       BIGINT       NOT NULL,
    user_id       BIGINT       NOT NULL,
    CONSTRAINT pk_maintenance_personnel       PRIMARY KEY (personnel_id),
    CONSTRAINT uq_maintenance_personnel_user  UNIQUE (user_id),
    CONSTRAINT fk_maintenance_personnel_team  FOREIGN KEY (team_id) REFERENCES maintenance_team (team_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_maintenance_personnel_user  FOREIGN KEY (user_id) REFERENCES app_user (user_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_maintenance_personnel_name  CHECK (btrim(name) <> ''),
    CONSTRAINT ck_maintenance_personnel_phone CHECK (phone ~ '^\+?[0-9 ()-]{7,20}$')
);

-- ---------------------------------------------------------------------
-- 5. category
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS category (
    category_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    category_name  VARCHAR(100) NOT NULL,
    description    VARCHAR(255),
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    team_id        BIGINT       NOT NULL,
    CONSTRAINT pk_category      PRIMARY KEY (category_id),
    CONSTRAINT uq_category_name UNIQUE (category_name),
    CONSTRAINT fk_category_team FOREIGN KEY (team_id) REFERENCES maintenance_team (team_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_category_name CHECK (btrim(category_name) <> '')
);

-- ---------------------------------------------------------------------
-- 6. status
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS status (
    status_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    status_name  VARCHAR(30) NOT NULL,
    description  VARCHAR(255),
    is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_status      PRIMARY KEY (status_id),
    CONSTRAINT uq_status_name UNIQUE (status_name),
    CONSTRAINT ck_status_name CHECK (btrim(status_name) <> '')
);

-- ---------------------------------------------------------------------
-- 7. priority   (higher sort_rank = more urgent)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS priority (
    priority_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    priority_name  VARCHAR(30) NOT NULL,
    sort_rank      SMALLINT    NOT NULL,
    is_active      BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_priority      PRIMARY KEY (priority_id),
    CONSTRAINT uq_priority_name UNIQUE (priority_name),
    CONSTRAINT uq_priority_rank UNIQUE (sort_rank),
    CONSTRAINT ck_priority_name CHECK (btrim(priority_name) <> ''),
    CONSTRAINT ck_priority_rank CHECK (sort_rank > 0)
);

-- ---------------------------------------------------------------------
-- 8. location   (floor: 0 = ground, negative = basement)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS location (
    location_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    building     VARCHAR(100) NOT NULL,
    floor        SMALLINT     NOT NULL,
    room_no      VARCHAR(20)  NOT NULL,
    CONSTRAINT pk_location          PRIMARY KEY (location_id),
    CONSTRAINT uq_location_place    UNIQUE (building, floor, room_no),
    CONSTRAINT ck_location_building CHECK (btrim(building) <> ''),
    CONSTRAINT ck_location_floor    CHECK (floor BETWEEN -5 AND 50),
    CONSTRAINT ck_location_room     CHECK (btrim(room_no) <> '')
);

-- ---------------------------------------------------------------------
-- 9. maintenance_request   (central table)
--    status_id has no DEFAULT: the BEFORE INSERT trigger (03_triggers.sql)
--    sets it to 'Pending'. Until that trigger exists, supply it explicitly.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maintenance_request (
    request_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    title             VARCHAR(150) NOT NULL,
    description       TEXT         NOT NULL,
    reported_on       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    completed_on      TIMESTAMPTZ,
    repair_details    TEXT,
    completion_notes  TEXT,
    requester_id      BIGINT       NOT NULL,
    personnel_id      BIGINT,
    category_id       BIGINT       NOT NULL,
    priority_id       BIGINT       NOT NULL,
    suggested_priority_id BIGINT,
    location_id       BIGINT       NOT NULL,
    status_id         BIGINT       NOT NULL,
    CONSTRAINT pk_maintenance_request           PRIMARY KEY (request_id),
    CONSTRAINT fk_maintenance_request_requester FOREIGN KEY (requester_id) REFERENCES requester (requester_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_maintenance_request_personnel FOREIGN KEY (personnel_id) REFERENCES maintenance_personnel (personnel_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_maintenance_request_category  FOREIGN KEY (category_id) REFERENCES category (category_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_maintenance_request_priority  FOREIGN KEY (priority_id) REFERENCES priority (priority_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_maintenance_request_suggested_priority FOREIGN KEY (suggested_priority_id) REFERENCES priority (priority_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_maintenance_request_location  FOREIGN KEY (location_id) REFERENCES location (location_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_maintenance_request_status    FOREIGN KEY (status_id) REFERENCES status (status_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_maintenance_request_title     CHECK (btrim(title) <> ''),
    CONSTRAINT ck_maintenance_request_desc      CHECK (btrim(description) <> ''),
    CONSTRAINT ck_maintenance_request_completed CHECK (completed_on IS NULL OR completed_on >= reported_on)
);

-- Add the requester-proposed urgency field to databases created from an
-- earlier version of this schema. The official priority remains priority_id.
ALTER TABLE maintenance_request
    ADD COLUMN IF NOT EXISTS suggested_priority_id BIGINT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_maintenance_request_suggested_priority'
          AND conrelid = 'public.maintenance_request'::regclass
    ) THEN
        ALTER TABLE maintenance_request
            ADD CONSTRAINT fk_maintenance_request_suggested_priority
            FOREIGN KEY (suggested_priority_id) REFERENCES priority (priority_id)
            ON DELETE RESTRICT ON UPDATE RESTRICT;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- 10. request_status_history   (append-only log; enforced in 03_triggers.sql)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS request_status_history (
    history_id     BIGINT GENERATED ALWAYS AS IDENTITY,
    changed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    remarks        TEXT,
    request_id     BIGINT      NOT NULL,
    old_status_id  BIGINT,
    new_status_id  BIGINT      NOT NULL,
    changed_by     BIGINT      NOT NULL,
    CONSTRAINT pk_request_status_history         PRIMARY KEY (history_id),
    CONSTRAINT fk_request_status_history_request FOREIGN KEY (request_id) REFERENCES maintenance_request (request_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_request_status_history_old     FOREIGN KEY (old_status_id) REFERENCES status (status_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_request_status_history_new     FOREIGN KEY (new_status_id) REFERENCES status (status_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_request_status_history_user    FOREIGN KEY (changed_by) REFERENCES app_user (user_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_request_status_history_change  CHECK (old_status_id IS NULL OR old_status_id <> new_status_id)
);

-- ---------------------------------------------------------------------
-- Indexes (PostgreSQL does not index foreign keys automatically)
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_app_user_email_lower ON app_user (lower(email));
CREATE INDEX IF NOT EXISTS ix_personnel_team      ON maintenance_personnel (team_id);
CREATE INDEX IF NOT EXISTS ix_category_team       ON category (team_id);
CREATE INDEX IF NOT EXISTS ix_request_status      ON maintenance_request (status_id, reported_on);
CREATE INDEX IF NOT EXISTS ix_request_personnel   ON maintenance_request (personnel_id, status_id);
CREATE INDEX IF NOT EXISTS ix_request_requester   ON maintenance_request (requester_id, reported_on DESC);
CREATE INDEX IF NOT EXISTS ix_request_category    ON maintenance_request (category_id);
CREATE INDEX IF NOT EXISTS ix_request_priority    ON maintenance_request (priority_id);
CREATE INDEX IF NOT EXISTS ix_request_location    ON maintenance_request (location_id);
CREATE INDEX IF NOT EXISTS ix_history_request     ON request_status_history (request_id, changed_at);
CREATE INDEX IF NOT EXISTS ix_history_changed_by  ON request_status_history (changed_by);

COMMIT;

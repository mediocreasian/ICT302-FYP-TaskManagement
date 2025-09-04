-- liquibase formatted sql

-- changeset you:mgmt-0001-extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- rollback DROP EXTENSION IF EXISTS pgcrypto;

-- changeset you:mgmt-0002-types-and-core
-- enum types (guarded)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'node_type') THEN
    CREATE TYPE node_type AS ENUM ('TASK','ACTIVITY');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dep_kind') THEN
    CREATE TYPE dep_kind AS ENUM ('FINISH_TO_START');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tag_target') THEN
    CREATE TYPE tag_target AS ENUM ('ACTIVITY','TASK');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'note_target') THEN
    CREATE TYPE note_target AS ENUM ('PROJECT','CYCLE','ACTIVITY','TASK','TAG');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reminder_target') THEN
    CREATE TYPE reminder_target AS ENUM ('ACTIVITY','TASK');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reminder_channel') THEN
    CREATE TYPE reminder_channel AS ENUM ('PUSH','LIST');
  END IF;
END $$;

-- projects
CREATE TABLE project (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  name        varchar(160) NOT NULL,
  description text,
  status      varchar(20) NOT NULL DEFAULT 'ACTIVE',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_project_user ON project (user_id);

-- cycles (templates/instances)
CREATE TABLE cycle (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL,
  project_id   uuid, -- null when template
  unique_name  varchar(160) NOT NULL,
  description  text,
  start_date   date,
  end_date     date,
  is_template  boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_cycle_user_uniquename UNIQUE (user_id, unique_name)
);
CREATE INDEX IF NOT EXISTS idx_cycle_user_proj_tmpl ON cycle (user_id, project_id, is_template);

-- activities
CREATE TABLE activity (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  cycle_id    uuid NOT NULL REFERENCES cycle(id) ON DELETE CASCADE,
  title       varchar(160) NOT NULL,
  description text,
  start_at    timestamptz,
  end_at      timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_activity_cycle ON activity (cycle_id);

-- tasks
CREATE TABLE task (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  cycle_id    uuid NOT NULL REFERENCES cycle(id) ON DELETE CASCADE,
  title       varchar(160) NOT NULL,
  description text,
  due_at      timestamptz,
  status      varchar(20) NOT NULL DEFAULT 'TODO',
  time_driver boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_task_cycle ON task (cycle_id);
CREATE INDEX IF NOT EXISTS idx_task_cycle_due ON task (cycle_id, due_at);
CREATE INDEX IF NOT EXISTS idx_task_user_status ON task (user_id, status);

-- dependencies (graph edges inside a cycle)
CREATE TABLE dependency (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id    uuid NOT NULL REFERENCES cycle(id) ON DELETE CASCADE,
  source_type node_type NOT NULL,
  source_id   uuid NOT NULL,
  target_type node_type NOT NULL,
  target_id   uuid NOT NULL,
  kind        dep_kind NOT NULL DEFAULT 'FINISH_TO_START',
  CONSTRAINT uq_dependency UNIQUE (cycle_id, source_type, source_id, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS idx_dependency_cycle ON dependency (cycle_id);

-- tags and links
CREATE TABLE tag (
  id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  name   varchar(80) NOT NULL,
  color  varchar(16),
  CONSTRAINT uq_tag_user_name UNIQUE (user_id, name)
);

CREATE TABLE tag_link (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tag_id      uuid NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
  target_type tag_target NOT NULL,
  target_id   uuid NOT NULL,
  CONSTRAINT uq_tag_link UNIQUE (tag_id, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS idx_tag_link_tag ON tag_link (tag_id, target_type);

-- notes (polymorphic)
CREATE TABLE note (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  target_type note_target NOT NULL,
  target_id   uuid NOT NULL,
  body        text NOT NULL,
  created_by  uuid NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_note_target ON note (target_type, target_id);

-- reminders
CREATE TABLE reminder (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  target_type reminder_target NOT NULL,
  target_id   uuid NOT NULL,
  remind_at   timestamptz,
  cron_expr   varchar(120),
  channel     reminder_channel NOT NULL DEFAULT 'PUSH',
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_reminder_due ON reminder (active, remind_at);
CREATE INDEX IF NOT EXISTS idx_reminder_target ON reminder (user_id, target_type, target_id);

-- outbox (for reliable push)
CREATE TABLE outbox_event (
  id           bigserial PRIMARY KEY,
  topic        varchar(80) NOT NULL,
  payload      jsonb NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_outbox_topic_processed ON outbox_event (topic, processed_at);

-- rollback
-- DROP TABLE IF EXISTS outbox_event;
-- DROP TABLE IF EXISTS reminder;
-- DROP TABLE IF EXISTS note;
-- DROP TABLE IF EXISTS tag_link;
-- DROP TABLE IF EXISTS tag;
-- DROP TABLE IF EXISTS dependency;
-- DROP TABLE IF EXISTS task;
-- DROP TABLE IF EXISTS activity;
-- DROP TABLE IF EXISTS cycle;
-- DROP TABLE IF EXISTS project;
-- DO $$
-- BEGIN
--   IF EXISTS (SELECT 1 FROM pg_type WHERE typname='reminder_channel') THEN DROP TYPE reminder_channel; END IF;
--   IF EXISTS (SELECT 1 FROM pg_type WHERE typname='reminder_target') THEN DROP TYPE reminder_target; END IF;
--   IF EXISTS (SELECT 1 FROM pg_type WHERE typname='note_target') THEN DROP TYPE note_target; END IF;
--   IF EXISTS (SELECT 1 FROM pg_type WHERE typname='tag_target') THEN DROP TYPE tag_target; END IF;
--   IF EXISTS (SELECT 1 FROM pg_type WHERE typname='dep_kind') THEN DROP TYPE dep_kind; END IF;
--   IF EXISTS (SELECT 1 FROM pg_type WHERE typname='node_type') THEN DROP TYPE node_type; END IF;
-- END $$;

-- liquibase formatted sql

-- changeset you:usersvc-0001-extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- rollback DROP EXTENSION IF EXISTS pgcrypto;

-- changeset you:usersvc-0002-core
-- users
CREATE TABLE app_user (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         varchar(255) UNIQUE NOT NULL,
  name          varchar(120),
  password_hash text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_app_user_email ON app_user (email);

-- login codes (for OTP/magic link)
CREATE TABLE login_code (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  code_hash   text NOT NULL,
  expires_at  timestamptz NOT NULL,
  consumed    boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_login_code_user_exp ON login_code (user_id, expires_at);

-- devices (FCM tokens)
CREATE TABLE device (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  fcm_token    text NOT NULL UNIQUE,
  platform     varchar(20) NOT NULL DEFAULT 'ANDROID',
  last_seen_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_device_user ON device (user_id);

-- notification preferences
CREATE TABLE notification_pref (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  project_id  uuid, -- nullable = global
  push_opt_in boolean NOT NULL DEFAULT true,
  quiet_hours jsonb
);
ALTER TABLE notification_pref
  ADD CONSTRAINT uq_notifpref_user_project UNIQUE (user_id, project_id);
CREATE INDEX IF NOT EXISTS idx_notifpref_user_project ON notification_pref (user_id, project_id);
-- rollback
-- DROP TABLE IF EXISTS notification_pref;
-- DROP TABLE IF EXISTS device;
-- DROP TABLE IF EXISTS login_code;
-- DROP TABLE IF EXISTS app_user;

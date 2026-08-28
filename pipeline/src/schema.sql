-- CoasterHunter seed database.
-- Ships read-only inside the app bundle; mirrored into Supabase for the parts
-- that need to be queried server-side (credit gap finder, leaderboards).
--
-- All measurements are metric. Every row that came from an outside source has
-- at least one matching row in `attributions` — the emitter fails the build if
-- that is not true.

PRAGMA journal_mode = OFF;
PRAGMA synchronous  = OFF;

CREATE TABLE meta (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL
);

CREATE TABLE sources (
  key         TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  url         TEXT NOT NULL,
  licence     TEXT NOT NULL
);

CREATE TABLE destinations (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  slug        TEXT
);

CREATE TABLE parks (
  id            TEXT PRIMARY KEY,
  destination_id TEXT REFERENCES destinations(id),
  name          TEXT NOT NULL,
  name_norm     TEXT NOT NULL,
  country       TEXT,
  latitude      REAL,
  longitude     REAL,
  timezone      TEXT,
  opened_year   INTEGER,
  external_id   TEXT
);

CREATE TABLE park_areas (
  id          INTEGER PRIMARY KEY,
  park_id     TEXT NOT NULL REFERENCES parks(id),
  name        TEXT NOT NULL,
  UNIQUE (park_id, name)
);

CREATE TABLE manufacturers (
  id          INTEGER PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  name_norm   TEXT NOT NULL
);

CREATE TABLE models (
  id              INTEGER PRIMARY KEY,
  manufacturer_id INTEGER REFERENCES manufacturers(id),
  name            TEXT NOT NULL,
  UNIQUE (manufacturer_id, name)
);

-- kind: coaster | dark | flat | water | show | transport | other
CREATE TABLE attractions (
  id            TEXT PRIMARY KEY,
  park_id       TEXT NOT NULL REFERENCES parks(id),
  area_id       INTEGER REFERENCES park_areas(id),
  name          TEXT NOT NULL,
  name_norm     TEXT NOT NULL,
  kind          TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'operating',
  latitude      REAL,
  longitude     REAL,
  external_id   TEXT,
  has_specs     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE attraction_specs (
  attraction_id          TEXT PRIMARY KEY REFERENCES attractions(id),
  manufacturer_id        INTEGER REFERENCES manufacturers(id),
  model_id               INTEGER REFERENCES models(id),
  designer               TEXT,
  track_type             TEXT,
  lift_type              TEXT,
  opened_year            INTEGER,
  closed_year            INTEGER,
  height_m               REAL,
  drop_m                 REAL,
  length_m               REAL,
  speed_kmh              REAL,
  inversions             INTEGER,
  duration_seconds       INTEGER,
  max_angle_deg          REAL,
  max_g_force            REAL,
  capacity_per_hour      INTEGER,
  height_restriction_cm  INTEGER,
  trains                 INTEGER,
  cars_per_train         INTEGER,
  rows_per_car           INTEGER,
  riders_per_row         INTEGER,
  single_rider           INTEGER,
  wheelchair_accessible  INTEGER,
  must_transfer          INTEGER,
  previous_names         TEXT
);

-- Lets us re-sync from a source without redoing entity resolution.
CREATE TABLE external_ids (
  entity_kind TEXT NOT NULL,      -- park | attraction
  entity_id   TEXT NOT NULL,
  source_key  TEXT NOT NULL REFERENCES sources(key),
  source_id   TEXT NOT NULL,
  PRIMARY KEY (entity_kind, entity_id, source_key)
);

CREATE TABLE attributions (
  entity_kind TEXT NOT NULL,
  entity_id   TEXT NOT NULL,
  source_key  TEXT NOT NULL REFERENCES sources(key),
  url         TEXT,
  PRIMARY KEY (entity_kind, entity_id, source_key)
);

CREATE INDEX idx_parks_dest        ON parks(destination_id);
CREATE INDEX idx_parks_norm        ON parks(name_norm);
CREATE INDEX idx_parks_coord       ON parks(latitude, longitude);
CREATE INDEX idx_attr_park         ON attractions(park_id);
CREATE INDEX idx_attr_kind         ON attractions(park_id, kind);
CREATE INDEX idx_attr_norm         ON attractions(name_norm);
CREATE INDEX idx_attr_coord        ON attractions(latitude, longitude);
CREATE INDEX idx_specs_maker       ON attraction_specs(manufacturer_id);
CREATE INDEX idx_ext_lookup        ON external_ids(source_key, source_id);

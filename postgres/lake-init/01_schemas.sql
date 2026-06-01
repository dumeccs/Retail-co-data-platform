CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS meta;

CREATE TABLE IF NOT EXISTS meta.watermarks (
    entity_name      VARCHAR(100) PRIMARY KEY,
    last_updated_at  TIMESTAMPTZ  NOT NULL,
    last_run_at      TIMESTAMPTZ  DEFAULT NOW(),
    rows_extracted   INTEGER      DEFAULT 0
);

COMMENT ON SCHEMA raw  IS 'Raw ERP entity tables written by the Python extractor.';
COMMENT ON SCHEMA meta IS 'Pipeline operational metadata — watermarks, audit logs. Kept separate from raw so dlt never replicates it.';
COMMENT ON TABLE meta.watermarks IS 'Tracks last successful extract timestamp per entity. No row = first run = full extract.';
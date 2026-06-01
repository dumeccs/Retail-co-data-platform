"""Writes raw ERP rows into lake Postgres `raw` schema and manages watermarks.

Landing model: raw.<entity>(id, data JSONB, updated_at, extracted_at).
Idempotent via ON CONFLICT (id) DO UPDATE. Watermarks in meta.watermarks.
"""
from __future__ import annotations
import logging
from datetime import datetime, timezone

import psycopg2
from psycopg2 import sql
from psycopg2.extras import Json, execute_values

logger = logging.getLogger(__name__)


class LakeWriter:
    def __init__(self, dsn):
        self.conn = psycopg2.connect(dsn)
        self.conn.autocommit = False

    def close(self):
        self.conn.close()

    def ensure_table(self, entity):
        ddl = sql.SQL("""
            CREATE TABLE IF NOT EXISTS raw.{tbl} (
                id           TEXT PRIMARY KEY,
                data         JSONB       NOT NULL,
                updated_at   TIMESTAMPTZ,
                extracted_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
        """).format(tbl=sql.Identifier(entity))
        with self.conn.cursor() as cur:
            cur.execute(ddl)
        self.conn.commit()

    def get_watermark(self, entity):
        with self.conn.cursor() as cur:
            cur.execute("SELECT last_updated_at FROM meta.watermarks WHERE entity_name = %s", (entity,))
            row = cur.fetchone()
        return row[0] if row else None

    def upsert_rows(self, entity, rows):
        """rows: list of (id, data_dict, updated_at_dt). Returns count written."""
        if not rows:
            return 0
        query = sql.SQL("""
            INSERT INTO raw.{tbl} (id, data, updated_at, extracted_at)
            VALUES %s
            ON CONFLICT (id) DO UPDATE SET
                data         = EXCLUDED.data,
                updated_at   = EXCLUDED.updated_at,
                extracted_at = EXCLUDED.extracted_at
        """).format(tbl=sql.Identifier(entity)).as_string(self.conn)
        now = datetime.now(timezone.utc)
        values = [(rid, Json(rdata), rupd, now) for (rid, rdata, rupd) in rows]
        with self.conn.cursor() as cur:
            execute_values(cur, query, values, template="(%s, %s, %s, %s)", page_size=500)
        return len(values)

    def set_watermark(self, entity, last_updated_at, rows_extracted):
        with self.conn.cursor() as cur:
            cur.execute("""
                INSERT INTO meta.watermarks (entity_name, last_updated_at, last_run_at, rows_extracted)
                VALUES (%s, %s, now(), %s)
                ON CONFLICT (entity_name) DO UPDATE SET
                    last_updated_at = GREATEST(meta.watermarks.last_updated_at, EXCLUDED.last_updated_at),
                    last_run_at     = now(),
                    rows_extracted  = EXCLUDED.rows_extracted
            """, (entity, last_updated_at, rows_extracted))

    def commit(self):
        self.conn.commit()

    def rollback(self):
        self.conn.rollback()
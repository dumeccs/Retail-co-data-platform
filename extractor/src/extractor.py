"""Orchestrates extraction of all ERP entities into the lake.

Standalone: python -m extractor.src.extractor
From Airflow: from extractor.src.extractor import extract_all
"""
from __future__ import annotations
import logging
import os
from datetime import datetime, timezone

from .erp_client import ERPClient
from .lake_writer import LakeWriter

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("extractor")

# entity_name (= lake table) -> API path.  >>> VERIFY PATHS AT /docs/json <
ENTITIES = {
    "stores":              "stores",
    "employees":           "employees",
    "payment_methods":     "payment_methods",
    "customers":           "customers",
    "products":            "products",
    "orders":              "orders",
    "order_items":         "order_items",
    "payments":            "payments",
    "inventory_movements": "inventory_movements",
}
BATCH_SIZE = 500


def _parse_ts(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)   # 3.11 handles trailing 'Z'
    except (ValueError, TypeError):
        return None


def _iso_z(dt):
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _lake_dsn():
    return (
        f"host={os.environ['LAKE_POSTGRES_HOST']} "
        f"port={os.environ.get('LAKE_POSTGRES_PORT', '5432')} "
        f"dbname={os.environ['LAKE_POSTGRES_DB']} "
        f"user={os.environ['LAKE_POSTGRES_USER']} "
        f"password={os.environ['LAKE_POSTGRES_PASSWORD']}"
    )


def extract_entity(client, writer, entity, path):
    writer.ensure_table(entity)
    watermark = writer.get_watermark(entity)
    updated_after = _iso_z(watermark) if watermark else None
    logger.info("Extracting %s [%s] updated_after=%s",
                entity, "incremental" if updated_after else "full", updated_after)

    batch, total, max_seen = [], 0, watermark
    try:
        for row in client.fetch_entity(path, updated_after=updated_after):
            rid = row.get("id")
            if rid is None:
                logger.warning("  %s: row without id, skipping", entity)
                continue
            upd = _parse_ts(row.get("updatedAt") or row.get("updated_at"))
            if upd and (max_seen is None or upd > max_seen):
                max_seen = upd
            batch.append((str(rid), row, upd))
            if len(batch) >= BATCH_SIZE:
                total += writer.upsert_rows(entity, batch)
                batch.clear()
        if batch:
            total += writer.upsert_rows(entity, batch)

        if max_seen is not None:
            writer.set_watermark(entity, max_seen, total)
        writer.commit()                      # atomic per entity
        logger.info("  %s done: %d rows, watermark=%s", entity, total, max_seen)
        return total
    except Exception:
        writer.rollback()                    # failure => watermark unchanged
        logger.exception("  %s failed; rolled back", entity)
        raise


def extract_all(entities=None):
    client = ERPClient(os.environ["ERP_BASE_URL"], os.environ["ERP_API_KEY"])
    writer = LakeWriter(_lake_dsn())
    results = {}
    try:
        for entity in (entities or list(ENTITIES.keys())):
            results[entity] = extract_entity(client, writer, entity, ENTITIES[entity])
    finally:
        writer.close()
    logger.info("Extraction summary: %s", results)
    return results


if __name__ == "__main__":
    extract_all()
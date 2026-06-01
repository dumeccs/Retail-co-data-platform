"""dlt pipeline: lake (raw, JSONB) -> warehouse (raw, typed columns).

Per entity: read lake.raw.<entity> filtered by the incremental cursor,
unpack the JSONB payload, and merge into warehouse raw on id.
dlt infers/coerces column types and snake_cases the camelCase keys.
"""
from __future__ import annotations
import os

import dlt
import psycopg2
from psycopg2.extras import RealDictCursor

ENTITIES = [
    "stores", "employees", "payment_methods", "customers", "products",
    "orders", "order_items", "payments", "inventory_movements",
]
INITIAL_CURSOR = "1970-01-01T00:00:00.000Z"
READ_BATCH = 5000


def _lake_dsn():
    return (
        f"host={os.environ['LAKE_POSTGRES_HOST']} "
        f"port={os.environ.get('LAKE_POSTGRES_PORT', '5432')} "
        f"dbname={os.environ['LAKE_POSTGRES_DB']} "
        f"user={os.environ['LAKE_POSTGRES_USER']} "
        f"password={os.environ['LAKE_POSTGRES_PASSWORD']}"
    )


def _warehouse_conn_str():
    return (
        f"postgresql://{os.environ['WAREHOUSE_POSTGRES_USER']}:"
        f"{os.environ['WAREHOUSE_POSTGRES_PASSWORD']}@"
        f"{os.environ['WAREHOUSE_POSTGRES_HOST']}:"
        f"{os.environ.get('WAREHOUSE_POSTGRES_PORT', '5432')}/"
        f"{os.environ['WAREHOUSE_POSTGRES_DB']}"
    )


def _make_resource(entity):
    @dlt.resource(name=entity, primary_key="id", write_disposition="merge")
    def resource(cursor=dlt.sources.incremental("updatedAt", initial_value=INITIAL_CURSOR)):
        # push the high-water mark into the lake query (no full-table scan)
        query = (
            f"SELECT data FROM raw.{entity} "
            f"WHERE updated_at >= %s::timestamptz ORDER BY updated_at"
        )
        conn = psycopg2.connect(_lake_dsn())
        try:
            with conn.cursor(name=f"srv_{entity}", cursor_factory=RealDictCursor) as cur:
                cur.itersize = READ_BATCH
                cur.execute(query, (cursor.last_value,))
                for row in cur:
                    yield row["data"]          # unpacked JSON dict; dlt types it
        finally:
            conn.close()
    return resource


@dlt.source(name="erp_lake")
def lake_source():
    return [_make_resource(e) for e in ENTITIES]


def run():
    pipeline = dlt.pipeline(
        pipeline_name="lake_to_warehouse",
        destination=dlt.destinations.postgres(credentials=_warehouse_conn_str()),
        dataset_name="raw",
    )
    info = pipeline.run(lake_source())
    print(info)
    return info


if __name__ == "__main__":
    run()
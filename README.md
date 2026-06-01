Here's the full README — comprehensive enough that someone new can understand the why, reproduce it from a clean clone, run and test it, and pull straight from it for the presentation. Paste it into `README.md`.

# RetailCo Data Platform

End-to-end ELT pipeline that extracts data from a legacy ERP REST API, lands it in a raw data lake, loads it to a warehouse, and transforms it into Kimball-style dimensional models — orchestrated daily with Airflow, fully containerized, and answering five weekly business questions.

---

## 1. What this is

RetailCo (a Nigerian retail chain — Lagos, Abuja, Port Harcourt, Kano) is modernising off a legacy ERP. This repo builds the data platform that powers all reporting and analytics:

**ERP API → Python extractor → Lake (Postgres) → dlt → Warehouse (Postgres) → dbt (Kimball marts) → analytics**, all run by Airflow on a `@daily` schedule.

Design artifacts (bus matrix, ERD, architecture diagram) live in [`/design`](./design).

---

## 2. Architecture

```
                          ┌─────────────────────── Apache Airflow (@daily, LocalExecutor) ───────────────────────┐
                          │  extract → load → dbt snapshot → dbt run staging → dbt run marts → dbt test           │
                          │  retries=2 (exp backoff) · fail-stops-downstream · backfill-capable                   │
                          └──────────────────────────────────────────────────────────────────────────────────────┘
   ERP REST API                Python extractor              dlt                       dbt
  (read-only, Heroku)   ──►   auth / pagination /     ──►   incremental merge,   ──►  snapshots → staging
  X-API-Key, cursor           incremental / retries        unpack JSONB →             → marts (6 dims, 4 facts)
  pagination, 429s,           upsert on id                 typed columns              → flagged_payments
  ~3% 500s                         │                            │                          │  + tests
                                   ▼                            ▼                          ▼
                          Lake Postgres                Warehouse Postgres          Warehouse Postgres
                          schema: raw (JSONB)          schema: raw (typed)         schemas: staging, snapshots, marts
                          schema: meta (watermarks)
```

Everything runs in **Docker Compose**: `lake-postgres`, `warehouse-postgres`, `airflow-postgres`, `airflow-init`, `airflow-webserver`, `airflow-scheduler`.

---

## 3. Tech stack (pinned — no substitutions)

| Layer | Tool |
|---|---|
| Orchestration | Apache Airflow 2.9.2 (python3.11), LocalExecutor |
| Extraction | Python 3.11 (hand-written: `requests`, `tenacity`, `psycopg2`) |
| Lake / Warehouse | PostgreSQL 15 (two separate containers) |
| Loading | dlt[postgres] 0.5.4 |
| Transformation | dbt-core 1.7.17 + dbt-postgres 1.7.17, `dbt_utils` |
| Containerization | Docker + Docker Compose |

---

## 4. Repository structure

```
retailco-data-platform/
├── .env.example                # template (copy to .env, fill secrets)
├── docker-compose.yml
├── design/                     # bus matrix, ERD (DBML), architecture diagram
├── postgres/
│   ├── lake-init/01_schemas.sql        # raw + meta schemas, watermarks table
│   └── warehouse-init/01_schemas.sql   # raw, staging, snapshots, marts schemas
├── airflow/
│   ├── Dockerfile              # base image + build deps + git + /opt/airflow/.dlt
│   ├── requirements.txt        # dlt, dbt, requests, tenacity, psycopg2
│   └── dags/retailco_pipeline.py       # the single orchestrating DAG
├── extractor/src/
│   ├── erp_client.py           # HTTP client: auth, pagination, retries, backoff
│   ├── lake_writer.py          # JSONB landing + watermarks (upsert on id)
│   └── extractor.py            # orchestrates all 9 entities
├── dlt_pipeline/
│   └── lake_to_warehouse.py    # incremental merge, JSONB → typed columns
└── dbt_project/
    ├── dbt_project.yml
    ├── profiles.yml            # warehouse connection from env vars
    ├── packages.yml            # dbt_utils
    ├── macros/generate_schema_name.sql
    ├── snapshots/              # snapshot_customers, snapshot_products (SCD2)
    ├── models/
    │   ├── staging/            # 9 stg_* views + _sources.yml + _staging.yml
    │   └── marts/
    │       ├── dimensions/     # dim_date, dim_customer, dim_product, dim_store, dim_employee, dim_payment_method
    │       ├── facts/          # fct_sales, fct_payments, fct_inventory_daily, fct_order_lifecycle
    │       └── data_quality/   # flagged_payments
    └── tests/                  # 4 custom singular tests (one per fact)
```

---

## 5. Prerequisites

- Docker + Docker Compose
- Your ERP **team API key**
- A Fernet key: `python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`

---

## 6. Setup & run (reproduce from a clean clone)

```bash
# 1. secrets
cp .env.example .env
#    edit .env — set (no quotes around values):
#    ERP_API_KEY=<your key>
#    ERP_BASE_URL=https://hngstage8da-55c7f5f769c8.herokuapp.com
#    AIRFLOW__CORE__FERNET_KEY=<generated key>
#    lake/warehouse/airflow Postgres user/password/db, AIRFLOW_UID=50000

# 2. build & start (init scripts create all schemas on first boot)
docker compose up -d --build

# 3. verify schemas exist (proves init scripts ran cleanly)
docker compose exec lake-postgres      psql -U lake_user      -d lake_db        -c "\dn"   # raw, meta
docker compose exec warehouse-postgres psql -U warehouse_user -d warehouse_db   -c "\dn"   # raw, staging, snapshots, marts

# 4. Airflow UI: http://localhost:8080  (admin / admin)
```

> **Reproducibility note:** Postgres only runs `/docker-entrypoint-initdb.d/*.sql` on an **empty** volume. A clean `docker compose up` creates all schemas automatically. If you ever change the init scripts, fully reset with `docker compose down -v && docker compose up -d --build` so they re-run.

---

## 7. Running the pipeline

**Via Airflow (production path):**
```bash
# one full end-to-end run for a logical date
docker compose exec airflow-scheduler airflow dags test retailco_pipeline 2024-01-01
# or unpause 'retailco_pipeline' in the UI for the @daily schedule
```

**Each stage standalone (for development/debugging):**
```bash
# extract → lake
docker compose exec airflow-scheduler bash -lc "cd /opt/airflow && python -m extractor.src.extractor"
# lake → warehouse
docker compose exec airflow-scheduler bash -lc "cd /opt/airflow && python -m dlt_pipeline.lake_to_warehouse"
# transform
docker compose exec airflow-scheduler bash -lc "cd /opt/airflow/dbt_project && dbt deps && dbt snapshot && dbt run && dbt test"
```

**Backfill a historical range:**
```bash
docker compose exec airflow-scheduler airflow dags backfill -s 2024-01-01 -e 2024-01-03 retailco_pipeline
```

---

## 8. Data model (Kimball)

**Bus matrix** (business processes × conformed dimensions):

| Fact (grain) | dim_date | dim_customer | dim_product | dim_store | dim_employee | dim_payment_method |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| **fct_sales** (order line · transactional) | X | X | X | X | X | — |
| **fct_payments** (payment event · transactional) | X | X | — | — | — | X |
| **fct_inventory_daily** (product×store×day · periodic snapshot) | X | — | X | X | — | — |
| **fct_order_lifecycle** (order · accumulating snapshot, dim_date ×5 roles) | X | X | — | X | X | — |

`flagged_payments` is a **data-quality artifact**, not a fact — natural keys only, not in the bus matrix.

**Modelling conventions:**
- **Surrogate keys** on every dimension (`dbt_utils.generate_surrogate_key` hashes); facts reference **surrogate keys only**. Natural UUIDs appear on facts only as **degenerate dimensions** (`order_id`, `payment_id`, …).
- **No NULL foreign keys.** Each dim seeds an Unknown member (`'-1'`; `dim_date` uses `date_key = 0`); unreached lifecycle milestones point to `0`.
- **SCD2** (`dim_customer`, `dim_product`) via dbt snapshots, `strategy=timestamp` on `effective_from`, exposing `valid_from`/`valid_to`/`is_current`. Soft-deleted members are **kept** as a final slice with `is_current=false` so historical facts still resolve. The **earliest slice's `valid_from` is backdated** so facts predating the first tracked change still join.
- `date_key` is an `int` YYYYMMDD smart key; `dim_date` covers 2023–2028 with Nigerian public holidays.
- Measure additivity is labelled: `[A]` additive, `[SA]` semi-additive (`on_hand_quantity`), `[NA]` non-additive (`days_*` lags, `discount_pct`).

---

## 9. Querying the warehouse

The five weekly questions are answered against `marts.*` (full query set in [`/design/insights_queries.sql`](./design) or section 13 of the original analysis). Revenue queries exclude cancelled orders (`order_status <> 'cancelled'`). Example:

```sql
-- Revenue by store
SELECT s.store_name, count(DISTINCT fs.order_id) orders,
       round(sum(fs.net_amount),2) revenue, round(sum(fs.gross_margin),2) margin
FROM marts.fct_sales fs JOIN marts.dim_store s ON s.store_key = fs.store_key
WHERE fs.order_status <> 'cancelled' GROUP BY 1 ORDER BY revenue DESC;
```

Joining a fact to a dimension by its surrogate `*_key` automatically attributes the row to the **SCD2 version valid at the time of the event** (segment/category/price as they were at sale time).

---

## 10. Key findings

1. **Revenue is steady-state** — ~2.7B NGN and ~3,200 orders per month, flat across the 24-month window (first/last months are partial). Eight categories each 7.5–9.1B net, led by Electronics; revenue spread evenly across four stores.
2. **Segments are behaviourally near-identical** — AOV 848k–859k NGN, ~15 orders/customer across wholesale/retail/corporate/vip. Current segmentation isn't capturing distinct behaviour (actionable).
3. **Discounting roughly halves margin** — full-price lines run 28.9% margin; discounted lines (avg 17.5% off) drop to 13.8%. Only ~20% of lines are discounted. Best margin: Health & Beauty (28.4%); thinnest: Food & Beverage (23.9%).
4. **Payments are digital and even** — 4 of 5 methods digital, ~20% volume each (USSD marginally leads), uniform ~2% refund rate.
5. **Data quality** — 2.03% of payments are anomalous (756 unexplained negatives ≈ −1.9M NGN, 704 zero-amount), isolated to `flagged_payments`. 107 customers + 50 products soft-deleted but retained in SCD2 dims. Lifecycle integrity is clean (milestone gaps match order status exactly).

---

## 11. Design decisions & rationale

| Decision | Why |
|---|---|
| **JSONB landing** in the lake (`raw.<entity>(id, data, updated_at, extracted_at)`) | Entity-agnostic extractor (one code path for 9 entities), trivial idempotent upsert, preserves exact source payload for replay. dlt unpacks to typed columns downstream. |
| **Watermarks in `meta` schema** (not `raw`) | Keeps operational metadata out of the data dlt replicates. |
| **dlt incremental cursor pushed into the lake SQL** | Avoids re-scanning the whole lake table each run; only new/changed rows move. |
| **`merge` on `id`** (extractor and dlt) | Idempotency + handles late-arriving order updates. |
| **`generate_schema_name` macro** | Without it dbt prefixes custom schemas (`marts_staging`); the macro writes into bare `staging`/`snapshots`/`marts`. |
| **SCD2 on `effective_from` (business-effective time), earliest slice backdated** | `valid_from` reflects when a change was actually effective; backdating the first slice ensures facts predating it still resolve (without it, ~56% of sales lost their customer). |
| **`store` removed from `fct_payments`** | The payment payload has no `storeId`; store is reachable by drilling across `order_id`. Keeps the fact grain-pure. |
| **Unknown members + no NULL FKs** | Kimball discipline — facts route missing references to a sentinel member, never NULL. |
| **Sparse `fct_inventory_daily`** | One row per product×store×day-with-movement (~344k) vs ~6M for a full calendar cross-join; arbitrary-day stock still answerable via running balance. |
| **dlt state persisted in `dlt_state` volume** | Incremental high-water mark survives container restarts, so a second run genuinely moves ~0 rows. |

---

## 12. Source quirks & how we handle them

| Quirk | Handling |
|---|---|
| `X-API-Key` auth (401 without it) | Header on every request via `requests.Session`. |
| Cursor pagination, `limit` capped at **100** | Follow `meta.cursor` until `has_more=false`; page size 100. |
| `?updated_after` incremental (mixed support — some endpoints ignore it) | Per-entity watermark; idempotent upsert makes both behaviours safe. |
| 429 rate limiting | Honor `Retry-After`, else exponential backoff (separate budget). |
| ~3% transient 500/timeout | Exponential backoff, max 5 attempts (observed firing & recovering on `order_items`). |
| snake_case endpoint paths | `payment_methods`, `order_items`, `inventory_movements`. |
| Numbers as strings (`"15775.00"`) | dlt keeps as text; dbt staging casts to `numeric`. |
| camelCase fields | dlt normalises to snake_case. |
| `phone` has a literal backslash (`\+234…`) | Stripped in staging. |
| **Inventory `quantity` is signed** (sale −, restock +) | `net = sum(quantity)`, `qty_in/qty_out` from sign; no need to map direction. |
| Soft deletes (`is_deleted`) | Filtered from facts; kept in SCD2 dims as final slice (`is_current=false`). |
| Refunds (negative `amount_paid`, `payment_type='refund'`) | Kept in `fct_payments` with `is_refund=true`. |
| Anomalous payments | `amount_paid = 0` **or** (`< 0` and not refund) → `flagged_payments`, excluded from revenue. |
| **Future-dated `updated_at`** (some 2027) | Synthetic source quirk; harmless — facts resolved with 0 unknown keys. Noted as a data-quality observation. |

---

## 13. Tradeoffs (for discussion)

- **JSONB lake vs typed lake** — chose JSONB for robustness/idempotency; the cost is dbt staging carries the casting. dlt does real type coercion into the warehouse, so types land before dbt.
- **Sparse vs dense inventory snapshot** — chose sparse (movement-days) for ~20× fewer rows; arbitrary-day stock needs a last-value-carried-forward query. Dense is the alternative if a grader requires a row per calendar day.
- **SCD2 `valid_from = effective_from`** — gives business-effective history, but a soft-delete that doesn't advance `effective_from` would only be captured via the current-state slice (acceptable; the current deleted state *is* captured and surfaced as `is_current=false`).
- **Monolithic Airflow image** (dbt + dlt + Airflow in one image) — simplest for this scope; verified compatible via `pip check`. At larger scale you'd isolate dbt/dlt behind `DockerOperator`.
- **`catchup=False` + manual backfill** — avoids an auto-backfill storm on deploy; the API is forward-only (`updated_after`), so a backfill re-syncs from the watermark rather than reconstructing a specific historical window (handled idempotently).
- **dlt pinned to 0.5.4** — reproducibility over "latest"; re-verify the incremental/merge API if bumping.

---

## 14. Testing

```bash
docker compose exec airflow-scheduler bash -lc "cd /opt/airflow/dbt_project && dbt test"   # 76 tests
```
Coverage: `not_null` + `unique` on every model's PK; `relationships` on every fact FK to its dimension; one custom singular test per fact (sales valid amounts, payments anomaly-exclusion, inventory `net = in − out`, lifecycle non-negative durations).

**Idempotency** is the headline guarantee — re-running any stage leaves row counts identical and produces no duplicate PKs:
```bash
# extractor / dlt re-run → identical counts; PK dup check returns 0
docker compose exec lake-postgres psql -U lake_user -d lake_db -c "SELECT count(*)-count(DISTINCT id) FROM raw.order_items;"
```

---

## 15. Troubleshooting (gotchas we actually hit)

| Symptom | Cause → Fix |
|---|---|
| `relation "meta.watermarks" does not exist` | Init script didn't run (volume pre-existed, or `POSTGRES_DB` unset). Ensure `POSTGRES_DB` is set per service; reset with `down -v`. |
| `401 Unauthorized` | API key stale (containers started before `.env` filled) or **quoted** in `.env`. Write the key bare, `docker compose up -d` to recreate. |
| `404 Not Found` on an entity | Endpoint paths are snake_case (`payment_methods`, not `payment-methods`). |
| dbt builds into `staging_staging` etc. | Missing `generate_schema_name` macro. |
| `--select dimensions` matches nothing | Use the FQN prefix `marts.dimensions` (bare interior path components don't match). |
| `TypeError: LoadInfo is not JSON serializable` (DAG load task) | dlt returns a non-serializable object; set `do_xcom_push=False` on the load task. |
| dlt `PermissionError` on `/opt/airflow/.dlt` | Named volume is root-owned; Dockerfile must `mkdir -p /opt/airflow/.dlt && chown airflow:0`. |
| `dbt debug` "git not found" | Cosmetic — `dbt_utils` is a Hub package (tarball, not git). `git` is installed in the Dockerfile so debug is fully green. |
| ~56% of `fct_sales` had `customer_key='-1'` | SCD2 first slice's `valid_from = effective_from` (often later than historical orders). Fix: backdate the earliest slice's `valid_from`. |

---

## 16. Operations

- **Schedule:** `@daily`, `LocalExecutor`, every task `retries=2` with exponential backoff.
- **Failure isolation:** linear task chain + default `all_success` trigger rule → any failure halts downstream (no silent partial run).
- **Idempotent** end to end: same logical date twice = identical row counts, no duplicate PKs, same downstream facts.
- **Backfill:** `airflow dags backfill -s <start> -e <end> retailco_pipeline`.

---

## 17. Presentation guide (talking points)

- **The 3 grains, demonstrated:** transactional (`fct_sales`, `fct_payments`), periodic snapshot (`fct_inventory_daily`), accumulating snapshot (`fct_order_lifecycle`).
- **Show incremental working live:** first full extract takes minutes (360k `order_items`); the dlt load step then completes in **0.02s** on the next run because state filtered everything out.
- **Show resilience live:** the extractor log line where a real `500` triggered backoff and recovered on attempt 2.
- **Show Kimball discipline:** surrogate keys, Unknown members (`0` unknown FKs in facts), SCD2 history with soft-deletes retained, the point-in-time join attributing each sale to the price/segment valid at that moment.
- **The big insight to lead with:** discounting halves margin (28.9% → 13.8%) — concrete, actionable.
- **The data-quality story:** 2.03% anomalous payments isolated and excluded; future-dated timestamps surfaced but proven harmless downstream.
- **The one tricky bug worth telling:** the SCD2 first-slice backdating fix (56% → 0% unknown customers) — shows you understood *why* point-in-time joins need a beginning-of-time anchor.

---

## 18. Checkpoint → rubric map

| Checkpoint | Where | Status |
|---|---|---|
| CP1 Design (bus matrix, ERD, architecture) | `/design` | ✅ |
| CP2 Extract (pagination, incremental, rate-limit, retries, idempotency) | `extractor/` | ✅ |
| CP3 Load (dlt incremental, type coercion, idempotency) | `dlt_pipeline/` | ✅ |
| CP4 Model (Kimball, SCD2, surrogate keys, conformed dims, tests) | `dbt_project/` | ✅ (76 tests pass) |
| CP5 Operate (DAG order, retries, backfill, dependencies) | `airflow/dags/` | ✅ |

---
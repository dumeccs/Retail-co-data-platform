-- Warehouse database: four schemas for the four transformation layers
CREATE SCHEMA IF NOT EXISTS raw;        -- dlt loads here from the lake
CREATE SCHEMA IF NOT EXISTS staging;    -- dbt cleans and types-casts here
CREATE SCHEMA IF NOT EXISTS snapshots;  -- dbt SCD2 snapshots live here
CREATE SCHEMA IF NOT EXISTS marts;      -- final Kimball dims and facts live here

COMMENT ON SCHEMA raw       IS 'Raw data as loaded by dlt. Mirrors lake raw schema.';
COMMENT ON SCHEMA staging   IS 'Cleaned, typed, snake_cased views built by dbt.';
COMMENT ON SCHEMA snapshots IS 'SCD2 snapshot tables for dim_customer and dim_product.';
COMMENT ON SCHEMA marts     IS 'Kimball dimensional model: dims and facts.';

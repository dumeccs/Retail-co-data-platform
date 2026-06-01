{% snapshot snapshot_products %}
{{ config(target_schema='snapshots', 
          unique_key='id', 
          strategy='timestamp',
          updated_at='scd_valid_from', 
          invalidate_hard_deletes=false) 
          }}
with source as (
    select
        id, sku, name as product_name, category, sub_category, brand, supplier,
        cost_price::numeric(14,2)   as cost_price,
        selling_price::numeric(14,2) as selling_price,
        effective_from, coalesce(is_deleted, false) as is_deleted,
        created_at, updated_at,
        coalesce(effective_from, created_at) as scd_valid_from
    from {{ source('erp_raw', 'products') }}
)
select * from source
{% endsnapshot %}

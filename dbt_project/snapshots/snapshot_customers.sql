{% snapshot snapshot_customers %}
{{ config(target_schema='snapshots', 
          unique_key='id', 
          strategy='timestamp',
          updated_at='scd_valid_from', 
          invalidate_hard_deletes=false) }}
with source as (
    select
        id, first_name, last_name, email, phone, segment, tier,
        address, city, state, registered_at, effective_from,
        coalesce(is_deleted, false) as is_deleted,
        created_at, updated_at,
        coalesce(effective_from, created_at) as scd_valid_from
    from {{ source('erp_raw', 'customers') }}
)
select * from source
{% endsnapshot %}
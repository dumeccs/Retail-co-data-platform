with o as (select * from {{ ref('stg_orders') }})
select
    {{ dbt_utils.generate_surrogate_key(['o.order_id']) }} as order_lifecycle_key,
    cast(to_char(o.ordered_at,'YYYYMMDD') as int)                  as ordered_date_key,
    coalesce(cast(to_char(o.paid_at,'YYYYMMDD') as int),0)         as paid_date_key,
    coalesce(cast(to_char(o.shipped_at,'YYYYMMDD') as int),0)      as shipped_date_key,
    coalesce(cast(to_char(o.delivered_at,'YYYYMMDD') as int),0)    as delivered_date_key,
    coalesce(cast(to_char(o.cancelled_at,'YYYYMMDD') as int),0)    as cancelled_date_key,
    coalesce(dc.customer_key,'-1') as customer_key,
    coalesce(ds.store_key,'-1')    as store_key,
    coalesce(de.employee_key,'-1') as employee_key,
    o.order_id, o.status as current_status, o.discount_code,
    o.total_amount    as order_total_amount,
    o.discount_amount as order_discount_amount,
    (o.paid_at::date      - o.ordered_at::date) as days_pending_to_paid,
    (o.shipped_at::date   - o.paid_at::date)    as days_paid_to_shipped,
    (o.delivered_at::date - o.shipped_at::date) as days_shipped_to_delivered,
    (o.delivered_at::date - o.ordered_at::date) as days_order_to_delivered,
    (o.status = 'cancelled') as is_cancelled
from o
left join {{ ref('dim_customer') }} dc
  on dc.customer_id = o.customer_id
 and o.ordered_at >= dc.valid_from
 and o.ordered_at <  coalesce(dc.valid_to, timestamptz '9999-12-31')
left join {{ ref('dim_store') }}    ds on ds.store_id = o.store_id
left join {{ ref('dim_employee') }} de on de.employee_id = o.employee_id
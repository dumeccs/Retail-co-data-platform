with oi as (select * from {{ ref('stg_order_items') }}),
o  as (select * from {{ ref('stg_orders') }}),
lines as (
    select oi.order_item_id, oi.order_id, oi.product_id, oi.quantity,
           oi.unit_price, oi.discount_pct, oi.line_total,
           o.customer_id, o.store_id, o.employee_id, o.status as order_status,
           o.discount_code, o.ordered_at
    from oi join o on oi.order_id = o.order_id
)
select
    {{ dbt_utils.generate_surrogate_key(['l.order_item_id']) }} as sales_key,
    cast(to_char(l.ordered_at,'YYYYMMDD') as int) as date_key,
    coalesce(dc.customer_key,'-1') as customer_key,
    coalesce(dp.product_key,'-1')  as product_key,
    coalesce(ds.store_key,'-1')    as store_key,
    coalesce(de.employee_key,'-1') as employee_key,
    l.order_id, l.order_item_id, l.order_status, l.discount_code,
    l.quantity, l.unit_price,
    (l.quantity * l.unit_price)                  as gross_amount,
    l.discount_pct,
    (l.quantity * l.unit_price) - l.line_total   as discount_amount,
    l.line_total                                 as net_amount,
    dp.cost_price                                as unit_cost,
    (l.quantity * dp.cost_price)                 as total_cost,
    l.line_total - (l.quantity * dp.cost_price)  as gross_margin
from lines l
left join {{ ref('dim_customer') }} dc
  on dc.customer_id = l.customer_id
 and l.ordered_at >= dc.valid_from
 and l.ordered_at <  coalesce(dc.valid_to, timestamptz '9999-12-31')
left join {{ ref('dim_product') }} dp
  on dp.product_id = l.product_id
 and l.ordered_at >= dp.valid_from
 and l.ordered_at <  coalesce(dp.valid_to, timestamptz '9999-12-31')
left join {{ ref('dim_store') }}    ds on ds.store_id = l.store_id
left join {{ ref('dim_employee') }} de on de.employee_id = l.employee_id
select id as order_item_id, order_id, product_id, quantity::int as quantity,
       unit_price::numeric(14,2) as unit_price, discount_pct::numeric(5,2) as discount_pct,
       line_total::numeric(14,2) as line_total, created_at, updated_at
from {{ source('erp_raw','order_items') }}
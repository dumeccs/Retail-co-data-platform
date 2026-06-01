select id as order_id, customer_id, store_id, employee_id, status,
       discount_code, discount_amount::numeric(14,2) as discount_amount,
       total_amount::numeric(14,2) as total_amount,
       ordered_at::timestamptz as ordered_at, paid_at::timestamptz as paid_at,
       shipped_at::timestamptz as shipped_at, delivered_at::timestamptz as delivered_at,
       cancelled_at::timestamptz as cancelled_at, created_at, updated_at
from {{ source('erp_raw','orders') }}
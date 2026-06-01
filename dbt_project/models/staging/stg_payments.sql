
select id as payment_id, order_id, customer_id, payment_method_id,
       amount_paid::numeric(14,2) as amount_paid, currency,
       status as payment_status, payment_type, reference,
       paid_at::timestamptz as paid_at, created_at, updated_at
from {{ source('erp_raw','payments') }}
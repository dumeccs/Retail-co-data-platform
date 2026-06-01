select
    payment_id, order_id, customer_id, payment_method_id,
    amount_paid, currency, payment_status, payment_type, reference, paid_at,
    case when amount_paid = 0 then 'zero_amount' else 'unexplained_negative' end as flag_reason,
    current_timestamp as flagged_at
from {{ ref('stg_payments') }}
where amount_paid = 0 or (amount_paid < 0 and payment_type <> 'refund')
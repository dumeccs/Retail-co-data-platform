with p as (
    select * from {{ ref('stg_payments') }}
    where not (amount_paid = 0 or (amount_paid < 0 and payment_type <> 'refund'))
)
select
    {{ dbt_utils.generate_surrogate_key(['p.payment_id']) }} as payment_key,
    cast(to_char(coalesce(p.paid_at,p.created_at),'YYYYMMDD') as int) as date_key,
    coalesce(dc.customer_key,'-1')       as customer_key,
    coalesce(pm.payment_method_key,'-1') as payment_method_key,
    p.payment_id, p.order_id, p.reference, p.payment_type, p.payment_status, p.currency,
    p.amount_paid,
    (p.payment_type = 'refund') as is_refund
from p
left join {{ ref('dim_customer') }} dc
  on dc.customer_id = p.customer_id
 and coalesce(p.paid_at,p.created_at) >= dc.valid_from
 and coalesce(p.paid_at,p.created_at) <  coalesce(dc.valid_to, timestamptz '9999-12-31')
left join {{ ref('dim_payment_method') }} pm on pm.payment_method_id = p.payment_method_id
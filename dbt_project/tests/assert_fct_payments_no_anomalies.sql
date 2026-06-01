-- anomalies must have been routed to flagged_payments, never here
select * from {{ ref('fct_payments') }}
where amount_paid = 0 or (amount_paid < 0 and not is_refund)
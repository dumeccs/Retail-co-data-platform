select * from {{ ref('fct_order_lifecycle') }}
where coalesce(days_pending_to_paid,0) < 0
   or coalesce(days_paid_to_shipped,0) < 0
   or coalesce(days_shipped_to_delivered,0) < 0
   or coalesce(days_order_to_delivered,0) < 0
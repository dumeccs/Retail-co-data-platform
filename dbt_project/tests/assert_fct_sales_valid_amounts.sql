select * from {{ ref('fct_sales') }}
where quantity <= 0 or net_amount < 0
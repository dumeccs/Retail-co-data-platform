select
    {{ dbt_utils.generate_surrogate_key(['payment_method_id']) }} as payment_method_key,
    payment_method_id, method_name, provider, is_digital
from {{ ref('stg_payment_methods') }}
union all
select '-1','UNKNOWN',null,null, false
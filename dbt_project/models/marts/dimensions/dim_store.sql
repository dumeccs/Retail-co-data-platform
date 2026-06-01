select
    {{ dbt_utils.generate_surrogate_key(['store_id']) }} as store_key,
    store_id, store_name, city, state, address, phone, manager_name, opened_date
from {{ ref('stg_stores') }}
union all
select '-1','UNKNOWN',null,null,null,null,null,null,null::date
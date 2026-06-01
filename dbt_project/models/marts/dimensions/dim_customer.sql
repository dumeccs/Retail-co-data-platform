select
    {{ dbt_utils.generate_surrogate_key(['id','dbt_valid_from']) }} as customer_key,
    id as customer_id, first_name, last_name, email,
    replace(phone, chr(92), '') as phone,
    segment, tier, address, city, state, registered_at, is_deleted,
    case when dbt_valid_from = min(dbt_valid_from) over (partition by id)
         then timestamptz '1900-01-01'
         else dbt_valid_from end as valid_from,
    dbt_valid_to as valid_to,
    (dbt_valid_to is null and is_deleted = false) as is_current
from {{ ref('snapshot_customers') }}
union all
select '-1','UNKNOWN',null,null,null,null,null,null,null,null,null,
       null::timestamptz, false, timestamptz '1900-01-01', null::timestamptz, true
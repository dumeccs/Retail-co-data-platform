select
    {{ dbt_utils.generate_surrogate_key(['employee_id']) }} as employee_key,
    employee_id, store_id, first_name, last_name, email, role, hired_date, is_deleted
from {{ ref('stg_employees') }}
union all
select '-1','UNKNOWN',null,null,null,null,null,null::date, false
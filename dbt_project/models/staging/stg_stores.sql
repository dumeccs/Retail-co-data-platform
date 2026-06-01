select id as store_id, name as store_name, city, state, address,
       replace(phone, chr(92), '') as phone, manager_name,
       opened_date::date as opened_date, created_at, updated_at
from {{ source('erp_raw','stores') }}
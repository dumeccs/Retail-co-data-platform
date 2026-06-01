select id as customer_id, first_name, last_name, email,
       replace(phone, chr(92), '') as phone, segment, tier, address, city, state,
       registered_at, effective_from, coalesce(is_deleted,false) as is_deleted,
       created_at, updated_at
from {{ source('erp_raw','customers') }}
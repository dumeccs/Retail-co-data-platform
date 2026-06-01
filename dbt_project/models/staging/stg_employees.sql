select id as employee_id, store_id, first_name, last_name, email, role,
       hired_date::date as hired_date, coalesce(is_deleted,false) as is_deleted,
       created_at, updated_at
from {{ source('erp_raw','employees') }}
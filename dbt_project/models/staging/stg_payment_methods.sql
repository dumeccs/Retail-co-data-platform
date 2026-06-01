select id as payment_method_id, name as method_name, provider,
       coalesce(is_digital,false) as is_digital, created_at, updated_at
from {{ source('erp_raw','payment_methods') }}
select id as product_id, sku, name as product_name, category, sub_category,
       brand, supplier, cost_price::numeric(14,2) as cost_price,
       selling_price::numeric(14,2) as selling_price, effective_from,
       coalesce(is_deleted,false) as is_deleted, created_at, updated_at
from {{ source('erp_raw','products') }}
select id as movement_id, product_id, store_id, movement_type,
       quantity::int as quantity, reference_id, reference_type, notes,
       moved_at::timestamptz as moved_at, created_at, updated_at
from {{ source('erp_raw','inventory_movements') }}
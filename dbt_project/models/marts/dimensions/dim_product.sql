select
    {{ dbt_utils.generate_surrogate_key(['id','dbt_valid_from']) }} as product_key,
    id as product_id, sku, product_name, category, sub_category, brand, supplier,
    cost_price, selling_price, is_deleted,
    case when dbt_valid_from = min(dbt_valid_from) over (partition by id)
         then timestamptz '1900-01-01'
         else dbt_valid_from end as valid_from,
    dbt_valid_to as valid_to,
    (dbt_valid_to is null and is_deleted = false) as is_current
from {{ ref('snapshot_products') }}
union all
select '-1','UNKNOWN',null,null,null,null,null,null,
       null::numeric, null::numeric, false,
       timestamptz '1900-01-01', null::timestamptz, true
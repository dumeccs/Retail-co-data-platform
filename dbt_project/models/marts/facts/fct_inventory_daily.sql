with daily as (
    select product_id, store_id, cast(moved_at as date) as movement_date,
           sum(case when quantity > 0 then quantity else 0 end)  as qty_in,
           sum(case when quantity < 0 then -quantity else 0 end) as qty_out,
           sum(quantity)                                         as net_movement
    from {{ ref('stg_inventory_movements') }}
    group by product_id, store_id, cast(moved_at as date)
),
running as (
    select d.*,
           sum(net_movement) over (partition by product_id, store_id
               order by movement_date rows between unbounded preceding and current row
           ) as on_hand_quantity
    from daily d
)
select
    {{ dbt_utils.generate_surrogate_key(['r.product_id','r.store_id','r.movement_date']) }} as inventory_daily_key,
    cast(to_char(r.movement_date,'YYYYMMDD') as int) as date_key,
    coalesce(dp.product_key,'-1') as product_key,
    coalesce(ds.store_key,'-1')   as store_key,
    r.qty_in, r.qty_out, r.net_movement, r.on_hand_quantity
from running r
left join {{ ref('dim_product') }} dp
  on dp.product_id = r.product_id
 and r.movement_date >= dp.valid_from::date
 and r.movement_date <  coalesce(dp.valid_to::date, date '9999-12-31')
left join {{ ref('dim_store') }} ds on ds.store_id = r.store_id
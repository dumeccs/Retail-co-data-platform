select * from {{ ref('fct_inventory_daily') }}
where net_movement <> (qty_in - qty_out)
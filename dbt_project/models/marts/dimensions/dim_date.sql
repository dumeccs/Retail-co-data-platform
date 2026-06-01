with spine as (
    {{ dbt_utils.date_spine(datepart="day",
        start_date="cast('2023-01-01' as date)",
        end_date="cast('2028-01-01' as date)") }}
),
holidays as (
    select * from (values
        (1,1,'New Year''s Day'), (5,1,'Workers'' Day'), (6,12,'Democracy Day'),
        (10,1,'Independence Day'), (12,25,'Christmas Day'), (12,26,'Boxing Day')
    ) as h(mth, dy, holiday_name)
),
calendar as (
    select
        cast(to_char(cast(date_day as date),'YYYYMMDD') as int) as date_key,
        cast(date_day as date) as date_actual,
        extract(year    from date_day)::int as year,
        extract(quarter from date_day)::int as quarter,
        extract(month   from date_day)::int as month,
        trim(to_char(date_day,'Month'))     as month_name,
        extract(week    from date_day)::int as week_of_year,
        extract(day     from date_day)::int as day_of_month,
        extract(isodow  from date_day)::int as day_of_week,
        trim(to_char(date_day,'Day'))       as day_name,
        (extract(isodow from date_day) in (6,7)) as is_weekend,
        (h.holiday_name is not null)             as is_public_holiday,
        h.holiday_name
    from spine
    left join holidays h
      on extract(month from date_day) = h.mth
     and extract(day   from date_day) = h.dy
)
select * from calendar
union all
select 0, date '1900-01-01', 1900, 1, 1, 'Unknown', 1, 1, 1, 'Unknown',
       false, false, null
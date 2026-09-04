select
    currency_code,
    cast(month_start_date as date) as month_start_date,
    rate_to_usd
from {{ ref('fx_rate_month') }}

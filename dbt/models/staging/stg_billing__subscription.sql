select
    id           as billing_subscription_id,
    customer_id  as billing_customer_id,
    plan_code,
    quantity,
    unit_amount_cents,
    interval,
    status       as subscription_status,
    currency     as currency_code,
    cast(current_period_start as date) as current_period_start,
    cast(current_period_end as date)   as current_period_end,
    cast(canceled_at as date)          as canceled_at
from {{ ref('billing_subscription') }}

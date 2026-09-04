select
    id              as invoice_id,
    customer_id     as billing_customer_id,
    subscription_id as billing_subscription_id,
    total_cents / 100.0 as total_native,
    currency        as currency_code,
    status          as invoice_status,
    cast(period_start as date) as period_start,
    cast(period_end as date)   as period_end,
    cast(issued_at as date)    as issued_at,
    cast(due_at as date)       as due_at,
    cast(paid_at as date)      as paid_at
from {{ ref('billing_invoice') }}

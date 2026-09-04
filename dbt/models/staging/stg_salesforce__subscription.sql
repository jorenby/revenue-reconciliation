select
    id                as salesforce_subscription_id,
    account_id        as salesforce_account_id,
    plan_name,
    mrr               as mrr_native,
    currency_iso_code as currency_code,
    cast(start_date as date) as start_date,
    cast(end_date as date)   as end_date,
    status            as subscription_status,
    is_deleted
from {{ ref('salesforce_subscription') }}

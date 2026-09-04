select
    id                   as product_account_id,
    nullif(salesforce_account_id, '') as salesforce_account_id,
    nullif(billing_customer_id, '')   as billing_customer_id,
    plan_tier,
    cast(site_published_at as date) as site_published_at,
    status               as account_status,
    is_internal
from {{ ref('product_account') }}

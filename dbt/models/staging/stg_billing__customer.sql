select
    id           as billing_customer_id,
    external_ref as salesforce_account_id,
    email
from {{ ref('billing_customer') }}

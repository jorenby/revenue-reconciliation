select
    id                as salesforce_account_id,
    name              as account_name,
    parent_account_id,
    is_deleted,
    cast(created_date as date) as created_date
from {{ ref('salesforce_account') }}

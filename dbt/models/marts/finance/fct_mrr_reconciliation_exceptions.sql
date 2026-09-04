{{ config(materialized = 'view') }}

select *
from {{ ref('fct_mrr_by_account_month') }}
where reconciliation_case != 'matches'
  and is_in_scope

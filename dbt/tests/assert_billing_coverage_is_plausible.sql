/*
    The silent failure this model is most exposed to: the billing sync is late
    or a month lands partial, every account classifies salesforce_only, mrr_usd
    goes to zero across the book, and nothing else fails. mrr_usd cannot be null
    because of the coalesce, so a not_null test would never catch it.

    This is a canary, not an invariant. It asserts that most in-scope accounts
    with a Salesforce contract also have a billing record in the same month.
    A genuine wave of unbilled accounts would trip it too, which is the correct
    outcome: both causes need a human before the number goes anywhere.
*/

with monthly as (

    select
        month_start_date,
        count(*) as accounts_with_salesforce_contract,
        sum(case when reconciliation_case = 'salesforce_only' then 1 else 0 end)
            as accounts_missing_from_billing
    from {{ ref('fct_mrr_by_account_month') }}
    where is_in_scope
      and salesforce_mrr_usd is not null
    group by month_start_date

)

select *
from monthly
where accounts_with_salesforce_contract > 0
  and accounts_missing_from_billing::float / accounts_with_salesforce_contract > 0.25

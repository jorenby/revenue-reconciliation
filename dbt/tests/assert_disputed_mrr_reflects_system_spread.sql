/*
    Recomputes contested dollars from the intermediate models rather than from
    the fact's own columns, so it fails if the fact's classification and its
    arithmetic drift apart. A test that reads only the fact can be satisfied by
    the same mistake twice.
*/

with

fct as (
    select * from {{ ref('fct_mrr_by_account_month') }}
),

salesforce as (
    select * from {{ ref('int_salesforce__account_month') }}
),

billing as (
    select * from {{ ref('int_billing__account_month') }}
),

recomputed as (

    select
        fct.account_id,
        fct.month_start_date,
        fct.reconciliation_case,
        fct.disputed_mrr_usd,
        case
            when fct.reconciliation_case = 'matches'
                then 0
            when fct.reconciliation_case = 'policy_undecided'
                then coalesce(billing.mrr_usd, 0)
            else abs(coalesce(salesforce.mrr_usd, 0) - coalesce(billing.mrr_usd, 0))
        end as expected_disputed_mrr_usd
    from fct
    left join salesforce
        on fct.account_id = salesforce.account_id
        and fct.month_start_date = salesforce.month_start_date
    left join billing
        on fct.account_id = billing.account_id
        and fct.month_start_date = billing.month_start_date

)

select *
from recomputed
where abs(disputed_mrr_usd - expected_disputed_mrr_usd) > 0.001

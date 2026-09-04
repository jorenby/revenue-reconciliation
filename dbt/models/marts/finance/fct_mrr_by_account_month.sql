{{ config(materialized = 'table') }}

with

spine as (
    select * from {{ ref('int_account_spine') }}
),

salesforce as (
    select * from {{ ref('int_salesforce__account_month') }}
),

billing as (
    select * from {{ ref('int_billing__account_month') }}
),

product as (
    select * from {{ ref('int_product__account_month') }}
),

account_months as (

    select account_id, month_start_date from salesforce
    union
    select account_id, month_start_date from billing
    union
    select account_id, month_start_date from product

),

joined as (

    select
        account_id,
        month_start_date,

        spine.parent_account_id,
        spine.is_in_scope,
        spine.exclusion_reason,
        spine.exists_in_product,

        salesforce.mrr_usd             as salesforce_mrr_usd,
        salesforce.subscription_status as salesforce_status,
        salesforce.plan_name           as salesforce_plan_name,

        billing.mrr_usd             as billing_mrr_usd,
        billing.subscription_status as billing_status,
        billing.days_past_due       as billing_days_past_due,

        product.account_status  as product_status,
        product.plan_tier       as product_plan_tier

    from account_months
    inner join spine     using (account_id)
    left join salesforce using (account_id, month_start_date)
    left join billing    using (account_id, month_start_date)
    left join product    using (account_id, month_start_date)

),

canonical as (

    select
        *,
        case lower(salesforce_status)
            when 'active'  then 'active'
            when 'churned' then 'inactive'
            else 'unknown'
        end as salesforce_status_canonical,
        case lower(billing_status)
            when 'active'   then 'active'
            when 'trialing' then 'active'
            when 'past_due' then 'active'
            when 'canceled' then 'inactive'
            else 'unknown'
        end as billing_status_canonical
    from joined

),

classified as (

    select
        *,
        case
            when billing_days_past_due >= {{ var('past_due_review_days', 60) }}
                then 'policy_undecided'

            when salesforce_mrr_usd is null
                and billing_mrr_usd is null
                and exists_in_product
                then 'product_only'

            when salesforce_mrr_usd is null and billing_mrr_usd is not null
                then 'billing_only'

            when billing_mrr_usd is null and salesforce_mrr_usd is not null
                then 'salesforce_only'

            when salesforce_status_canonical = 'unknown'
                or billing_status_canonical = 'unknown'
                then 'status_conflict'

            when coalesce(salesforce_status_canonical, 'unknown')
                 != coalesce(billing_status_canonical, 'unknown')
                or product_status in ('suspended', 'canceled')
                then 'status_conflict'

            when abs(coalesce(salesforce_mrr_usd, 0) - coalesce(billing_mrr_usd, 0))
                 > {{ var('mrr_match_tolerance_usd', 1) }}
                then 'amount_mismatch'

            else 'matches'
        end as reconciliation_case

    from canonical

),

final as (

    select
        account_id || '-' || cast(month_start_date as varchar) as account_month_key,
        account_id,
        month_start_date,
        parent_account_id,

        salesforce_mrr_usd,
        salesforce_status,
        salesforce_plan_name,
        billing_mrr_usd,
        billing_status,
        billing_days_past_due,
        product_status,
        product_plan_tier,

        /*
            Billing supplies the number wherever billing has an opinion, because
            it records what was actually invoiced. Salesforce records what was
            sold, which is a different fact, and it only stays current if
            something keeps it current.

            Two branches genuinely diverge from that default.

            'salesforce_only' and 'product_only' resolve to zero, and this is a
            policy choice rather than an obvious call. Nothing was invoiced, so
            zero is the conservative reading. But a signed contract not yet billed
            is ARR under plenty of definitions, and if Finance counts it, this
            branch is where the gap between our number and theirs would live.
            Either way the Salesforce figure is not discarded; it surfaces in
            disputed_mrr_usd.

            'policy_undecided' is governed by count_past_due_as_revenue, which
            defaults to true. Dropping a long-past-due account to zero is itself
            a revenue policy decision and it belongs to Finance, not to this
            model, so the default preserves today's behavior and flags the row.
            When Finance rules, flip the variable in dbt_project.yml and the full
            history rebuilds against the new rule. That variable is the record of
            the decision, which is why it is not a hard-coded literal here.
        */
        case
            when reconciliation_case in ('salesforce_only', 'product_only')
                then 0
            when reconciliation_case = 'policy_undecided'
                and not {{ var('count_past_due_as_revenue', true) }}
                then 0
            else coalesce(billing_mrr_usd, 0)
        end as mrr_usd,

        case
            when reconciliation_case = 'matches'
                then 0
            when reconciliation_case = 'policy_undecided'
                then coalesce(billing_mrr_usd, 0)
            else abs(coalesce(salesforce_mrr_usd, 0) - coalesce(billing_mrr_usd, 0))
        end as disputed_mrr_usd,

        reconciliation_case,
        is_in_scope,
        exclusion_reason

    from classified

)

select * from final


with

subscription as (
    select * from {{ ref('stg_salesforce__subscription') }}
),

spine as (
    select * from {{ ref('int_account_spine') }}
),

months as (
    select * from {{ ref('int_month_spine') }}
),

fx as (
    select * from {{ ref('stg_fx__rate_month') }}
),

expanded as (

    select
        spine.account_id,
        months.month_start_date,
        subscription.plan_name,
        subscription.subscription_status,
        subscription.mrr_native,
        subscription.currency_code,
        subscription.is_deleted
    from subscription
    inner join spine
        using (salesforce_account_id)
    cross join months
    where months.month_start_date >= date_trunc('month', subscription.start_date)
      and (
            subscription.end_date is null
            or months.month_start_date <= date_trunc('month', subscription.end_date)
          )

),

converted as (

    select
        expanded.account_id,
        expanded.month_start_date,
        max(expanded.plan_name)           as plan_name,
        min_by(
            expanded.subscription_status,
            case expanded.subscription_status
                when 'Active'  then 1
                when 'Churned' then 2
                else 3
            end
        ) as subscription_status,
        sum(
            case when expanded.is_deleted then 0
                 else expanded.mrr_native * fx.rate_to_usd
            end
        ) as mrr_usd,
        max(case when expanded.is_deleted then 1 else 0 end) = 1
            as has_soft_deleted_subscription
    from expanded
    left join fx
        on expanded.currency_code = fx.currency_code
        and expanded.month_start_date = fx.month_start_date
    group by expanded.account_id, expanded.month_start_date

)

select * from converted

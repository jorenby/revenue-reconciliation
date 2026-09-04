
with

invoice_month as (
    select * from {{ ref('int_billing__invoice_month') }}
),

delinquency as (
    select * from {{ ref('int_billing__delinquency_by_account_month') }}
),

subscription as (
    select * from {{ ref('stg_billing__subscription') }}
),

spine as (
    select * from {{ ref('int_account_spine') }}
),

months as (
    select * from {{ ref('int_month_spine') }}
),

revenue as (

    select
        account_id,
        month_start_date,
        sum(amount_usd) as mrr_usd
    from invoice_month
    where invoice_status in ('paid', 'open')
    group by account_id, month_start_date

),

-- Most-live status wins. An account can carry a cancelled legacy subscription
-- beside a live one, and ranking cancellation highest would report it as churned.
status_by_account as (

    select
        spine.account_id,
        min_by(
            subscription.subscription_status,
            case subscription.subscription_status
                when 'active'   then 1
                when 'past_due' then 2
                when 'canceled' then 3
                else 4
            end
        ) as subscription_status
    from subscription
    inner join spine
        using (billing_customer_id)
    group by spine.account_id

),

-- Month grid from subscription presence, not invoices: a cancellation that
-- stops invoicing must still report as cancelled, not as absent from billing.
subscription_months as (

    select
        spine.account_id,
        months.month_start_date
    from subscription
    inner join spine
        using (billing_customer_id)
    cross join months
    where months.month_start_date >= date_trunc('month', subscription.current_period_start)
       or subscription.canceled_at is not null

),

account_months as (

    select account_id, month_start_date from revenue
    union
    select account_id, month_start_date from subscription_months

),

final as (

    select
        account_id,
        month_start_date,
        coalesce(revenue.mrr_usd, 0) as mrr_usd,
        status_by_account.subscription_status,
        coalesce(delinquency.days_past_due, 0) as days_past_due,
        true as status_is_inferred
    from account_months
    left join revenue           using (account_id, month_start_date)
    left join status_by_account using (account_id)
    left join delinquency       using (account_id, month_start_date)

)

select * from final

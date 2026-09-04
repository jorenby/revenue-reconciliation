/*
    An invoice spread evenly across the months its period covers.

    Its own model rather than a CTE because the spread is the piece of billing
    logic most likely to be wrong, and because anything else reporting revenue
    over service months wants this table unchanged. Worth testing on its own
    rather than only through whatever consumes it.

    period_end is treated as inclusive, and periods are assumed to align to
    calendar months. Several billing platforms set period_end to the start of the
    next period, and anniversary-date billing spans two calendar months, either
    of which changes months_covered. Confirm both against the real platform
    before trusting a single multi-month invoice.
*/

with

invoice as (
    select * from {{ ref('stg_billing__invoice') }}
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

/*
    Step 1: how many calendar months does this invoice cover?
    A single-month invoice covers 1. An annual invoice covers 12.
*/
invoice_span as (

    select
        invoice_id,
        billing_customer_id,
        invoice_status,
        currency_code,
        total_native,
        period_start,
        period_end,
        datediff(
            'month',
            date_trunc('month', period_start),
            date_trunc('month', period_end)
        ) + 1 as months_covered

    from invoice

),

-- Step 2: one row per invoice per covered month, still in the billed currency.
invoice_by_month as (

    select
        spine.account_id,
        months.month_start_date,
        invoice_span.invoice_id,
        invoice_span.invoice_status,
        invoice_span.currency_code,
        invoice_span.total_native,
        invoice_span.months_covered,
        invoice_span.total_native / invoice_span.months_covered as native_per_month

    from invoice_span
    inner join spine
        using (billing_customer_id)
    cross join months
    where months.month_start_date >= date_trunc('month', invoice_span.period_start)
      and months.month_start_date <= date_trunc('month', invoice_span.period_end)

),

-- Step 3: convert to USD at the rate for the month the amount lands in.
converted as (

    select
        invoice_by_month.account_id,
        invoice_by_month.month_start_date,
        invoice_by_month.invoice_id,
        invoice_by_month.invoice_status,
        invoice_by_month.currency_code,
        invoice_by_month.total_native,
        invoice_by_month.months_covered,
        invoice_by_month.native_per_month,
        fx.rate_to_usd,
        invoice_by_month.native_per_month * fx.rate_to_usd as amount_usd

    from invoice_by_month
    left join fx
        on invoice_by_month.currency_code = fx.currency_code
        and invoice_by_month.month_start_date = fx.month_start_date

)

select * from converted


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

overdue as (

    select
        spine.account_id,
        months.month_start_date,
        max(datediff('day', invoice.due_at, last_day(months.month_start_date)))
            as days_past_due
    from invoice
    inner join spine
        using (billing_customer_id)
    cross join months
    where invoice.paid_at is null
      and invoice.invoice_status = 'open'
      and invoice.due_at <= last_day(months.month_start_date)
    group by spine.account_id, months.month_start_date

)

select * from overdue

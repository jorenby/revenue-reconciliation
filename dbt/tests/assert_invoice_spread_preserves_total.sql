/*
    The spread divides an invoice across the months its period covers. If
    months_covered is wrong, or a covered month falls outside the modelled
    window, dollars are quietly created or destroyed and every downstream number
    inherits it.

    Compared in the billed currency, because conversion is a separate step and a
    rate that varies by month would make a correct spread look broken.

    Invoices whose period extends past the modelled month range are excluded:
    those are legitimately partial rather than wrong.
*/

with

invoice as (
    select * from {{ ref('stg_billing__invoice') }}
),

months as (
    select min(month_start_date) as first_month, max(month_start_date) as last_month
    from {{ ref('int_month_spine') }}
),

spread as (
    select
        invoice_id,
        sum(native_per_month) as spread_total_native
    from {{ ref('int_billing__invoice_month') }}
    group by invoice_id
)

select
    invoice.invoice_id,
    invoice.total_native,
    spread.spread_total_native
from invoice
inner join spread using (invoice_id)
cross join months
where date_trunc('month', invoice.period_start) >= months.first_month
  and date_trunc('month', invoice.period_end)   <= months.last_month
  and abs(invoice.total_native - spread.spread_total_native) > 0.01

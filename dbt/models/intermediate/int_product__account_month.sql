
with

product_account as (
    select * from {{ ref('stg_product__account') }}
),

spine as (
    select * from {{ ref('int_account_spine') }}
),

months as (
    select * from {{ ref('int_month_spine') }}
),

final as (

    select
        spine.account_id,
        months.month_start_date,
        product_account.account_status,
        product_account.plan_tier,
        true as status_is_inferred
    from product_account
    inner join spine
        using (product_account_id)
    cross join months
    -- Bounded at both ends. Without the upper bound a customer who churned two
    -- years ago produces a product_only exception every month, forever.
    where months.month_start_date >= date_trunc('month', product_account.site_published_at)
      and product_account.account_status not in ('canceled', 'deleted')

)

select * from final

/*
    The spine claims each system's native key maps to exactly one resolved
    account. Nothing in the grouping enforces that: it dedups on the resolved id
    only, so a broken crosswalk can put one billing customer under two accounts
    (revenue counted twice) or collapse two under one (revenue dropped).

    Both failures are invisible downstream, because the per-system intermediates
    join on those native keys and would simply follow whatever the spine says.
*/

with spine as (

    select * from {{ ref('int_account_spine') }}

),

offenders as (

    select 'salesforce_account_id' as key_name, salesforce_account_id as key_value, count(*) as account_count
    from spine where salesforce_account_id is not null
    group by 1, 2 having count(*) > 1

    union all

    select 'billing_customer_id', billing_customer_id, count(*)
    from spine where billing_customer_id is not null
    group by 1, 2 having count(*) > 1

    union all

    select 'product_account_id', product_account_id, count(*)
    from spine where product_account_id is not null
    group by 1, 2 having count(*) > 1

)

select * from offenders

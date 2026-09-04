
with

salesforce_account as (
    select * from {{ ref('stg_salesforce__account') }}
),

/*
    Scope is deliberately account-level only.

    Deletion can be recorded on either the account or the subscription, and it is
    tempting to treat both the same way. That is wrong here: Salesforce keeps
    deleted records in the recycle bin for about fifteen days and Fivetran syncs
    them with is_deleted set, so a live customer with one stale deleted
    subscription beside a live one would silently leave the board number. A
    deleted subscription instead contributes zero dollars in
    int_salesforce__account_month while the account stays in scope.
*/

billing_customer as (
    select * from {{ ref('stg_billing__customer') }}
),

product_account as (
    select * from {{ ref('stg_product__account') }}
),

candidates as (

    select
        salesforce_account_id,
        cast(null as varchar) as billing_customer_id,
        cast(null as varchar) as product_account_id,
        parent_account_id,
        is_deleted            as salesforce_is_deleted,
        cast(null as boolean) as is_internal
    from salesforce_account

    union all

    select
        salesforce_account_id,
        billing_customer_id,
        cast(null as varchar) as product_account_id,
        cast(null as varchar) as parent_account_id,
        cast(null as boolean) as salesforce_is_deleted,
        cast(null as boolean) as is_internal
    from billing_customer

    union all

    select
        salesforce_account_id,
        billing_customer_id,
        product_account_id,
        cast(null as varchar) as parent_account_id,
        cast(null as boolean) as salesforce_is_deleted,
        is_internal
    from product_account

),

keyed as (

    select
        coalesce(
            salesforce_account_id,
            'BILLING:' || billing_customer_id,
            'PRODUCT:' || product_account_id
        ) as account_id,
        *
    from candidates

),

resolved as (

    select
        account_id,
        max(salesforce_account_id) as salesforce_account_id,
        max(billing_customer_id)   as billing_customer_id,
        max(product_account_id)    as product_account_id,
        max(parent_account_id)     as parent_account_id,
        max(case when salesforce_is_deleted then 1 else 0 end) = 1 as salesforce_is_deleted,
        max(case when is_internal then 1 else 0 end) = 1           as is_internal
    from keyed
    group by account_id

),

final as (

    select
        account_id,
        salesforce_account_id,
        billing_customer_id,
        product_account_id,
        parent_account_id,

        salesforce_account_id is not null as exists_in_salesforce,
        billing_customer_id   is not null as exists_in_billing,
        product_account_id    is not null as exists_in_product,

        not (is_internal or salesforce_is_deleted) as is_in_scope,

        case
            when is_internal            then 'internal_or_test_account'
            when salesforce_is_deleted  then 'salesforce_soft_deleted'
        end as exclusion_reason

    from resolved

)

select * from final

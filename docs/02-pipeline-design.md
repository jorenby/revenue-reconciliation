# Pipeline design

```mermaid
%%{init: {'theme':'base','themeVariables':{'fontSize':'20px','fontFamily':'system-ui, -apple-system, sans-serif','lineColor':'#e2e8f0','textColor':'#f1f5f9','clusterBkg':'#0b1220','clusterBorder':'#e2e8f0','titleColor':'#f1f5f9'}}}%%
flowchart LR

  subgraph SRC["SOURCES"]
    sf_sub[(salesforce.subscription__c)]
    sf_acct[(salesforce.account)]
    prod_acct[(product.account)]
    bill_inv[(billing.invoice)]
    bill_sub[(billing.subscription)]
    bill_cust[(billing.customer)]
    fx_src[(finance FX rates)]
  end

  subgraph STG["STAGING"]
    stg_sf_sub[stg_salesforce__subscription]
    stg_sf_acct[stg_salesforce__account]
    stg_prod_acct[stg_product__account]
    stg_bill_inv[stg_billing__invoice]
    stg_bill_sub[stg_billing__subscription]
    stg_bill_cust[stg_billing__customer]
    stg_fx[stg_fx__rate_month]
  end

  subgraph SNAP["SNAPSHOTS — SCD2"]
    snap_sf[snap_salesforce__subscription]
    snap_prod[snap_product__account]
  end

  subgraph INT["INTERMEDIATE"]
    spine[int_account_spine]
    int_sf[int_salesforce__account_month]
    int_prod[int_product__account_month]
    int_invmo[int_billing__invoice_month]
    int_delinq[int_billing__delinquency_by_account_month]
    int_bill[int_billing__account_month]
  end

  subgraph MART["MARTS / FINANCE"]
    fct[fct_mrr_by_account_month]
    exc[fct_mrr_reconciliation_exceptions]
  end

  sf_acct --> stg_sf_acct
  sf_sub --> stg_sf_sub
  bill_cust --> stg_bill_cust
  bill_sub --> stg_bill_sub
  bill_inv --> stg_bill_inv
  prod_acct --> stg_prod_acct
  fx_src --> stg_fx

  stg_sf_acct --> spine
  stg_bill_cust --> spine
  stg_prod_acct --> spine

  stg_prod_acct --> snap_prod
  stg_sf_sub --> snap_sf

  snap_sf --> int_sf
  stg_fx --> int_sf
  snap_prod --> int_prod

  stg_bill_inv --> int_invmo
  stg_fx --> int_invmo
  stg_bill_inv --> int_delinq
  int_invmo --> int_bill
  int_delinq --> int_bill
  stg_bill_sub --> int_bill

  spine --> fct
  int_sf --> fct
  int_bill --> fct
  int_prod --> fct

  fct --> exc

  fct -.-> dash([Exec dashboard])
  fct -.-> sem([Semantic layer / assistant])
  exc -.-> alerts([RevOps alerts])

  linkStyle default stroke:#e2e8f0,stroke-width:2.5px;

  classDef src fill:#334155,stroke:#94a3b8,stroke-width:2px,color:#ffffff;
  classDef stg fill:#1e293b,stroke:#64748b,stroke-width:2px,color:#ffffff;
  classDef snap fill:#4a3210,stroke:#fbbf24,stroke-width:2px,color:#ffffff;
  classDef int fill:#1e3a5f,stroke:#60a5fa,stroke-width:2px,color:#ffffff;
  classDef mart fill:#0f5132,stroke:#4ade80,stroke-width:3px,color:#ffffff;
  classDef out fill:#3f2d56,stroke:#c4b5fd,stroke-width:2px,color:#ffffff;

  class sf_acct,sf_sub,bill_cust,bill_sub,bill_inv,prod_acct,fx_src src;
  class stg_sf_acct,stg_sf_sub,stg_bill_cust,stg_bill_sub,stg_bill_inv,stg_prod_acct,stg_fx stg;
  class snap_prod,snap_sf snap;
  class spine,int_sf,int_bill,int_prod,int_invmo,int_delinq int;
  class fct,exc mart;
  class dash,sem,alerts out;

  style SRC fill:#0b1220,stroke:#e2e8f0,stroke-width:2px,color:#ffffff;
  style STG fill:#0b1220,stroke:#e2e8f0,stroke-width:2px,color:#ffffff;
  style SNAP fill:#0b1220,stroke:#e2e8f0,stroke-width:2px,color:#ffffff;
  style INT fill:#0b1220,stroke:#e2e8f0,stroke-width:2px,color:#ffffff;
  style MART fill:#0b1220,stroke:#e2e8f0,stroke-width:2px,color:#ffffff;
```

Snapshots are proposed, not built. The project reads staging directly and flags the affected columns `status_is_inferred`, because a snapshot has no history until it has been running a while and there was none to seed.

## The decisions

**Reconciliation sits at account-month.** Salesforce `subscription__c.id` and `billing.subscription.id` share no key, and one account can carry several rows on either side. The account is the finest level at which all three systems agree on identity, so it is the only level where they can be compared.

Open check: count product accounts per billing customer. If product accounts fan out under one billing customer, "account" has to mean the Salesforce account and per-account MRR needs an allocation rule.

**The spine feeds the intermediates, not just the fact.** Each per-system model translates its native key to a resolved `account_id` before anything is unioned, because a union is only meaningful over one key space. The alternative is to leave the intermediates in native keys and join through the spine's per-system columns in the fact; I chose upstream so anything else reading those models inherits the resolved key.

**Billing splits into three models.** `int_billing__invoice_month` spreads each invoice across the months its period covers, which is what turns annual prepay into a monthly amount instead of a 12x spike. It's separate because the spread is the billing logic most likely to be wrong, and because a spread-by-service-month table is the shape anything doing revenue-over-time would want. `int_billing__delinquency_by_account_month` derives days past due, and is separate because collections consumes it with no interest in MRR.

**Currency converts at the same rate on both sides.** That's the part that matters for reconciliation: if the two sides use different rates, every non-USD account shows a gap the pipeline invented. I've used the reporting month's rate because it's the one rule both sides can apply, but which rate Finance actually wants is their call, and the swap is a one-join change.

## The fact table

| | |
|---|---|
| `account_id`, `month_start_date` | grain |
| `salesforce_mrr_usd`, `salesforce_status`, `billing_mrr_usd`, `billing_status`, `product_status`, `product_plan_tier` | each system's belief, side by side |
| `mrr_usd` | the reconciled number, by a precedence rule keyed to the case |
| `reconciliation_case` | `matches`, `amount_mismatch`, `billing_only`, `salesforce_only`, `product_only`, `status_conflict`, `policy_undecided` |
| `disputed_mrr_usd` | dollars the systems don't agree on |
| `is_in_scope` | internal, test, and soft-deleted accounts stay as rows and are excluded by the metric, not by an upstream `WHERE` |

`is_in_scope` and `reconciliation_case` are separate on purpose. Scope is whether an account counts at all; the case is how the systems disagree. LP QA Account 4 is both, and one column would hide one of them.

## History, and what limits reconciling past months

Account-month grain assumes each system's belief can be stated for any month. The three sources differ in whether that's possible today.

**Billing** is derivable. Invoices accumulate and carry `period_start`, `period_end`, and `issued_at`.

**Salesforce** is partially derivable. Contract terms give a timeline; field history is what shows when `mrr__c` and `status__c` actually changed. The project reads terms, not field history.

**Product** is not derivable. A nightly snapshot that overwrites leaves current state only. Northshore reads `suspended` today, and nothing says when that started.

So reconciliation for closed months is limited by product history, and any backfill has to say so rather than imply equal confidence across all three. Forward fix: `dbt snapshot` with the `check` strategy on product `status` and `plan_tier`. A nightly full-overwrite source with no reliable updated-at is exactly what that strategy exists for.

## Deliberately excluded

**`billing.credit_note`**, because a credit adjusts what's owed on an invoice rather than the contracted amount. That's the simple reading and it may not survive contact with the real data — credits are also how some shops express a mid-term downgrade, which would change the run rate. Worth confirming before it stays excluded.

**`salesforce.opportunity`**, because bookings aren't recurring revenue. Whether Finance counts signed-but-unprovisioned contracts is a definitional question rather than a modelling one.

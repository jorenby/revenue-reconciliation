# Assumptions and known limits

Places where the model behaves differently if something I assumed turns out to be false. The design decisions themselves are in the pipeline and tests docs; this is only what would change the answer.

## The one everything else rests on

**`billing.customer.external_ref` holds the Salesforce account id.** The schema doesn't say so, and the spine's resolution order depends on it. First thing I'd verify with whoever built the billing integration.

If it turns out to be a product id, an email, or free text, the failure is a split rather than an orphan — `product.account` carries both foreign keys, so a customer resolves partly through product and partly through billing and lands in two rows. `assert_native_keys_resolve_to_one_account` catches that immediately, which is the one good property of this failure. Product's crosswalk is the fallback join.

## Identity

**One native key must map to one resolved account, and only half of that is tested.** The test catches a split, where one billing customer appears under two accounts and revenue counts twice. It cannot catch a collapse: the spine keeps `max(billing_customer_id)` per account, so if a Salesforce account legitimately has two billing customers, the second id appears in no spine row and its invoices vanish at the join. The test for it is one CTE: distinct `billing_customer_id` in staging, minus those present in the spine.

**Scope only knows what product knows.** `is_internal` comes from `product.account`, so a test account that exists only in Salesforce stays in scope. That's why "internal account with non-zero MRR" matters as a separate detector.

**Parent and child accounts are carried but not rolled up.** `parent_account_id` is on the fact so a rollup can avoid double counting, and nothing does that rollup yet. An enterprise sold at the parent and billed at the child appears as two accounts.

**The duplicate is modelled at the account level.** The brief describes it as a second `Subscription__c` row. At the subscription level it would surface as an inflated Salesforce amount rather than an excluded row — same effect on the number, different label.

## Currency

**A missing rate fails differently on each side.** On billing it raises, because `amount_usd` carries a not-null test. On Salesforce it produces a null amount, which reclassifies the row as `billing_only` and passes quietly. The Salesforce side needs a `relationships` test from its currency code to the rate table. Both also require a USD row in the rate table, and in a single-currency Salesforce org the currency field doesn't exist at all, so the staging model would fail rather than silently null out.

**The rate table stands in for a policy I'd need from Finance.** Which rate, which date, and whether a closed month's rate is ever restated are all their calls. A monthly table is one option; a rate fixed for the year is another. The pipeline is indifferent — it's a one-join change — so the policy question doesn't block anything.

## Money

**Invoice periods are assumed to align to calendar months, with `period_end` inclusive.** Anniversary-date billing that spans two calendar months splits fifty-fifty, and some platforms set `period_end` to the start of the next period. Either changes the divisor. The spread test only exercises invoices that fall entirely inside the modelled window, so it never checks the multi-month case the spread exists for.

**`due_at` isn't in the given schema — I added it.** Days past due keys on it, so if billing has no due date the whole `policy_undecided` branch needs payment terms from somewhere else.

**Days past due is computed against today's payment state, not as at month end.** Paying an old invoice next month rewrites how a closed month classifies. Fixing it needs payment events, or a snapshot of open invoices taken at each close.

**Closed months aren't frozen.** A full rebuild means late-arriving corrections silently change a month already reported. The fix is to snapshot each month at close and report the drift as a line item rather than letting it happen quietly. Not built here.

## History

**Product history is inferred, not recorded.** The nightly snapshot overwrites, so any past month's `product_status` is the current value carried backwards, flagged `status_is_inferred`. Billing statuses have the same problem. SCD2 snapshots fix this going forward and can't fix it retroactively.

**Salesforce history is contract terms, not field history.** A subscription's current MRR and status apply to every month inside its term, so a value someone edited in March reads as though it had always been that value.

## Classification

**The status map was built from a nine-account sample.** Only `active` and `churned` are mapped on the Salesforce side, and real picklists carry more. Anything unmapped now lands as a conflict, which is the safe direction and will be noisy on a first real load. Expanding the map is a conversation with RevOps.

**Two judgment calls sit inside that map, and both belong to Finance.** `past_due` maps to active, on the reading that a late payer is still a customer. `trialing` also maps to active, which only affects status comparison; a trial invoices at zero, so it contributes nothing to the money either way.

**One case per row.** An account can have a status conflict and an amount gap at once, and only the higher-priority label survives. The money stays visible in `disputed_mrr_usd`. Separate amount and status classifications would be cleaner and it's the next thing I'd change.

**`policy_undecided` is age-dependent.** The same open issue carries a different label at 30 days than at 61, so exception de-duplication has to key on the account rather than the case.

## Environment

**The month spine is a hardcoded three-month list.** `dbt_utils.date_spine` in real use.

**Verified on duckdb, targeted at Snowflake.** Functions were chosen to compile on both, and only duckdb has executed them. Anything genuinely Snowflake-specific — semi-structured landing tables, warehouse sizing — is untested here. Incremental strategy is a separate matter and not a gap: at volume the fact becomes incremental on `unique_key: account_month_key` with a merge and a lookback window wide enough for late-arriving invoices.

# Making it AI-ready

**Where I stand:** I've done the modeling that sits underneath a semantic layer, not the layer itself. This is my first pass at Snowflake's semantic model YAML. I checked it against the published spec rather than writing it from memory, but I haven't run it, so treat the content decisions as mine and the syntax as unverified.

## Which approach

**If anything already exists, extend it.** A second semantic layer is a second definition of MRR, and then somebody reconciles the reconciliation. That outweighs any preference between the two options.

**If nothing exists yet, Cortex.** It's native to the warehouse the data already lives in, and the assistant is the consumer. The dbt Semantic Layer is the real alternative and the argument for it is good: definitions sit in version control beside the models and travel if the warehouse changes. It's a hosted dbt Cloud service the assistant would have to be wired into, which is a cost this use case doesn't obviously need.

## What's exposed

| | |
|---|---|
| Metrics | `total_mrr`, `total_disputed_mrr`, `account_count` |
| Dimensions | month, plan tier (product-sourced), `reconciliation_case` |
| Filter | `in_scope`, applied to revenue questions by default |

**The per-system columns stay out.** If `salesforce_mrr_usd` is exposed, someone asks what Salesforce says revenue is, gets a total, and now there's a fourth number in circulation that nobody sanctioned.

**`reconciliation_case` is a dimension on purpose.** It makes "why is $6,680 disputed" answerable in the same breath as the number, instead of leaving a figure nobody can interrogate.

## The definition

The descriptions and custom instructions are what the assistant follows when deciding what a question is asking for.

```yaml
name: revenue
description: >
  Reconciled recurring revenue by account and month. The only sanctioned source
  for revenue questions. Per-system views are deliberately not modelled here.

tables:
  - name: mrr_by_account_month
    description: One row per account per month, after reconciliation.
    base_table:
      database: analytics
      schema: finance
      table: fct_mrr_by_account_month
    primary_key:
      columns: [account_month_key]

    time_dimensions:
      - name: month
        expr: month_start_date
        data_type: DATE
        synonyms: [period, monthly, month]

    dimensions:
      - name: plan_tier_product
        expr: product_plan_tier
        data_type: VARCHAR
        synonyms: [plan, tier, plan tier]
        description: >
          Plan tier as provisioned in the product database. Salesforce and billing
          each carry their own plan and can disagree with this one. The source is in
          the name because the choice is not obvious and the disagreements are real.

      - name: reconciliation_case
        expr: reconciliation_case
        data_type: VARCHAR
        is_enum: true
        sample_values:
          [matches, amount_mismatch, billing_only, salesforce_only,
           product_only, status_conflict, policy_undecided]
        description: >
          How the source systems disagree about this account-month. Group by this
          to explain contested dollars rather than only reporting them.

      - name: in_scope
        expr: is_in_scope
        data_type: BOOLEAN
        labels: [filter]
        description: >
          Excludes internal, test, and soft-deleted accounts. Applied to every
          revenue question unless the user asks explicitly for excluded accounts.

    facts:
      - name: mrr_usd
        expr: mrr_usd
        data_type: NUMBER
        description: >
          Reconciled monthly recurring revenue for one account-month, in USD.
          NOT any single system's view, and not invoiced or collected cash.
          Annual prepay is spread across its term rather than landing whole in
          its invoice month.

      - name: disputed_mrr_usd
        expr: disputed_mrr_usd
        data_type: NUMBER
        description: >
          Dollars in this row the source systems do not agree on, or that await a
          Finance ruling.

    metrics:
      - name: total_mrr
        expr: SUM(mrr_usd)
        synonyms: [mrr, revenue, recurring revenue, monthly revenue]
        description: Reconciled recurring revenue for the selected period and filters.

      - name: total_disputed_mrr
        expr: SUM(disputed_mrr_usd)
        synonyms: [contested revenue, unreconciled revenue]
        description: >
          The portion of total_mrr that is contested. Report alongside total_mrr
          whenever it is material.

      - name: account_count
        expr: COUNT(DISTINCT account_id)
        description: >
          Accounts with a row in the period, after the in-scope filter. This is not
          a customer count: parent and child accounts are separate rows and are not
          rolled up.

module_custom_instructions:
  sql_generation: |
    Always apply the in_scope filter to revenue questions unless the user
    explicitly asks about internal, test, or excluded accounts.
    Whenever total_mrr is returned, also return total_disputed_mrr.
  question_categorization: |
    Questions about NRR, net revenue retention, expansion, or contraction are
    unanswerable from this view. It holds monthly levels, not movements
    between periods, and no movement metric is defined in it. Ask which
    definition the user wants rather than inferring one.

verified_queries:
  - name: monthly_revenue_with_contested
    question: What was revenue last month, and how much of it is contested?
    use_as_onboarding_question: true
    sql: |
      SELECT month, SUM(mrr_usd), SUM(disputed_mrr_usd)
      FROM revenue
      WHERE month = DATE_TRUNC('month', DATEADD(month, -1, CURRENT_DATE()))
      GROUP BY month
```

The descriptions do more work than the structure. `total_mrr` says what it is *not*, because the failure mode is an assistant treating it as interchangeable with a per-system total. `account_count` denies being a customer count.

The custom instructions are the weakest of the guardrails and worth being honest about: they steer the model, they don't constrain it. If scope has to be guaranteed rather than encouraged, the enforcement belongs lower down — a base view already filtered, or a row access policy — and the instruction becomes a convenience rather than the control.

## Three questions, and what goes wrong

### "What was NRR for Scale-tier accounts in Q2?"

The model holds monthly levels; NRR needs movements between two points and a cohort rule for the denominator. Neither is defined here.

An assistant handed levels and asked for NRR won't refuse. It composes something from month-over-month sums, returns a number in the high nineties, and is confidently wrong about the metric the board watches most closely. Nobody catches it, because the answer lands where everyone expects.

Fix: define it, or have the assistant ask. Permanently refusing just moves the question into a spreadsheet, so it gets defined, and Finance rules on what counts as expansion versus reactivation.

### "Which accounts churned last month?"

Three systems can each say an account churned and they don't agree. Harborview is churned in Salesforce and actively invoicing. Northshore is suspended in product and active in both others. Marin cancelled in billing and is live everywhere else.

Churn gets defined the same way MRR did: **billing owns it, because cancellation is the money event.** Product suspension is a service state, and an account can be suspended for non-payment with the contract still live. A Salesforce status is sales' belief and it drifts.

That resolves the sample: Marin churned, Harborview not despite Salesforce, Northshore not. Accounts whose systems disagree already carry `status_conflict`, so the list returns with its contested count attached.

Where it still fails: an account cancelled in billing and never suspended in product is churned by this definition and still being served. The list is right; someone still has to act on the second fact.

### "Show me revenue by plan tier."

Plan lives in three places and they disagree: Sunbelt is Scale in Salesforce and All In in product. Ask for revenue by tier and the assistant picks one of them, so $4,050 lands in whichever bucket it chose, and the answer says nothing about having chosen.

This one is worse than churn, because a churn answer looks like a judgment call and a revenue-by-tier chart looks like a fact. It goes in a deck.

Fix: one plan dimension, from one system, **named for its source** — `plan_tier_product`. My read is product, since entitlements determine what the customer can actually do, but it's Finance's and RevOps' call.

## Failing loudly

Every revenue answer can carry its contested dollars, because `disputed_mrr_usd` sits on the same rows as `mrr_usd`. The number and the doubt travel together instead of the doubt living in someone's head.

What I don't know is how loudly to say it. Announcing a contested figure on every answer would get tuned out fast, and never mentioning it is how we got here. My instinct is to compute it always, return it on request always, and volunteer it above some threshold — but where that threshold sits is a Finance call, not mine. I'd rather ask than guess, and the useful thing is that the plumbing supports whichever answer they give.

One limit worth stating: the semantic view can define the measure, but deciding when a number is worth interrupting someone about has to happen in whatever renders the answer.

## What this can't prevent

Cortex will usually generate valid SQL against a governed model. What it will also do is answer a slightly different question than the one asked — a different sense of "customer," a different time basis for "Q2," a filter the asker didn't know applied. The ambiguity is in the question, so no semantic layer removes it.

What the design does is make the choice visible in the answer: dimensions named for their source, scope stated, contested dollars attached, and metrics that don't exist genuinely absent rather than approximated.

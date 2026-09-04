# ARR reconciliation — technical assessment

Finance closed the month at $104.2M. The dashboard says $99.6M. Product's count implies a third number.

Working through the sample accounts turns up three kinds of problem, and they need three different responses.

Some of it is broken data: a duplicate, a test account, Salesforce records that never caught up when billing changed. Some of it is a comparison problem, where both systems are right and the model is putting an annual invoice next to a monthly one. And at least one account is waiting on a decision rather than a fix. Northshore is 61 days past due and suspended in the product, and I couldn't find a rule saying whether it still counts. Cleanup doesn't resolve that one.

One thing in the sample doesn't add up yet, and it's the first thing I'd chase. The dashboard reads **$4.6M below** Finance, but most of the defects I found push the dashboard **high**: the duplicate, the test account, the cancelled account still on the books. Harborview is the only one pointing the other way. So either these accounts sample patterns that behave differently across the full book, or a large share of the gap is something Finance counts that the dashboard never sees. I can't tell which from nine accounts.

The design goal that follows: every account-month row carries what each system believed, the reconciled figure, and how many of those dollars are contested. The dashboard, the board deck, the RevOps alerts, and the assistant all read that row, so none of them can report a number without also reporting how much of it is disputed.

## What's here

| | |
|---|---|
| [`docs/01-sample-accounts.md`](docs/01-sample-accounts.md) | Each account: the data, what's happening, which system is truth for that case, the verdict, and where I can't tell, the question and who I'd ask |
| [`docs/02-pipeline-design.md`](docs/02-pipeline-design.md) | The DAG, why reconciliation sits at account-month, and the limits on reconstructing past months |
| [`docs/03-model-and-tests.md`](docs/03-model-and-tests.md) | What the tests protect against, and what I deliberately chose not to test |
| [`docs/04-semantic-layer.md`](docs/04-semantic-layer.md) | Making it safe for an assistant to query: what's exposed, three questions that go wrong, and how it fails loudly |
| [`docs/05-cfo-note.md`](docs/05-cfo-note.md) | The reply I'd actually send |
| [`docs/known-limits.md`](docs/known-limits.md) | The assumptions that would change the answer if they turned out to be false |
| [`dbt/`](dbt/) | The dbt project. It runs. |

## The dbt project

Seed data reproduces every sample account plus a product-only case. `dbt build` is green across 16 models, 7 seeds, and 23 tests.

```bash
pip install dbt-core dbt-duckdb
cd dbt
dbt build --profiles-dir . --project-dir .
```

Targeted at Snowflake and executed on duckdb, so the logic is verifiable without warehouse access. March output is in [`dbt/model-output-march.txt`](dbt/model-output-march.txt):

```
account            | sf_mrr | billing_mrr | mrr_usd | disputed | recon_case       | in_scope
-------------------+--------+-------------+---------+----------+------------------+---------
Aspen Collective   | 1450.0 | 1450.0      | 1450.0  | 0.0      | matches          | True
Marin Group        | 2100.0 | 0.0         | 0.0     | 2100.0   | status_conflict  | True
Harborview RE      | None   | 980.0       | 980.0   | 980.0    | billing_only     | True
Sunbelt Partners   | 3200.0 | 4050.0      | 4050.0  | 850.0    | amount_mismatch  | True
Sunbelt Partners   | 0.0    | None        | 0.0     | 0.0      | salesforce_only  | False
Cedar & Co         | 1100.0 | 1100.0      | 1100.0  | 0.0      | matches          | True
Vieux Carre Realty | 1404.0 | 1404.0      | 1404.0  | 0.0      | matches          | True
LP QA Account 4    | 500.0  | 0.0         | 0.0     | 500.0    | amount_mismatch  | False
Northshore Team    | 2750.0 | 2750.0      | 2750.0  | 2750.0   | policy_undecided | True
```

Cedar's annual prepay spreads to $1,100 a month instead of spiking. Vieux Carré converts identically on both sides and stops looking broken. The duplicate and the test account stay as visible rows with a stated exclusion reason rather than disappearing into a `WHERE` clause. Northshore is flagged as awaiting a decision rather than silently counted or silently dropped.

*(I built the seed data so most of the sample is broken, to make each case visible. The contested share reflects that.)*

## Judgment calls

**The reconciliation and the number are one model.** A separate "reconciliation number" would just be a fourth figure to reconcile, so the canonical MRR and its dispute state are columns on the same row.

**Account-month is where the systems can meet.** Salesforce subscription ids and billing subscription ids share no key. The account is the finest level at which all three agree on identity.

**Scope and disagreement are separate columns.** An account can be out of scope *and* internally inconsistent — LP QA Account 4 is both. Collapsing them would hide one.

**Billing amounts come from invoices, not from subscriptions.** A subscription row carries its current period, so building months from it gives you the present. Invoices accumulate and carry the period they cover, so prior months can be reconstructed and annual prepay can be spread across its term.

**An unmapped status counts as a conflict.** Two statuses the map doesn't recognize would otherwise both become "unknown," compare equal, and report an account as reconciled when neither side was understood.

**The rules Finance owns are variables, not literals.** `past_due_review_days` and `count_past_due_as_revenue` live in `dbt_project.yml` because they're revenue policy. The defaults preserve today's behavior; when Finance rules, the variable changes and history rebuilds.

## On tooling

I used AI throughout, as an implementation partner and as a reviewer. The review is the part that earned its keep: a fresh pass with no history of the work, run before I trusted anything. It caught a precedence rule that had collapsed to a single expression, sitting under a comment describing three branches. I'd read that comment several times without seeing it.

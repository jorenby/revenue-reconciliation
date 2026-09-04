# Tests: what they protect, and what I left untested

The project runs. Seed data reproduces every sample account plus a product-only case, and `dbt build` is green across 16 models, 7 seeds, and 23 tests.

## The two that matter

**`disputed_mrr_usd` reflects the actual spread.** The one I'd keep if I could keep one. That column is how a total reports its own confidence; if it silently goes to zero, every dashboard reads full confidence in an unreconciled number and nothing else fails. It recomputes the expected value from the intermediate models rather than from the fact's own columns, so the arithmetic has to agree with an upstream source rather than with itself.

Honest limit: it still reads the fact's own `reconciliation_case` to pick which formula applies, so a row misclassified as `matches` expects zero and gets zero. Checking the classification independently would mean reimplementing the CASE in the test, which is its own trap. The right tool is a dbt unit test with fixture rows, which exercises the logic without restating it.

**Billing coverage canary.** The failure this model is most exposed to: the billing sync lands late or partial, every account classifies `salesforce_only`, `mrr_usd` goes to zero across the book, and nothing else fails. It asserts that most in-scope accounts with a Salesforce contract also have a billing record that month.

It's a canary rather than an invariant, so a genuine wave of unbilled accounts trips it too. Both causes need a human before the number goes anywhere. The first line of defence should be `dbt source freshness` on the billing tables with the build gated behind it; this catches what gets past that.

It earned its place during the build. The first billing model derived months from the subscription's current period, which only describes the present, so January and February came out with no billing rows at all. This test is what found it.

## The structural ones

Uniqueness on `account_month_key`, the relationship to the spine, not-null on both money columns, and accepted values on `reconciliation_case` are all in the yml. **None of them can fail on today's data.** The relationship can't fail because the join is inner; the not-nulls can't because both columns are computed through a `coalesce`; accepted values guards a column computed in the same model. They constrain future edits to this model rather than catching bad input, which is worth having and isn't what the names suggest.

`assert_native_keys_resolve_to_one_account` is the exception — it can fail, and it's the guard on the assumption the whole spine rests on.

## What I chose not to test

**That Salesforce MRR equals billing MRR.** This is the disagreement the model exists to measure. A test asserting they match would fail on every real run, get muted within a week, and a muted test is worse than no test because it reads as coverage. The disagreement belongs in a column and an alert.

**That every account appears in all three systems.** Absence is a finding. Accounts get created in one system before another, and deals close before provisioning. Testing for full presence turns ordinary business sequencing into a pipeline failure.

**That the reconciled total matches Finance's closed number.** Tempting and wrong. I haven't seen how that figure is built, so testing against it would encode rules I can't read as truth. Convergence is the goal; it isn't an invariant to assert.

**Whether the precedence rule is right.** It encodes a Finance decision. Tests can confirm it was applied consistently. Whether it's the correct rule isn't a property of the data.

## The principle

Test the invariants the logic depends on — grain, identity, the fields the calculation reads. Don't test the conditions in the data you're reporting on; those belong in alerts.

A test written from the same assumptions as the code agrees with the code, so what catches that class of failure is a check with an independent source. Hence the disputed-dollars test reading the intermediates, and the canary comparing against something else entirely. The same reasoning is why every version of this went to a fresh reader before I trusted it.

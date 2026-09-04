# The sample accounts

Read as of **March 31**, the month Finance just closed.

They sort into a few kinds of problem, and the kind drives the response:

| Kind | Accounts | Response |
|---|---|---|
| A system is wrong | Marin, Harborview, Sunbelt, Sunbelt dup | Fix the record. Alert. |
| The comparison is wrong | Cedar, Vieux Carré | Fix the model. Both systems are correct. |
| Out of scope | LP QA Account 4 | Never should have reached the metric. |
| Waiting on a decision | Northshore | No system holds the answer. |
| Ties out | Aspen | Control case. |

Rows two and four are the ones that matter for the headline gap. Neither is a bug, and cleanup doesn't touch either.

---

## Aspen Collective

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | Active | active | active |
| MRR | $1,450 | $1,450 | Scale |

Everything agrees. **Verdict:** nothing.

---

## Marin Group

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | **Active** | **canceled Mar 14** | **active** |
| MRR | $2,100 | $0 | Scale |

Billing cancelled mid-month, Salesforce never caught up, and product still shows the account active. Worth knowing whether product access is meant to run to the end of the paid period or whether nothing revokes it.

**Truth:** billing. **Verdict:** alert, to RevOps.
**Check:** `canceled_at`, invoice history, Salesforce field history on `status__c`.
**Ask:** the account owner, whether the cancellation was intentional. Product engineering, what is supposed to revoke access when billing cancels.

---

## Harborview RE

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | **Churned Feb 28** | **active** | **active** |
| MRR | **$0** | **$980** | Brand |

Billing and product agree the customer is live and paying. Salesforce is the odd one out, and because the dashboard reads Salesforce, this account **understates** revenue rather than inflating it.

**Truth:** billing and product. **Verdict:** alert.
**Check:** Salesforce field history on the Feb 28 edit; billing invoice history back through February. Continuous invoicing points to a bad Salesforce edit; a gap followed by a new subscription points to a churn and re-sign.
**Ask:** the account owner, churn or downgrade-and-re-sign.

---

## Sunbelt Partners

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | Active | active | active |
| MRR | **$3,200** | **$4,050** | **All In** |
| Plan | **Scale** | | |

Billing is invoicing $850 more than Salesforce has on record, and product already shows the higher tier. Most likely a plan change that never reached Salesforce; possibly a prorated invoice being compared against a steady-state figure.

**Truth:** billing, though the cause is unresolved. **Verdict:** alert.
**Check:** the prior month's invoice, `plan_name__c` against product `plan_tier` (a mismatch confirms the upgrade in-data), `parent_account_id` for a parent/child arrangement, credit notes.
**Ask:** RevOps if Salesforce is simply stale. Finance if the question is how a mid-cycle plan change should land in ARR.

---

## Sunbelt Partners (duplicate)

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | **Active** | **—** | **—** |
| MRR | **$3,200** | — | — |

A second Salesforce subscription with no counterpart in either other system. Salesforce is counting this account twice.

**Truth:** billing and product, neither of which has ever seen this record.
**Verdict:** branch on the check. Soft-deleted means the pipeline isn't filtering deletes, which is a silent fix. A live record means a merge, and a ticket.
**Check:** `salesforce.subscription__c.is_deleted`.

---

## Cedar & Co

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | Active | active | active |
| MRR | **$1,100** | **$13,200** (last invoice) | Brand |

$1,100 × 12 = $13,200 exactly, which points at annual prepay invoiced once for the year and sitting in a column next to eleven monthly figures. If that's right, both systems are correct.

**Truth:** billing, once normalized. **Verdict:** nothing to alert on; fix the model.
**Check:** `billing.subscription.interval`.

---

## Vieux Carré Realty

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | Active | active | active |
| MRR | **€1,300** | **€1,300** | Scale |

Both sides internally correct, both in euros. Any USD comparison is meaningless until a conversion policy is applied, and it has to be the same policy on both sides.

**Truth:** billing, once converted. **Verdict:** nothing to alert on; fix the model.
**Check:** how many accounts are non-USD and how much MRR they carry. If it's widespread, this is a material share of the gap rather than one odd account.
**Ask:** Finance, which rate and which date, as a stated policy.

---

## LP QA Account 4

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | Active | active | active |
| MRR | **$500** | **$0** | All In, **`is_internal`** |

An internal test account carrying $500 of Salesforce MRR. Whether it reaches the dashboard depends on whether anything upstream filters internal accounts, which is worth confirming.

**Truth:** product, via the internal flag.
**Verdict:** branch on the check. Flag set means exclude systematically, which is a scope decision rather than an alert. Flag not set means alert, because the exclusion mechanism itself is broken.
**Check:** `product.account.is_internal`.
**Ask:** RevOps to strip the MRR from the Salesforce record. The recurring detector worth building is "internal account with non-zero MRR," not this one account.

---

## Northshore Team

| | Salesforce | Billing | Product |
|---|---|---|---|
| Status | **Active** | **past_due, 61 days** | **suspended** |
| MRR | $2,750 | $2,750 | Scale |

Billing knows they haven't paid. Product knows access is off. Whether a delinquent contract still counts as ARR is not a fact any of the three systems holds.

**Truth:** none of them. This needs a ruling from Finance.
**Verdict:** alert, plus a definition decision. The alert alone doesn't resolve it.
**Check:** invoice history. Whether new invoices are still being issued, and what the retry state is on the unpaid ones, are separate questions and both matter.
**Ask:** Finance, whether past-due beyond some threshold still counts, and what the threshold is. Product, what suspension is supposed to trigger.

---

## Standing questions

**How does Salesforce actually get updated?** Marin has been cancelled for seventeen days and Northshore past due for 61, and Salesforce reflects neither. If field history tracking is switched on for `mrr__c` and `status__c`, that answers it empirically, since the history record carries who made the change. Whether those fields are tracked is the first thing to check.

**Alerts need to stay useful once the backlog clears.** Everything marked "alert" assumes the pattern still appears after the defects are fixed and the definitions settled. A detector that fires on annual prepay, currency, and test accounts recreates the noise that made Finance stop trusting the dashboard.

**The direction of the gap doesn't yet reconcile.** The dashboard reads $4.6M *below* Finance, but most of the defects here push the dashboard *high* — the duplicate, the test account, Marin. Harborview is the only one pointing the other way. So either these accounts sample patterns that behave differently at scale, or a large share of the gap comes from things Finance counts that the dashboard never sees.

**Whose spreadsheet is it.** The analyst on parental leave has reconciled this by hand for two quarters. Whatever rules it applies, asking for the file is faster than deriving them again. The ask is for the artifact and for whoever else worked on it.

**At least one account may be receiving service nobody is billing for.** Marin cancelled in billing and is still active in product. A cancellation normally leaves service running to the end of the paid period, so this is worth checking before calling it leakage. That is revenue leakage rather than a reporting defect, and it needs an owner outside this project.

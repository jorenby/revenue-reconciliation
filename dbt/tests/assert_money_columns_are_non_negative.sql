-- Cheap guard against a sign flip in currency conversion or annual spreading.
select account_month_key, mrr_usd, disputed_mrr_usd
from {{ ref('fct_mrr_by_account_month') }}
where mrr_usd < 0 or disputed_mrr_usd < 0

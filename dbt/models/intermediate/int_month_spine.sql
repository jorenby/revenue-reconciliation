select cast(month_start_date as date) as month_start_date
from (values
    ('2026-01-01'),
    ('2026-02-01'),
    ('2026-03-01')
) as t(month_start_date)

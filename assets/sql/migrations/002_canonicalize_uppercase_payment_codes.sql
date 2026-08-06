UPDATE tx_recipients
SET payment_code = lower(payment_code)
WHERE payment_code = upper(payment_code)
  AND (payment_code LIKE 'SP1%'
    OR payment_code LIKE 'TSP1%'
    OR payment_code LIKE 'SPRT1%'
    OR payment_code LIKE 'BC1%'
    OR payment_code LIKE 'TB1%'
    OR payment_code LIKE 'BCRT1%')

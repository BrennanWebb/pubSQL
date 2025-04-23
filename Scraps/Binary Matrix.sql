Drop table if exists #t2
SELECT n ID,
CASE WHEN n&1 >0 THEN 1 ELSE 0 END AS a,
CASE WHEN n&2 >0 THEN 1 ELSE 0 END AS b,
CASE WHEN n&4 >0 THEN 1 ELSE 0 END AS c,
CASE WHEN n&8 >0 THEN 1 ELSE 0 END AS d
Into #t2
FROM
(	SELECT number n
	FROM master..spt_values
	WHERE TYPE ='p'
	AND number <Power(2,4) --Change powers as needed.  Use 2 for binary testing (ergo True False).
) Nums

Select * From #T2;
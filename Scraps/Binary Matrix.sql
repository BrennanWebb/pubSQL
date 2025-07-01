Drop table if exists #t2
SELECT n ID,
IIF(n&1 >0, 1, 0) AS a,
IIF(n&2 >0, 1, 0) AS b,
IIF(n&4 >0, 1, 0) AS c,
IIF(n&8 >0, 1, 0) AS d

--,CASE WHEN n&16 >0 THEN 1 ELSE 0 END AS e --add more columns as needed, however be sure to up the second number in the Power() function below.
Into #t2
FROM
(	SELECT number n
	FROM master..spt_values --just get some values
	WHERE TYPE ='p'
	AND number <Power(2,4) --Power(Use 2 for binary testing (ergo True False), second value in the Power() function must match the number of columns) 
) Nums

Select * From #T2;
Use tempdb
go

--demo setup
drop table if exists #table1;
go
CREATE TABLE #Table1
    (SalesID int, Order1Name varchar(10), Order1Date date, Order1Amt int
	,Order2Name varchar(10), Order2Date date, Order2Amt int
	,Order3Name varchar(10), Order3Date date, Order3Amt int
	,Order4Name varchar(10), Order4Date date, Order4Amt int)
;

INSERT INTO #Table1
    (SalesID, Order1Name, Order1Date, Order1Amt, Order2Name, Order2Date, Order2Amt,Order3Name, Order3Date, Order3Amt,Order4Name, Order4Date, Order4Amt)
VALUES
    (1001, 'first', '2018-01-01', 111.00, 'second', '2018-02-01', 222.00,'third', '2018-03-01', 322.00,'fourth', '2018-04-01', 422.00),
	(1002, 'first', '2019-01-01', 112.00, 'second', '2019-02-01', 223.00,'third', '2019-03-01', 324.00,'fourth', '2019-04-01', 425.00),
	(1003, 'first', '2020-01-01', 113.00, 'second', '2020-02-01', 224.00,'third', '2020-03-01', 325.00,'fourth', '2020-04-01', 426.00)
;

Select * From #Table1

SELECT 
    *,
    ROW_NUMBER() over(partition by SalesID order by OrderDate) as OrderNum

FROM 
(
  SELECT SalesID, OrderName, OrderDate, OrderAmt,OrderNames,
    idon = replace(replace(OrderNames,'Order',''),'Name',''),
    idod = replace(replace(OrderDates,'Order',''),'Date',''),
    idoa = replace(replace(OrderAmts,'Order',''),'Amt','')
  FROM
	  (
		SELECT SalesID,[Order1Name],[Order2Name],[Order3Name], [Order4Name]
					  ,[Order1Date],[Order2Date],[Order3Date], [Order4Date]
					  ,[Order1Amt],[Order2Amt],[Order3Amt], [Order4Amt]
		FROM #Table1
	  ) AS cp
  UNPIVOT 
  (
    OrderName FOR OrderNames IN ( [Order1Name],[Order2Name],[Order3Name], [Order4Name])
  ) AS OrderName
  UNPIVOT 
  (
    OrderDate FOR OrderDates IN ([Order1Date],[Order2Date],[Order3Date], [Order4Date])
  ) AS OrderDate
  UNPIVOT
  (
    OrderAmt FOR OrderAmts IN ([Order1Amt],[Order2Amt],[Order3Amt], [Order4Amt])
  ) AS OrderAmt
) AS x
WHERE idod = idon and idoa = idon;
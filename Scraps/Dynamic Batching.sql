--Setup for the demo
Set NOCOUNT on
-- Create the table
Drop table if exists #FastTable;
CREATE TABLE #FastTable (
    [ID] INT IDENTITY(1,1) PRIMARY KEY,
    [Name] VARCHAR(50),
    [Date] DATE
);

-- Disable indexes and constraints for faster bulk insert
ALTER TABLE #FastTable NOCHECK CONSTRAINT ALL;

--Set variables for insert limits
DECLARE @TargetRowCount INT = 3000000;
DECLARE @CurrentRowCount INT = 0;

-- Insert rows in batches until the target row count is reached
WHILE @CurrentRowCount < @TargetRowCount
BEGIN
	INSERT INTO #FastTable (Name, [Date])
	SELECT 
		'Name' + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VARCHAR(10)),
		DATEADD(DAY, ABS(CHECKSUM(NEWID()) % 1000)*-1, GETDATE()) -- Random date
	FROM 
		master.dbo.spt_values a
	
	SET @CurrentRowCount = @@ROWCOUNT + @CurrentRowCount;
	--Declare @Message Nvarchar(50) = @CurrentRowCount
	--RAISERROR(@Message,1, 1) with NoWait; --Keep this off unless needed
END;

-- Enable indexes and constraints after bulk insert
ALTER TABLE #FastTable CHECK CONSTRAINT ALL;
-- Re-create non-clustered indexes if dropped earlier.

-- Optional: Check the row count
SELECT COUNT(*) AS TotalRows FROM #FastTable;
--SELECT TOP 1000 * FROM #FastTable ;

--Add a blank column for the demo below
Alter table #FastTable Add DateMinusJunk date
---------------------------------------------------------------
GO

--Batching Demo
--Set variables for insert limits
DECLARE @TargetRowCount INT = (Select max([ID]) From #FastTable);
DECLARE @CurrentRowCount INT = 0;
Declare @BatchTargetRowCount int;

--Create a holding table for stats
Drop table if exists #statsOut
Create table #statsOut (id int identity(1,1), CurrentRowCount int, BatchTargetRowCount int);

-- Insert rows in batches until the target row count is reached
WHILE @CurrentRowCount < @TargetRowCount
	BEGIN
		--https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-sys-memory-transact-sql?view=sql-server-ver16 
		Set @BatchTargetRowCount =(SELECT @CurrentRowCount+IIF(system_low_memory_signal_state = 1,10000, 100000)FROM sys.dm_os_sys_memory)
		
		--LogBatchMetadata
		Insert into #statsOut (CurrentRowCount, BatchTargetRowCount) Values (@CurrentRowCount,@BatchTargetRowCount);

		Update #FastTable
		Set DateMinusJunk = DateAdd(DAY, Left(2,[id])*-1,[Date])
		Where ID between @CurrentRowCount and @BatchTargetRowCount;

		SET @CurrentRowCount = @BatchTargetRowCount+1;
	End;

---Check outputs
Select *, BatchTargetRowCount-CurrentRowCount [BatchSize]
From #statsOut



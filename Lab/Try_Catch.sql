Create Database TryCatch

Use TryCatch

Set NoCount ON

------------------------------------------------------------
-------------------Begin Try Catch Demo---------------------
------------------------------------------------------------
--Basic Error Handling
BEGIN TRY
    -- This will cause a divide-by-zero error.
    SELECT 1 / 0 AS Result;
END TRY
BEGIN CATCH
    -- This block will execute because of the error.
    SELECT
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE() AS ErrorState,
        ERROR_LINE() AS ErrorLine,
        ERROR_PROCEDURE() AS ErrorProcedure;
END CATCH;
------------------------------------------------------------

--Nested TRY CATCH
BEGIN TRY
    PRINT 'Outer TRY block started.';
    BEGIN TRY
        PRINT '-->Inner TRY block started.';
        SELECT 1 / 0 AS Result; -- This will cause an error
        PRINT '-->Inner TRY block finished.'; -- This will not be reached
    END TRY
    BEGIN CATCH
        PRINT '-->Inner CATCH block executed.';
        SELECT ERROR_MESSAGE() AS InnerErrorMessage;
    END CATCH;
    PRINT 'Outer TRY block finished.';
END TRY
BEGIN CATCH
    PRINT 'Outer CATCH block executed.';
    SELECT ERROR_MESSAGE() AS OuterErrorMessage;
END CATCH;

------------------------------------------------------------
--Transaction Rollback

/*
XACT_STATE() is a scalar function that returns the transaction state of the current user session. 
It tells you not just if a transaction exists, but also whether that transaction is still usable 
or has entered a state where it can only be rolled back. See addendum for demo.
*/

CREATE TABLE dbo.TestTransaction (
    ID INT PRIMARY KEY
);

INSERT INTO dbo.TestTransaction (ID) VALUES (1);

BEGIN TRY
    BEGIN TRANSACTION;
    -- This will succeed
    INSERT INTO dbo.TestTransaction (ID) VALUES (2);
    -- This will fail due to a primary key violation
    INSERT INTO dbo.TestTransaction (ID) VALUES (1);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    -- Check if the transaction is uncommittable
    PRINT '@@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
    PRINT 'XACT_STATE() is: ' + CAST(XACT_STATE() AS VARCHAR);
    IF @@TRANCOUNT >0
    BEGIN
        PRINT 'Error Encountered: Rolling back transaction.';
        ROLLBACK TRANSACTION;
        PRINT '@@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
        PRINT 'XACT_STATE() is: ' + CAST(XACT_STATE() AS VARCHAR);
    END;

    -- You could also log the error here
    SELECT
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage;
    
END CATCH;

-- Verify that the second insert was rolled back
SELECT * FROM dbo.TestTransaction;

-- Clean up
DROP TABLE dbo.TestTransaction;

------------------------------------------------------------
--Re-throwing an Error
BEGIN TRY
    PRINT 'Outer TRY block.';
    BEGIN TRY
        PRINT '-->Inner TRY block.';
        SELECT 1 / 0 AS Result; -- Error
    END TRY
    BEGIN CATCH
        PRINT '-->Inner CATCH block. Logging error and re-throwing.';
        THROW; -- Re-throws the original error
    END CATCH;
END TRY
BEGIN CATCH
    PRINT 'Outer CATCH block caught the re-thrown error.';
    SELECT
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage;
END CATCH;


------------------------------------------------------------

--silent fail
-- First, let's ensure the table exists to guarantee an error on the second CREATE attempt.
IF OBJECT_ID('dbo.OptionalLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.OptionalLog (LogID INT PRIMARY KEY, LogMessage NVARCHAR(100));
    PRINT 'dbo.OptionalLog table created for the first time.';
END
GO

PRINT '--- Starting batch that might have a silent failure ---';
PRINT 'Attempting to create the dbo.OptionalLog table again...';

BEGIN TRY
    -- This statement will fail because the table already exists.
    CREATE TABLE dbo.OptionalLog (LogID INT PRIMARY KEY, LogMessage NVARCHAR(100));
    PRINT 'This message will NOT be displayed.';
END TRY
BEGIN CATCH
    -- The CATCH block is entered, but we choose to do nothing.
    -- In a real-world scenario, you might have a comment here explaining why it's ignored.
    -- For example: -- "Error ignored: Table may already exist, which is acceptable."
    PRINT 'An error occurred but was silently handled.';
END CATCH

PRINT 'Script execution continued successfully after the handled error.';
GO

-- Clean up
DROP TABLE dbo.OptionalLog;
GO

------------------------------------------------------------
---Syntax Errors Are Not Caught by Try Catch (important for Dynamic SQL) / compile-time errors
PRINT '--- Starting batch with a syntax error ---';

BEGIN TRY
    PRINT 'This message will be displayed because it is before the error.';
    -- The following line contains a syntax error ('SELEC' instead of 'SELECT').
    SELECT * FROM sys.objects;
END TRY
BEGIN CATCH
    -- This CATCH block will NOT be executed.
    PRINT 'CATCH block reached. This should not happen!';
    SELECT ERROR_MESSAGE() AS ErrorMessage;
END CATCH

PRINT 'This message will never be reached.';
GO

------------------------------------------------------------
--Cannot Catch High Severity
PRINT '--- Starting batch with a high-severity error ---';
PRINT 'The CATCH block will not be reached.';

BEGIN TRY
    PRINT 'TRY block entered. About to raise a fatal error.';
    -- RAISERROR with severity 20 or higher terminates the connection.
    -- The WITH LOG clause is required for severities >= 20.
    RAISERROR('This is a connection-terminating error.', 20, 1) WITH LOG;
    PRINT 'This line will never be reached.';
END TRY
BEGIN CATCH
    -- This block is completely bypassed.
    PRINT 'CATCH block has been entered. This should not happen!';
    SELECT ERROR_MESSAGE() AS ErrorMessage;
END CATCH

-- This statement will not be executed because the connection is severed.
PRINT 'Batch execution is continuing... or is it?';
GO

------------------------------------------------------------
--"Doomed" Transaction --> Lacks IF (XACT_STATE()) <> 0 ROLLBACK
CREATE TABLE dbo.TestDoomedTran (ID INT PRIMARY KEY);
INSERT INTO dbo.TestDoomedTran (ID) VALUES (101);
GO

BEGIN TRY
    PRINT 'Starting transaction...';
    BEGIN TRANSACTION;
    -- This will cause a Primary Key violation, dooming the transaction.
    INSERT INTO dbo.TestDoomedTran (ID) VALUES (101);
    -- This COMMIT will never be reached.
    COMMIT TRANSACTION;
    PRINT 'Transaction committed successfully inside TRY.';
END TRY
BEGIN CATCH
    PRINT 'CATCH block entered due to PK violation.';
    PRINT 'Transaction state (XACT_STATE()): ' + CAST(XACT_STATE() AS VARCHAR);

    -- This is the MISTAKE: We are trying to commit a doomed transaction.
    PRINT 'Now attempting to COMMIT inside the CATCH block...';
    COMMIT TRANSACTION;
END CATCH
GO

-- Clean up
DROP TABLE dbo.TestDoomedTran;
GO

------------------------------------------------------------
--Catching Deferred Name Resolution Errors / Run-time errors
-- This CREATE PROCEDURE will succeed due to deferred name resolution.
CREATE OR ALTER PROCEDURE dbo.GetDataFromFakeTable
AS
BEGIN
    PRINT 'Procedure dbo.GetDataFromFakeTable is now running.';
    -- This table does not exist, so this will cause a run-time error.
    SELECT * FROM dbo.ThisTableDoesNotExist;
    PRINT 'This line in the procedure will not be reached.';
END
GO

PRINT '--- Starting batch to execute the procedure ---';

BEGIN TRY
    -- We are executing the syntactically valid procedure.
    -- The error will occur at run-time, not compile-time.
    EXEC dbo.GetDataFromFakeTable;
END TRY
BEGIN CATCH
    PRINT 'CATCH block has been successfully entered.';
    SELECT
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage,
        ERROR_PROCEDURE() AS ErrorProcedure;
END CATCH

PRINT 'Execution continued after catching the procedure error.';
GO

-- Clean up
DROP PROCEDURE dbo.GetDataFromFakeTable;
GO

------------------------------------------------------------
--Rollback Pitfalls and Best Practices
CREATE TABLE dbo.WidgetOrders (
    OrderID INT PRIMARY KEY,
    WidgetID INT,
    Quantity INT
);
GO

PRINT '--- Starting The @@TRANCOUNT Trap Demo ---';

-- Check transaction count before we begin.
PRINT 'Before starting, @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);

BEGIN TRY
    -- Outer Transaction (e.g., the main stored procedure)
    BEGIN TRANSACTION;
    PRINT 'Outer transaction started. @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
    INSERT INTO dbo.WidgetOrders (OrderID, WidgetID, Quantity) VALUES (100, 1, 50);

    BEGIN TRY
        -- Inner Transaction (e.g., a helper procedure is called)
        BEGIN TRANSACTION;
        PRINT 'Inner transaction started. @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
        -- This insert will cause a Primary Key violation.
        INSERT INTO dbo.WidgetOrders (OrderID, WidgetID, Quantity) VALUES (100, 2, 99);
        COMMIT TRANSACTION; -- This is never reached
    END TRY
    BEGIN CATCH
        PRINT '--> Inner CATCH block entered.';
        PRINT '--> Before ROLLBACK, @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
        -- THIS IS THE TRAP! This rollback resets @@TRANCOUNT to 0, not 1.
        ROLLBACK TRANSACTION;
        PRINT '--> After ROLLBACK, @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
        PRINT '--> Inner CATCH block finished.';
    END CATCH

    -- We are now back in the outer TRY block. The developer might expect the outer transaction is still active.
    PRINT 'Resuming in outer TRY block.';
    PRINT 'Current @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);

    -- This will now FAIL because the ROLLBACK above killed the transaction.
    COMMIT TRANSACTION;
    PRINT 'Outer transaction committed successfully.'; -- This is never reached
END TRY
BEGIN CATCH
    PRINT '*** OUTER CATCH block entered! ***';
    SELECT
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage;
    -- Always good practice to check if a rollback is still needed
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
END CATCH

PRINT 'Final @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);

-- Check the table. The first insert should be gone too!
SELECT * FROM dbo.WidgetOrders;
GO

-- Clean up
DROP TABLE dbo.WidgetOrders;
GO


------------------------------------------------------------
--Using Savepoints for Partial Rollbacks
CREATE TABLE dbo.WidgetOrders (
    OrderID INT PRIMARY KEY,
    WidgetID INT,
    Quantity INT
);
GO

PRINT '--- Starting The Savepoint Demo ---';

-- Check transaction count before we begin.
PRINT 'Before starting, @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);

BEGIN TRANSACTION; -- Outer transaction is the REAL transaction
PRINT 'Outer transaction started. @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
INSERT INTO dbo.WidgetOrders (OrderID, WidgetID, Quantity) VALUES (200, 1, 50);

BEGIN TRY
    -- Create a savepoint before attempting the risky operation.
    SAVE TRANSACTION PartialInsert;
    PRINT 'Savepoint created. @@TRANCOUNT is still: ' + CAST(@@TRANCOUNT AS VARCHAR);
    -- This insert will cause a Primary Key violation.
    INSERT INTO dbo.WidgetOrders (OrderID, WidgetID, Quantity) VALUES (200, 2, 99);
    Commit Transaction
END TRY
BEGIN CATCH
    PRINT '--> CATCH block entered.';
    -- Check if we are in a transaction before rolling back to the savepoint
    IF (@@TRANCOUNT > 0)
    BEGIN
        PRINT '--> Before rolling back to savepoint, @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
        ROLLBACK TRANSACTION PartialInsert;
        PRINT '--> After rolling back to savepoint, @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);
    END
END CATCH

-- Execution continues, and the outer transaction should still be active.
PRINT 'Resuming after CATCH block.';
PRINT 'Current @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);

-- This COMMIT should now succeed.
IF (@@TRANCOUNT > 0)
BEGIN
    PRINT 'Committing the main transaction.';
    COMMIT TRANSACTION;
END

PRINT 'Final @@TRANCOUNT is: ' + CAST(@@TRANCOUNT AS VARCHAR);

-- Check the table. The first insert should exist!
SELECT * FROM dbo.WidgetOrders;
GO

-- Clean up
DROP TABLE dbo.WidgetOrders;
GO


------------------------------------------------------------
---------------------End Try Catch Demo---------------------
------------------------------------------------------------

------------------------------------------------------------
-----------------------Begin Adendum------------------------
------------------------------------------------------------

--Xact_State Demo
CREATE TABLE dbo.RuleTest (
    ID INT PRIMARY KEY,
    StatusName VARCHAR(20),
    Value INT
);
INSERT INTO dbo.RuleTest VALUES (1, 'Initial', 100);
GO

PRINT '--- Starting Doomed vs. Rollback-able Demo ---';

BEGIN TRANSACTION;
PRINT 'Transaction started. @@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR)
    + ', XACT_STATE = ' + CAST(XACT_STATE() AS VARCHAR);

-- ===================================================================
-- PART 1: A "Rollback-able" Business Rule Error
-- ===================================================================
PRINT CHAR(13) + '--- PART 1: Simulating a business rule error ---';
BEGIN TRY
    -- We decide that a value over 200 is not allowed.
    IF (SELECT Value FROM dbo.RuleTest WHERE ID = 1) < 200
    BEGIN
        -- This RAISERROR with severity 16 will be caught,
        -- but will NOT doom the transaction.
        RAISERROR('Business Rule Violation: Value must be over 200.', 16, 1);
    END
END TRY
BEGIN CATCH
    PRINT '--> CATCH block for Part 1 entered.';
    PRINT '--> ERROR: ' + ERROR_MESSAGE();
    PRINT '--> DIAGNOSIS: @@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR)
        + ', XACT_STATE = ' + CAST(XACT_STATE() AS VARCHAR);
    PRINT '--> CONCLUSION: Transaction is "Rollback-able", but still healthy.';
END CATCH

-- ===================================================================
-- PART 2: A Doomed Data Type Error
-- ===================================================================
PRINT CHAR(13) + '--- PART 2: Causing a data type conversion error ---';
BEGIN TRY
    -- This update will fail because 'INVALID' cannot be converted to an INT.
    -- This type of error DOOMS the transaction.
    UPDATE dbo.RuleTest
    SET Value = 'INVALID'
    WHERE ID = 1;
END TRY
BEGIN CATCH
    PRINT '--> CATCH block for Part 2 entered.';
    PRINT '--> ERROR: ' + ERROR_MESSAGE();
    PRINT '--> DIAGNOSIS: @@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR)
        + ', XACT_STATE = ' + CAST(XACT_STATE() AS VARCHAR);
    PRINT '--> CONCLUSION: Transaction is now DOOMED and must be rolled back.';
END CATCH

-- Final cleanup
IF (@@TRANCOUNT > 0)
BEGIN
    PRINT CHAR(13) + 'Performing final mandatory rollback.';
    ROLLBACK TRANSACTION;
END
GO

-- Cleanup
DROP TABLE dbo.RuleTest;
GO

------------------------------------------------------------

--Creating a savepoint: The primary use case for SAVE TRANSACTION is to handle errors in iterative or multi-step processes.
--@@TRANCOUNT is Unaffected: Creating a savepoint does not decrement or increment @@TRANCOUNT.
--Locks Are Not Released
--Commit is Still Required
--Duplicate Savepoint names allowed and are reused.
--Identity() Values are Lost
SAVE TRANSACTION savepoint_name;
-- Or using a variable
Declare @savepoint_variable varchar(20) = 'T1'
SAVE TRANSACTION @savepoint_variable;

--Rolling back to a savepoint
ROLLBACK TRANSACTION savepoint_name;
-- Or using a variable
ROLLBACK TRANSACTION @savepoint_variable;

--Processing a Batch with Partial Rollbacks
-- 1. Setup
CREATE TABLE dbo.Employees (
    EmployeeID INT PRIMARY KEY,
    FullName VARCHAR(100) NOT NULL,
    Department VARCHAR(50)
);
GO

-- This table variable simulates the batch of new data to be imported.
DECLARE @NewHires TABLE (
    EmployeeID INT,
    FullName VARCHAR(100),
    Department VARCHAR(50)
);

INSERT INTO @NewHires VALUES
(101, 'Alice Williams', 'Engineering'),
(102, 'Bob Johnson', 'Sales'),
(101, 'Charlie Brown', 'Engineering'), -- DUPLICATE EmployeeID! This will fail.
(103, 'Diana Prince', 'HR');
GO

-- 2. The Procedure Logic
PRINT '--- Starting Batch Import with Savepoints ---';

BEGIN TRANSACTION; -- The single, overarching transaction for the whole batch.

DECLARE @CurrentID INT, @CurrentName VARCHAR(100), @CurrentDept VARCHAR(50);

-- Create a cursor to loop through the batch
DECLARE hire_cursor CURSOR FOR
SELECT EmployeeID, FullName, Department FROM @NewHires;

OPEN hire_cursor;
FETCH NEXT FROM hire_cursor INTO @CurrentID, @CurrentName, @CurrentDept;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Create a savepoint for each individual record.
    SAVE TRANSACTION EmployeeSavePoint;

    BEGIN TRY
        -- Attempt to insert the current record
        INSERT INTO dbo.Employees (EmployeeID, FullName, Department)
        VALUES (@CurrentID, @CurrentName, @CurrentDept);

        PRINT 'SUCCESS: Imported EmployeeID ' + CAST(@CurrentID AS VARCHAR) + ' (' + @CurrentName + ').';
    END TRY
    BEGIN CATCH
        -- If the insert fails, roll back to the savepoint for this record ONLY.
        IF (XACT_STATE() = 1) -- Check that the transaction is still committable
        BEGIN
            ROLLBACK TRANSACTION EmployeeSavePoint;
            PRINT 'FAILED: Could not import EmployeeID ' + CAST(@CurrentID AS VARCHAR) + '. Rolling back this record.';
            -- In a real application, you would log the error details here.
            -- SELECT ERROR_MESSAGE()
        END
    END CATCH

    FETCH NEXT FROM hire_cursor INTO @CurrentID, @CurrentName, @CurrentDept;
END

CLOSE hire_cursor;
DEALLOCATE hire_cursor;

-- 3. Finalize the work
-- All valid records have been inserted, now commit the main transaction.
COMMIT TRANSACTION;
PRINT '--- Batch Import Finished ---';
GO

-- 4. Verification
PRINT 'Final state of the Employees table:';
SELECT * FROM dbo.Employees ORDER BY EmployeeID;
GO

-- 5. Cleanup
DROP TABLE dbo.Employees;
GO


------------------------------------------------------------
-----------------------End Adendum--------------------------
------------------------------------------------------------


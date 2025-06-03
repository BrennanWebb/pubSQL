--Deployment script
Use [Master]

CREATE SERVER AUDIT Audit_DDL_Perm_Activity
TO FILE ( 
    FILEPATH = '\\SQ0DB-PRPT01\L$\AuditLogs\',  -- Change as needed
    MAXSIZE = 100 MB,
    MAX_FILES = 10,
    RESERVE_DISK_SPACE = OFF
)
WITH (ON_FAILURE = CONTINUE);
GO
ALTER SERVER AUDIT Audit_DDL_Perm_Activity
WITH (STATE = ON);
GO

--Create a test db
If DB_ID('Test') is not null
	Begin
		Alter database [test] set single_user with rollback immediate;
		Drop database [test];
	End

Create Database [test];

/*https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-action-groups-and-actions?view=sql-server-ver16#database-level-audit-action-groups*/
Use [Test]
CREATE DATABASE AUDIT SPECIFICATION Audit_DDL_Perm_Spec
FOR SERVER AUDIT Audit_DDL_Perm_Activity
ADD (DATABASE_OBJECT_CHANGE_GROUP),         -- Covers CREATE, ALTER, DROP for DB-level objects
ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),      -- Covers CREATE, ALTER, DROP for users/roles
ADD (DATABASE_PERMISSION_CHANGE_GROUP),     -- Covers GRANT, REVOKE, DENY at DB level
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP)     -- Covers ALTER ROLE ... ADD/DROP MEMBER
WITH (STATE = ON);


/*
--Rollback Script
USE [Test];
GO
-- Step 1: Disable the Database Audit Specification if it exists
IF EXISTS (
    SELECT 1
    FROM sys.database_audit_specifications
    WHERE name = 'Audit_DDL_Perm_Spec'
)
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION Audit_DDL_Perm_Spec
    WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION Audit_DDL_Perm_Spec;
END
GO
-- Step 2: Switch to master for server-level operations
USE [master];
GO
-- Step 3: Disable the Server Audit if it exists
IF EXISTS (
    SELECT 1
    FROM sys.server_audits
    WHERE name = 'Audit_DDL_Perm_Activity'
)
BEGIN
    ALTER SERVER AUDIT Audit_DDL_Perm_Activity
    WITH (STATE = OFF);
    
    DROP SERVER AUDIT Audit_DDL_Perm_Activity;
END
GO

*/


----------------------------------------------------

---Lets look at what we just built
Select *
From sys.server_audits

Select *
From sys.server_file_audits

Select *
From sys.database_audit_specifications

Select *
From test_Sandbox.sys.database_audit_specification_details

---------------------------------------------------------

--Now lets look at the logs.
With Action_Desc as (
SELECT 
    action_id,
    name AS action_description,
    string_agg(class_desc+' - '+containing_group_name Collate  SQL_Latin1_General_CP1_CI_AS,' , ') Within Group (Order by action_id) as action_group
FROM sys.dm_audit_actions
WHERE action_id IS NOT NULL
  AND name IS NOT NULL
  AND containing_group_name IS NOT NULL
Group by action_id,
    name

)

SELECT
a.event_time,
a.class_type,
ad.action_description,
a.session_server_principal_name AS executed_by,
a.server_instance_name [client],
a.database_name,
a.schema_name,
a.object_name,
a.object_id,
STRING_AGG(Cast(a.statement as varchar(max)), '') WITHIN GROUP (ORDER BY a.event_time DESC) AS statement   
FROM sys.fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT) A --or L:\AuditLogs
left join Action_Desc AD on A.action_id=AD.action_id
WHERE 1=1
--and a.action_id IN ('CR', 'AL', 'DR') -- CREATE, ALTER, DROP
AND a.class_type NOT IN ('SC')        -- Exclude schema changes
AND Len(a.statement)>1
Group by 
event_time,
class_type,
ad.action_description,
session_server_principal_name,
server_instance_name,
database_name,
schema_name,
object_name,
a.object_id
Order by event_time desc;


--------------------------------------------------
--Lets do some actions that will be logged.
Use Test
Go

Create table Test_Table_1 (N1 int);

Alter table Test_Table_1 
Add N2 varchar(max)

Alter table Test_Table_1 
Alter column N2 varchar(max) Not NULL 

Drop table Test_Table_1


----------------------------
-- Cycle the audit to close the file and start a new one
Use Master
ALTER SERVER AUDIT Audit_DDL_Perm_Activity WITH (STATE = OFF);
ALTER SERVER AUDIT Audit_DDL_Perm_Activity WITH (STATE = ON);
----------------------------

/*
--Powershell
$AuditFolder = "C:\AuditLogs\"
$Now = Get-Date

Get-ChildItem -Path $AuditFolder -Filter "*.sqlaudit" |
Where-Object { $_.CreationTime -lt $Now } |
ForEach-Object {
    Remove-Item $_.FullName -Force
}
*/



--------------------------------------------------------------
--views
Declare @FilePath varchar(1000) = (Select Log_File_Path + Log_File_Name 
									From sys.server_file_audits)
Set @FilePath = Replace(@FilePath,'.sqlaudit', '*.sqlaudit')

Select File_Name, 
		Min(event_time AT TIME ZONE 'UTC' AT TIME ZONE 'Central Standard Time') Min_Event_Time,
		Max(event_time AT TIME ZONE 'UTC' AT TIME ZONE 'Central Standard Time') Max_Event_Time,
		Count(*) CNT
From sys.fn_get_audit_file(@FilePath, DEFAULT, DEFAULT) A
Group by File_Name

------------------------------------------------
/*
Declare @sql nvarchar(max)= '
Use [?]
If (db_id()=1 or db_id()>4)
	Begin Try

			--ALTER DATABASE AUDIT SPECIFICATION Audit_DDL_Perm_Spec
			--WITH (STATE = OFF);
			--DROP DATABASE AUDIT SPECIFICATION Audit_DDL_Perm_Spec;

			CREATE DATABASE AUDIT SPECIFICATION Audit_DDL_Perm_Spec
			FOR SERVER AUDIT Audit_DDL_Perm_Activity
			ADD (SCHEMA_OBJECT_CHANGE_GROUP),			-- Covers CREATE, ALTER, DROP for schema level objects
			ADD (DATABASE_OBJECT_CHANGE_GROUP),         -- Covers CREATE, ALTER, DROP for DB-level objects
			ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),      -- Covers CREATE, ALTER, DROP for users/roles
			ADD (DATABASE_PERMISSION_CHANGE_GROUP),     -- Covers GRANT, REVOKE, DENY at DB level
			ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP)     -- Covers ALTER ROLE ... ADD/DROP MEMBER
			WITH (STATE = ON);

	End Try
	Begin Catch
	End Catch

'
Exec sp_msforeachDB @sql



Declare @sql nvarchar(max)= '
Use [?]
If (db_id()=1 or db_id()>4) and (SELECT Count(*) FROM sys.database_audit_specification_details)<>5
Select DB_Name()
Union All
SELECT Cast(Count(*) as varchar(50)) FROM sys.database_audit_specification_details
'

Exec sp_msforeachDB @sql
*/
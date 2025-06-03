--Deployment script
Use [Master]

CREATE SERVER AUDIT Audit_DDL_Perm_Activity
TO FILE ( 
    FILEPATH = 'C:\AuditLogs\',  -- Change as needed
    MAXSIZE = 100 MB,
    MAX_FILES = 10,
    RESERVE_DISK_SPACE = OFF
)
WITH (ON_FAILURE = CONTINUE);
GO

ALTER SERVER AUDIT Audit_DDL_Perm_Activity
WITH (STATE = ON);
GO


/*https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-action-groups-and-actions?view=sql-server-ver16#database-level-audit-action-groups*/
Use [Test]
CREATE DATABASE AUDIT SPECIFICATION Audit_Database_Spec
FOR SERVER AUDIT Audit_DDL_Perm_Activity
ADD (SCHEMA_OBJECT_CHANGE_GROUP),  --This event is raised when a CREATE, ALTER, or DROP operation is performed on a schema.
ADD (DATABASE_OBJECT_CHANGE_GROUP), -- This event is raised when a CREATE, ALTER, or DROP statement is executed on database objects, such as schemas. This event is raised whenever any database object is created, altered, or dropped.
ADD (DATABASE_PERMISSION_CHANGE_GROUP), --This event is raised whenever a GRANT, REVOKE, or DENY is issued for a statement permission by any principal in SQL Server
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP), --This event is raised whenever a login is added to or removed from a database role. This event class is raised for the sp_addrolemember, sp_changegroup, and sp_droprolemember stored procedures. This event is raised on any Database role member change in any database.
ADD (SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP) --This event is raised whenever a grant, deny, revoke is performed against a schema object.
WITH (STATE = ON);



/*
--Rollback Script
USE [Test];
GO

-- Step 1: Disable the Database Audit Specification if it exists
IF EXISTS (
    SELECT 1
    FROM sys.database_audit_specifications
    WHERE name = 'Audit_Database_Spec'
)
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION Audit_Database_Spec
    WITH (STATE = OFF);
    
    DROP DATABASE AUDIT SPECIFICATION Audit_Database_Spec;
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




Use [Test_Sandbox];
GO

/************************************************************************************************************************
 Author:		Brennan Webb
 Create date:	2023-05-17
 Jira Ticket:	None
 Description:	Tool for creating Change Tracking Scripts
 SLA:			None
 Caller:		None
 Audience:		BI Devs
 Change Log
--------------------------------------------------------------------------------------------------------------------------
| Date       | Jira Ticket ID | Developer           | Change Summarized                                                  |
--------------------------------------------------------------------------------------------------------------------------
|			 |                |                     |                                                                    |
--------------------------------------------------------------------------------------------------------------------------
--Test Harness:

	Declare   @TrackedDB		varchar(250) = '[GIS_Household]'
			, @ChangeTrackDB	varchar(250) = '[GIS_Household_CT]'
			, @Object			varchar(250) = 'GoldenRecord.[individuals]';

	Exec Test_Sandbox.dbo.sp_ChangeTrackingGenerator @TrackedDB, @ChangeTrackDB, @Object;

**************************************************************************************************************************/

CREATE OR ALTER  proc [dbo].[sp_ChangeTrackingGenerator] 
(@TrackedDB			varchar(250) = Null
,@ChangeTrackDB		varchar(250) = Null
,@Object			varchar(250) = Null
 )
 as 

Set NoCount On;
Begin
	
	Declare @SQL			nvarchar(max),
			@SQL2			varchar(max),
			@Action			varchar(50),
			@i				int				= 1,
			@ObjectID		int,
			@PKColumn		varchar(250),
			@PKColumnType	varchar(250)
			;

	Drop table if exists #LoopTable1;
	Create table #LoopTable1 (rid int identity(1,1),[action] varchar(50));
	Insert into #LoopTable1
	Values('Insert'),('Update'),('Delete');
	
	--If exists remove bracketing.
	Set @TrackedDB		= replace(Replace(@TrackedDB,'[',''),']','');
	Set @ChangeTrackDB	= replace(Replace(@ChangeTrackDB,'[',''),']','');
	Set @Object			= replace(Replace(@Object,'[',''),']','');

	--Check all parameters to make sure they are not void.  DBID's can be checked in the same operation.
	If (DB_ID(@TrackedDB) is null OR DB_ID(@ChangeTrackDB) is null OR @Object is Null) Goto Help; --If any of these fields are Null, jump to help section below.

	--Params are not null.  Now validate @object and output its @PKColumn.
	Set @SQL = 'USE '+Quotename(@TrackedDB)+';
				Select @ObjectID = [Object_ID] From '+Quotename(@TrackedDB)+'.[Sys].[Objects] O With (NoLock)
				Where O.[Name] = '''+Parsename(@Object,1)+''' AND O.[Schema_ID]=Schema_ID('''+Parsename(@Object,2)+''');';
		--print @sql
	Exec sp_executesql @SQL,N'@ObjectID int output',@ObjectID=@ObjectID output;
	
	If @ObjectID is Null 
		Begin
			Print 'The object_id for '+Quotename(@TrackedDB)+'.'+IsNull(@Object,'')+' could not be resolved for the parameters supplied.'+Char(10)+  
			'Check spelling and make sure the object exists.'
			Goto Help;
		End 
	
	--Now that we have an object ID, get the PK of the Object.
	Set @SQL = 'USE '+Quotename(@TrackedDB)+';
				Select @PKColumn = QuoteName(c.[Name]),@PKColumnType = QuoteName(t.[Name])
				From '+Quotename(@TrackedDB)+'.SYS.INDEXES I
				INNER JOIN '+Quotename(@TrackedDB)+'.SYS.INDEX_COLUMNS IC on i.[object_id] = ic.[object_id] and i.index_id = ic.index_id
				INNER JOIN '+Quotename(@TrackedDB)+'.SYS.COLUMNS C on ic.[object_id]=c.[object_id] and ic.column_id=c.column_id
				INNER JOIN '+Quotename(@TrackedDB)+'.SYS.TYPES T on C.user_type_id=T.System_Type_ID
				Where i.is_primary_key = 1 and i.[Object_ID]='+Cast(@ObjectID as varchar(50))+';'
	Exec sp_executesql @SQL,N'@PKColumn varchar(250) output,@PKColumnType varchar(250) output ',@PKColumn=@PKColumn output,@PKColumnType=@PKColumnType output;
	
	If @PKColumn is null 
		If @ObjectID is Null 
		Begin
			Print 'The object '+Quotename(@TrackedDB)+'.'+IsNull(@Object,'')+' has no detectable primary key.'+Char(10)+  
			'Please ensure the object has a primary key.'
			Goto Help;
		End 

	--Set quotenames incase of dashes or other trash in the naming convention.
	Set @ChangeTrackDB	= QuoteName(@ChangeTrackDB);
	Set @TrackedDB		= QuoteName(@TrackedDB);
	Set @Object			= QuoteName(Parsename(@Object,2))+'.'+Quotename(Parsename(@Object,1)); 
	Set @PKColumn		= QuoteName(Replace(Replace(@PKColumn,'[',''),']',''));
	
	Print'
--Copy and paste into a new window, then execute!

USE '+@ChangeTrackDB+'
GO

IF NOT EXISTS (Select * From sys.schemas Where [name] ='''+Parsename(@Object,2)+''')
	BEGIN
		Exec(''Create Schema '+Quotename(Parsename(@Object,2))+''');
	END;
GO

--Tracks table version changes
CREATE TABLE '+@Object+'
(
	VersionChangeId bigint not null identity(1,1),
	VersionChangeOperation char(1) not null,
	VersionDate datetime not null default getdate(),
	DatabaseVersionChangeId bigint not null,
	'+@PKColumn+' '+@PKColumnType+' not null,
	constraint PK_'+Parsename(@Object,1)+' primary key clustered (VersionChangeId),
	constraint FK_'+Parsename(@Object,1)+'_DatabaseVersionTracking FOREIGN KEY (DatabaseVersionChangeId) REFERENCES dbo.DatabaseVersionTracking (DatabaseVersionChangeId) ON DELETE CASCADE,
	check(VersionChangeOperation = ''I'' OR VersionChangeOperation = ''U'' OR VersionChangeOperation = ''D'')
)
';

	While @i<=(Select Max(rid) from #LoopTable1)
		Begin
			Set @action =(Select UPPER(LEFT([action],1))+LOWER(SUBSTRING([action],2,LEN([action]))) From #LoopTable1 Where rid=@i);
			Set @SQL = '
USE '+@TrackedDB+'
GO

CREATE OR ALTER TRIGGER '+Parsename(@Object,2)+'.'+Parsename(@Object,1)+'_ChangeTracking_'+@action+' ON '+@Object+'
AFTER '+@action+'
/***************************************************************************
-- Author: '+system_user+'
-- Create date:  '+Cast(cast(getdate() as Date) as varchar(10))+'
-- Jira Ticket: 
-- Description: Executed as a form of change tracking that stores '+@action+' operations in '+@ChangeTrackDB+'.'+@Object+' and '+@ChangeTrackDB+'.dbo.DatabaseVersionTracking
*****************************************************************************/
AS
BEGIN
	SET NOCOUNT ON;

	--Create new database version
	INSERT INTO '+@ChangeTrackDB+'.[dbo].[DatabaseVersionTracking]
	([VersionTableName])
	VALUES('''+Replace(Replace(@Object,'[',''),']','')+''')

	--Create new table version
	INSERT INTO '+@ChangeTrackDB+'.'+@Object+'
	(
		[VersionChangeOperation],
		'+@PKColumn+',
		[DatabaseVersionChangeId]
	)
	SELECT
		'''+Left(@action,1)+''',
		'+@PKColumn+',
		@@IDENTITY
	FROM '+IIF(@action='Delete','Deleted','Inserted')+'
END;
'
		--Print the output
		Print @SQL+Char(10)+'GO';
		Set @SQL=replace(@SQL,'''','''''')
		Set @SQL2 ='--------------------------------------------------------------------------------------------------------------------------------------'
+ISNULL(@SQL2,'') +Char(10)+'IF NOT EXISTS(
SELECT * FROM sys.triggers 
WHERE [name]='''+Parsename(@Object,1)+'_ChangeTracking_'+@action+''' AND parent_id = OBJECT_ID('''+@Object+''')
)
BEGIN
	EXEC('''+@SQL+''')
	INSERT INTO @createdTriggers (TriggerName) SELECT '''+Parsename(@Object,1)+'_ChangeTracking_'+@action+'''
END
--------------------------------------------------------------------------------------------------------------------------------------
'	
		Set @i=@i+1;
	END;
	
	--Print the replicated triggers build
	Print '/*Below script is for adding to dbo.repl_RebuildTriggers '+Char(10)+@SQL2+Char(10)+'*/'

	Return;


	Help:
		Begin
			Print 'Help Section for dbo.ChangeTrackingScripter.
This proc will only output the script necessary for deployment in PROD and for PR.  
Users must copy the message output and execute individually and create files individually in repo.
Ensure you have all necessary parameters supplied.  The following shows parameter meanings.

	@TrackedDB		varchar(250) = ''''--The Database that is being tracked.  This is the source database.  
	@ChangeTrackDB	varchar(250) = ''''--The Database maintaining the tracked metadata.  This is the Change Tracking database.  
	@Object			varchar(250) = ''''--This is the object name, *which should include the schema*. Bracketing is optional. 

------------------------------------

Declare   @TrackedDB		varchar(250) = ''[DB Name To Be Tracked]''
		, @ChangeTrackDB	varchar(250) = ''[Name of the _CT DB]''
		, @Object			varchar(250) = ''dbo.[Customer]'';

Exec Test_Sandbox.dbo.sp_ChangeTrackingGenerator @TrackedDB, @ChangeTrackDB, @Object;
'
			Return;
		End;
END;


GO

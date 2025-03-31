USE [master]
GO

CREATE or ALTER   proc [dbo].[sp_Scripter]
(
	@sql NVARCHAR(MAX) = NULL,
	@sort NVARCHAR(MAX) = NULL,
	@filter NVARCHAR(MAX) = NULL,
	@replace_matrix NVARCHAR(MAX)  = NULL,
	@template NVARCHAR(MAX)  = NULL,
	@print BIT = 0,
	@debug BIT = 0
)
AS

SET NOCOUNT ON
SET STATISTICS XML OFF --Required for use of sp_describe_first_result_set
SET STATISTICS PROFILE OFF --Required for use of sp_describe_first_result_set
--------------------------------------------------------------------------------------------------------
/*Check that all parameters are supplied.*/ 
IF @sql IS NULL OR @replace_matrix IS NULL OR @template IS NULL GOTO Help;
--------------------------------------------------------------------------------------------------------

DECLARE @VersionHistory VARCHAR(MAX) ='Version 1 | Release Notes: https://github.com/BrennanWebb/pubSQL/blob/main/Dev%20Tools/Procedures/sp_Scripter%20Release%20Notes.txt'
DECLARE @NewID VARCHAR(8) =LEFT (NEWID(),8); 

IF @debug = 1 PRINT'##'+@NewID+CHAR(10);
IF @debug = 1 PRINT '@sql: '+@sql+CHAR(10);

--------------------------------------------------------------------------------------------------------
/*First stage. This section creates a randomized, dynamically created temp table that mirrors the source.
  The reason for this is to also handle proc outputs as well.*/ 
DROP TABLE IF EXISTS #TempColumns;
CREATE TABLE #TempColumns (
	 is_hidden						BIT					NULL
	,column_ordinal					INT					NULL
	,name							SYSNAME				NULL
	,is_nullable					BIT					NULL
	,system_type_id					INT					NULL
	,system_type_name				NVARCHAR(256)		NULL
	,max_length						SMALLINT			NULL
	,precision						TINYINT				NULL
	,scale							TINYINT				NULL
	,collation_name					SYSNAME				NULL
	,user_type_id					INT					NULL
	,user_type_database				SYSNAME				NULL
	,user_type_schema				SYSNAME				NULL
	,user_type_name					SYSNAME				NULL
	,assembly_qualified_type_name	NVARCHAR(4000)		NULL
	,xml_collection_id				INT					NULL
	,xml_collection_database		SYSNAME				NULL
	,xml_collection_schema			SYSNAME				NULL
	,xml_collection_name			SYSNAME				NULL
	,is_xml_document				BIT					NULL
	,is_case_sensitive				BIT					NULL
	,is_fixed_length_clr_type		BIT					NULL
	,source_server					SYSNAME				NULL
	,source_database				SYSNAME				NULL
	,source_schema					SYSNAME				NULL
	,source_table					SYSNAME				NULL
	,source_column					SYSNAME				NULL
	,is_identity_column				BIT					NULL
	,is_part_of_unique_key			BIT					NULL
	,is_updateable					BIT					NULL
	,is_computed_column				BIT					NULL
	,is_sparse_column_set			BIT					NULL
	,ordinal_in_order_by_list		SMALLINT			NULL
	,order_by_list_length			SMALLINT			NULL
	,order_by_is_descending			SMALLINT			NULL
	,tds_type_id					INT					NULL
	,tds_length						INT					NULL
	,tds_collation_id				INT					NULL
	,tds_collation_sort_id			TINYINT				NULL
);

-- Get column metadata
INSERT INTO #TempColumns 
EXEC sp_describe_first_result_set @sql;

-- Construct the create table statement dynamically
DECLARE	 @columns NVARCHAR(MAX) = '', @column_names NVARCHAR(MAX) = '';
SELECT	 @columns = @columns + QUOTENAME(name) + ' ' + system_type_name + IIF(is_nullable = 1 ,' NULL,' , ' NOT NULL,')
		,@column_names = @column_names + QUOTENAME(name)+','
FROM #TempColumns;

-- Remove last comma
SET @columns = LEFT(@columns, LEN(@columns) - 1);IF @debug=1 PRINT @columns+CHAR(10);
SET @column_names = LEFT(@column_names, LEN(@column_names) - 1); IF @debug=1 PRINT @column_names+CHAR(10);

-- Final SQL to create a temp table
DECLARE @tableSQL NVARCHAR(MAX) = 'DROP TABLE IF EXISTS ##'+@NewID+'_Prep; '+CHAR(10)+
								 +'CREATE TABLE ##'+@NewID+'_Prep (ScripterID INT IDENTITY(1,1),' + @columns + '); '+CHAR(10);
IF @print=1 PRINT @tableSQL+CHAR(10);
EXEC sp_executesql @tableSQL;

--------------------------------------------------------------------------------------------------------
/*Second stage.  Now that we have the randomized, dynamically created temp table from the query/proc metadata, we can now get results into the temp table.
*/
IF @sql LIKE '%!Select %' ESCAPE'!'
	BEGIN
		SET @sql ='Insert Into ##'+@NewID+'_Prep ('+@column_names+') '+CHAR(10)+
				  +'Select '+@column_names+' '+CHAR(10)+
				  +'From ('+@sql+')A'+CHAR(10)+
				  +IIF(@sort IS NOT NULL,'Order by '+@sort,'')
		IF @print=1 PRINT @sql+CHAR(10);
		EXEC sp_executesql @sql;
	END;
ELSE IF @sql NOT LIKE '%!Select %' ESCAPE'!'
	BEGIN
		SET @sql ='Insert Into ##'+@NewID+'_Prep ('+@column_names+')'+CHAR(10)+
				  ' EXEC sp_executesql N'''+@sql+''' ';
		IF @print=1 PRINT @sql+CHAR(10);
		EXEC sp_executesql @sql;
    END;

--Clean the data per the @filter.
IF @Filter IS NOT NULL
	BEGIN
		SET @sql ='Select * '+CHAR(10)+
		+'Into ##'+@NewID+' '+CHAR(10)+
		+'From ##'+@NewID+'_Prep'+CHAR(10)+
		+'Where '+@Filter;
		EXEC sp_executesql @sql;
	END
ELSE
	BEGIN
		SET @sql ='Select * '+CHAR(10)+
		+'Into ##'+@NewID+' '+CHAR(10)+
		+'From ##'+@NewID+'_Prep';
		EXEC sp_executesql @sql;
	END

--------------------------------------------------------------------------------------------------------
/*Third stage.  Now that we have dynamically added all results from our query or proc into a randomized temp table which has an identity,
we can apply our template text and do replacements.*/

--Splitout the replacement_matrix string
SET @sql = 'Select Identity(int,1,1) ScripterID '+CHAR(10)+
		  +',TRIM(SUBSTRING([Value], 1, CHARINDEX(''='', [Value]) - 1)) [Value] '+CHAR(10)+
		  +',TRIM(SUBSTRING([Value], CHARINDEX(''='', [Value]) + 1, LEN([Value]))) [Replacement] '+CHAR(10)+ 
		  +'into ##'+@NewID+'_replace_matrix '+CHAR(10)+
		  +'From (Select Trim(Value) [Value] From String_Split('''+@replace_matrix+''','',''))A;'
IF @debug=1 PRINT @sql+CHAR(10);
EXEC sp_executesql @sql;

--preset the proper escapement for the template
SET @template= REPLACE(@template,'''',''''''); 
IF @debug=1 PRINT '@template: '+@template+CHAR(10);

--Apply the Replacement_Matrix to the template.
SET @sql = '
Declare @i				int		=  1,
		@Value			varchar(max),
		@Replacement	varchar(max);
While @i<= (Select Max(ScripterID) From ##'+@NewID+'_replace_matrix)
	BEGIN
		Set @Value =(Select [Value] From ##'+@NewID+'_replace_matrix Where ScripterID=@i);
		Set @Replacement =(Select [Replacement] From ##'+@NewID+'_replace_matrix Where ScripterID=@i);

		Select @template = Replace(@Template,@Value,''''''+Cast(''+@Replacement+'' as Varchar(max))+'''''')
		Set @i=@i+1;
	END
'
IF @debug=1 PRINT @sql+CHAR(10);
EXEC sp_executesql @sql, N'@template NVARCHAR(MAX) Output',@template=@template OUTPUT ; 
IF @debug=1 PRINT '@template: '+@template+CHAR(10);

--Cross apply the template.
SET @sql = 'SELECT '''+@template+'''Script '+CHAR(10)+
		  +'FROM ##'+@NewID+' '+CHAR(10);
IF @debug=1 PRINT @sql+CHAR(10);
EXEC sp_executesql @sql;

RETURN;

HELP:
PRINT '
/*
sp_Scripter allows a user to supply any SQL Query or Procedure, a user template, and a replacement matrix for the purpose of dynamic script generation.
This proc only generates script and will never auto-execute DML or DDL on behalf of the user.
See below for examples.

GitHub: https://github.com/BrennanWebb/pubSQL/blob/main/Dev%20Tools/Procedures/sp_Scripter.sql

PARAMETERS:
	@sql NVARCHAR(MAX)				-- This is the sql query or proc that will determine the @template iterations as well as replacement values.
	@sort NVARCHAR(MAX)				-- If any sorting on the SQL query above is needed, provide it here.  Only comma separated feilds are needed. See examples below.
	@filter NVARCHAR(MAX)			-- Allows the user to 
	@replace_matrix NVARCHAR(MAX)	-- This is the replacement matrix for which a user will supply an equivalence string of their choosing.  Comma separations are required between replacement equivalences.
	@template NVARCHAR(MAX)			-- The template is what will be reproduced with proper replacements for every record in the original SQL query or procedure provided via @sql.
	@print BIT						-- Print''s the DML operations performed by sp_Scripter so that users can view sp_scripter operations.
	@debug BIT						-- Helpful for debugging issues with sp_Scripter
--------------------------------------------------------------------
**Note** - This will not bypass server permissions. */

-------------------------------------------------------------------------------------------------------
--Using a Query
-------------------------------------------------------------------------------------------------------
/*This is a bit silly, but it demonstrates how you would take a query (this one is simply using sys.schema table) 
and apply a template (this particular one is mimicing the creation of job steps) and how the replacement matrix is applied.  

NOTE!!!! Keep in mind that whatever you use as your replacement value (left side of the''='') will be used in a replacement statement.
Be careful to use a replacement string that is unique to your template and distinguishable (ex. ''{var1}'').*/

DECLARE @sql NVARCHAR(MAX)=''
	SELECT [name],[schema_id],[principal_id] 
	FROM sys.schemas
	WHERE schema_id<10000 
	and name <>''''dbo''''
'';
DECLARE @sort NVARCHAR(MAX) = ''[name]''; 
DECLARE @replace_matrix VARCHAR(MAX) = ''{Var1}=[ScripterID],{Var2}=[name],{Var3}=[schema_id],{Var4}=[principal_id]''; --[ScripterID] is built into sp_scripter as a default identity column 
DECLARE @template NVARCHAR(MAX) = ''
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, 
		@step_name=N''''Select ''''{Var2}'''' '''', 
		@step_id={Var1}, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N''''TSQL'''', 
		@command=N''''Select {Var2} [name],{Var3} [schema_id] ,{Var4} [principal_id] '''', 
		@database_name=N''''Master'''', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
'';

EXEC sp_Scripter @sql=@sql, @sort=@sort ,@replace_matrix=@replace_matrix ,@template=@template; 
GO
-------------------------------------------------------------------------------------------------------
--Using a Procedure
-------------------------------------------------------------------------------------------------------
/*The example below demonstrates how you would take a proc (this one is using sp_who) 
and apply a template (this template is a kill demo) and how the replacement matrix is applied.
This demo also shows how @filter works as well.

NOTE!!!! Keep in mind that whatever you use as your replacement value (left side of the''='') will be used in a replacement statement.
Be careful to use a replacement string that is unique to your template and distinguishable (ex. ''{var1}'').*/

DECLARE @sql NVARCHAR(MAX)=''sp_who'';
DECLARE @sort NVARCHAR(MAX) = ''[name]''; 
DECLARE @filter NVARCHAR(MAX) = ''[Status] like ''''%Sleep%'''' '';
DECLARE @replace_matrix VARCHAR(MAX) = ''{Var1}=[ScripterID],{Var2}=[Spid],{Var3}=[Status],{Var4}=[LogiName]''; --[ScripterID] is built into sp_scripter as a default column 
DECLARE @template NVARCHAR(MAX) = ''
If ''''Sleeping'''' = ''''{Var3}'''' 
	BEGIN
		Kill {Var2}; /*Don''''t actually exec this!!! It''''s just a demo :)*/
	END;
'';

EXEC sp_Scripter @sql=@sql, @sort=@sort ,@filter=@filter,@replace_matrix=@replace_matrix ,@template=@template;
GO
--------------------------------------------------------------------

'
PRINT '/*'+@VersionHistory+'*/';
RETURN;
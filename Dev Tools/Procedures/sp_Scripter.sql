USE [master]
GO

CREATE or ALTER   proc [dbo].[sp_Scripter]
(
	@sql NVARCHAR(MAX),
	@order_by NVARCHAR(MAX) = NULL, 
	@replace_matrix NVARCHAR(MAX),
	@template NVARCHAR(MAX),
	@print bit = 0,
	@Debug BIT = 0

)
as

SET NOCOUNT ON
SET STATISTICS XML OFF --Required for use of sp_describe_first_result_set
SET STATISTICS PROFILE OFF --Required for use of sp_describe_first_result_set

DECLARE @VersionHistory VARCHAR(MAX) ='Version Release Notes: https://github.com/BrennanWebb/pubSQL/blob/main/Dev%20Tools/Procedures/sp_Scripter%20Release%20Notes.txt'
DECLARE @NewID VARCHAR(8) =LEFT (NEWID(),8); IF @Debug = 1 PRINT'##'+@NewID+CHAR(10);

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
SET @columns = LEFT(@columns, LEN(@columns) - 1);IF @Debug=1 PRINT @columns+CHAR(10);
SET @column_names = LEFT(@column_names, LEN(@column_names) - 1); IF @Debug=1 PRINT @column_names+CHAR(10);

-- Final SQL to create a temp table
DECLARE @tableSQL NVARCHAR(MAX) = 'DROP TABLE IF EXISTS ##'+@NewID+'; '+CHAR(10)+
								 +'CREATE TABLE ##'+@NewID+' (ID INT IDENTITY(1,1),' + @columns + '); '+CHAR(10);
IF @print=1 PRINT @tableSQL+CHAR(10);
EXEC sp_executesql @tableSQL;
--------------------------------------------------------------------------------------------------------

/*Second stage.  Now that we have the randomized, dynamically created temp table from the query/proc metadata, we can now get results into the temp table.
*/
IF @sql LIKE '%!Select %' ESCAPE'!'
	BEGIN
		SET @sql ='Insert Into ##'+@NewID+'('+@column_names+') '+CHAR(10)+
				  +'Select '+@column_names+' '+CHAR(10)+
				  +'From ('+@sql+')A'+CHAR(10)+
				  +IIF(@order_by IS NOT NULL,'Order by '+@order_by,'')
		IF @print=1 PRINT @sql+CHAR(10);
		EXEC sp_executesql @sql;
	END;
ELSE IF @sql NOT LIKE '%!Select %' ESCAPE'!'
	BEGIN
		SET @sql ='Insert Into ##'+@NewID+'('+@column_names+')'+CHAR(10)+
				  ' EXEC sp_executesql N'''+@sql+''' ';
		IF @print=1 PRINT @sql+CHAR(10);
		EXEC sp_executesql @sql;
    END;

--------------------------------------------------------------------------------------------------------

/*Third stage.  Now that we have dynamically added all results from our query or proc into a randomized temp table which has an identity,
we can apply our template text and do replacements.*/

--Splitout the replacement_matrix string
SET @sql = 'Select Identity(int,1,1) ID '+CHAR(10)+
		  +',TRIM(SUBSTRING([Value], 1, CHARINDEX(''='', [Value]) - 1)) [Value] '+CHAR(10)+
		  +',TRIM(SUBSTRING([Value], CHARINDEX(''='', [Value]) + 1, LEN([Value]))) [Replacement] '+CHAR(10)+ 
		  +'into ##'+@NewID+'_replace_matrix '+CHAR(10)+
		  +'From (Select Trim(Value) [Value] From String_Split('''+@replace_matrix+''','',''))A;'
IF @Debug=1 PRINT @sql+CHAR(10);
EXEC sp_executesql @sql;

--preset the proper escapement for the template
SET @template= REPLACE(@template,'''',''''''); 

--Apply the Replacement_Matrix to the template.
SET @sql = '
Declare @i				int		=  1,
		@Value			varchar(max),
		@Replacement	varchar(max);
While @i<= (Select Max(ID) From ##'+@NewID+'_replace_matrix)
	BEGIN
		Set @Value =(Select [Value] From ##'+@NewID+'_replace_matrix Where ID=@i);
		Set @Replacement =(Select [Replacement] From ##'+@NewID+'_replace_matrix Where ID=@i);

		Select @template = Replace(@Template,@Value,''''''+Cast(''+@Replacement+'' as Varchar(max))+'''''')
		Set @i=@i+1;
	END
'
IF @Debug=1 PRINT @sql+CHAR(10);
EXEC sp_executesql @sql, N'@template NVARCHAR(MAX) Output',@template=@template OUTPUT ; 
IF @Print=1 PRINT @template+CHAR(10);

--Cross apply the template.
SET @sql = 'SELECT '''+@template+'''Script '+CHAR(10)+
		  +'FROM ##'+@NewID+' '+CHAR(10);
IF @Debug=1 PRINT @sql+CHAR(10);
EXEC sp_executesql @sql;

RETURN;

HELP:
PRINT '
/*
sp_Scripter allows a user to supply a SQL Query or proc, a template, and a replacement matrix for the purpose of dynamic script generation.

GitHub: https://github.com/BrennanWebb/pubSQL/blob/main/Dev%20Tools/Procedures/sp_Scripter.sql

PARAMETERS:
	@search nvarchar(500)	-- This is the term to be searched.  % can be used mid string wildcard operations. 
								ex. @search = ''From %account'' will return procs containing the string "From dbo.accounts". 
								An exclamation point in your search term "!" can be used to handle special characters (such as underscores and brackets) 
								normally reserved for SQL LIKE operations to be handled as a string literal.
	@db varchar(128)		-- Specify the database(s) if trying to limit results. Use comma separated string, else the entire server will be searched per the granted user permissions.
	@type varchar(50)		-- Distinguishes the type of search being performed. See below for short codes and examples of types.
	@sys_obj bit			-- Suppress system objects by default
	@sort varchar(1000)		-- Pass in a list of comma separated columns to get a custom sort order for returned data.
	@print bit				-- Use this parameter to have the proc print the exec''d code.
	@filter varchar(1000)	-- Post query filter on the returned data set.  This is executed inside of a where clause. Ex. @filter=''[Database]=''''GIS_Household'''''', 

TYPES: 
	sp_search will also allow searches by type, such as column searches and index searches. There are additional search types as well, some less common in usage.
	
	@type IS NULL --General search
	@type in (''index'',''ix'',''i'')
	@type in (''column'',''col'',''c'')
	@type in (''QueryStats'',''qs'')
	@type in (''replication'',''repl'',''r'')
	@type in(''Reference'', ''ref'')
	@type in(''Permission'',''Permissions'',''perm'',''pm'')
	@type in(''Partition'',''part'',''pd'')

See usage examples below.

--------------------------------------------------------------------
**Note** - Some of these executions require View Definition as well as View Server State permission.
*/
-------------------------------------------------------------------------------------------------------
--General Object Search
-------------------------------------------------------------------------------------------------------
--Search for any object or sql agent job that has ''Search_term'' in the name.
sp_search @search =''Search_term'' 

--Search for any object (EXCLUDING system object names) or sql agent job that has ''Search_term'' in the name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'' 

--Search for any object (INCLUDING system object names) or sql agent job that has ''Search_term'' in the name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @sys_obj = 1 


-------------------------------------------------------------------------------------------------------
--Column Search
-------------------------------------------------------------------------------------------------------
--Search for any column (EXCLUDING system columns) that has ''Search_term'' in the column name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''column'' --You can also supply ''col'' or simply ''c'' to denote you want the search type on columns.

--Search for any column (INCLUDING system columns) that has ''Search_term'' in the column name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @sys_obj = 1 , @type = ''column'' --You can also supply ''col'' or simply ''c'' to denote you want the search type on columns.


-------------------------------------------------------------------------------------------------------
--Index Search
-------------------------------------------------------------------------------------------------------
--Search index metadata for ''Search_term'' in the table name or index name over the entire server.
sp_search @search =''Search_term'', @type = ''index'' --You can also supply ''ix'' or simply ''i'' to denote you want the search type on indexes.

--Search index metadata for ''Search_term'' in the table name or index name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''index'' --You can also supply ''ix'' or simply ''i'' to denote you want the search type on indexes.

--Index search also allows for fully qualified 3 part comma separated objects (database.schema.table). If a fully qualified object is supplied, this will supercede any @db comma separated strings. 
sp_search @search = ''msdb.dbo.sysjobs,msdb.dbo.sysjobhistory'' ,@type=''i'';

-------------------------------------------------------------------------------------------------------
--Query Stats Search
-------------------------------------------------------------------------------------------------------
--Search sys.dm_exec_query_stats for ''Search_term'' in the query text.  This function can be filtered just to a specific db, as query_stats are server wide.
--@db is not necessary in this usage since query stats are server level; @db will be ignored.
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''QueryStats'' --You can also supply ''qs'' to denote you want the search type on query stats.


-------------------------------------------------------------------------------------------------------
--Replication Search
-------------------------------------------------------------------------------------------------------
--Search replication objects for ''Search_term'' in subscription and publication names and sources.    
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''repl'' --You can also supply ''r'' to denote you want the search type on replication objects.


-------------------------------------------------------------------------------------------------------
--Referenced Entity Search
-------------------------------------------------------------------------------------------------------
--Search referenced objects for ''Search_term'' via sys.dm_sql_referenced_entities.    
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''reference'' --You can also supply ''ref'' to denote you want the search type on refrence objects.


-------------------------------------------------------------------------------------------------------
--Permissions Search
-------------------------------------------------------------------------------------------------------
--Search permissions for ''Search_term'' via sys.database_permissions and sys.database_roles.
sp_search @search =''<User>, <Login>, Or <Securable>'', @db =''Database_Name'', @type = ''permission'' 

--If @db is not specified, the entire server will be searched by @search term.
sp_search @search =''<User>, <Login>, Or <Securable>'', @type = ''permission'';

--If @db and @search is not specified, the entire server will be searched by @search term.
sp_search @type = ''perm''; 


-------------------------------------------------------------------------------------------------------
--Partition Search
-------------------------------------------------------------------------------------------------------
--Search partitions for ''Search_term'' via sys.indexes and sys.partitions.
sp_search @search =''<tableName>, <indexName>, Or <partitionfunctionName>'', @db =''Database_Name'', @type = ''partition'' 

--If @db is not specified, the entire server will be searched by @search term.
sp_search @search =''<tableName>, <indexName>, Or <partitionfunctionName>'', @type = ''partition'';

--If @db and @search is not specified, the entire server will be searched by @search term.
sp_search @type = ''part''; 

--------------------------------------------------------------------

'

Print '/*'+@VersionHistory+'*/';
Return;
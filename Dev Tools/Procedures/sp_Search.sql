USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb

Purpose: Will search module definitions and sql agent jobs for a user supplied search string 
Example Usage Script (highlight the lines below and Execute): NA

Exec sp_Search 'sys.columns';

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision		Author			Date                 Reason
-------------	---------		-------------------- -------------------------------------------------------------------------------------
00000			Brennan.Webb	9/05/2020			 Implemented
00001			Brennan.Webb	5/09/2021			 Added DB filter
00002			Brennan.Webb	10/12/2022			 Multiple improvements. Simplified naming conventions.  Added various enhancements and string aggregations.
00003			Brennan.Webb	11/28/2022			 Added functionality of search "types".  Credit to Thomas Durst for the build of the index code.
00004			Brennan.Webb	01/13/2023			 Changed agent specific output script.
00005			Brennan.Webb	04/24/2023			 Added filter for system objects.
00006			Brennan.Webb	01/26/2024			 Removed unecessary reference to sys.modules. Switched to using MS function for object_definition().
00007			Brennan.Webb	03/05/2024			 Changed index search to definitive rather than wildcard search.
00008			Brennan.Webb	03/12/2024			 Added Column Search and updated the foreachDB approach away from msForEachDB to custom temp proc.
00009			Brennan.Webb	03/29/2024			 Added search against sys.dm_exec_query_stats.  Also added a custom sort ability.
000010			Brennan.Webb	04/01/2024			 Added ability to print the requested executing command.  This can be used for debugging.
________________________________________________________________________________________________________________
*/

CREATE OR ALTER proc [dbo].[sp_Search]
(
	@search nvarchar(500)= null,
	@db varchar(128) = null,
	@type varchar(50) = null,
	@sys_obj bit = 0, --Suppress system objects by default
	@sort varchar(1000) = Null,
	@print bit = 0
	
)
as
SET NOCOUNT ON

declare @sql nvarchar(max),
		@randtbl varchar(10)= '##'+(Select left(newID(),8))
	   ;

If @search is null goto help;

-------------------------------------------------------------------------------------------------------
--Universal Operations
-------------------------------------------------------------------------------------------------------
--create temp proc to handle messages.
If object_ID('tempdb..##sp_message')is null
Begin
	Exec ('
	Create proc ##sp_message (@string varchar(100) = Null, @int int = Null)
	as
		Begin
			Declare @timestamp varchar (19) =convert(varchar,getdate(),121)
			Set @String = ISNULL(@String,'''')
			RAISERROR (''Message: %s | %d | %s'', 0, 1, @String, @int, @timestamp) WITH NOWAIT;
			return;
		End;
	');
End;

--create temp proc to handle for each db request.
If object_ID('tempdb..##sp_ForEachDB')is null
Begin
	Exec ('CREATE PROCEDURE ##sp_ForEachDB
			@sql_command VARCHAR(MAX)
			AS
			BEGIN
				   SET NOCOUNT ON;
				   DECLARE @database_name VARCHAR(300) -- Stores database name for use in the cursor
				   DECLARE @sql_command_to_execute NVARCHAR(MAX) -- Will store the TSQL after the database name has been inserted
				   -- Stores our final list of databases to iterate through, after filters have been applied
				   DECLARE @database_names TABLE
						  (database_name VARCHAR(100))
				   DECLARE @SQL VARCHAR(MAX) -- Will store TSQL used to determine database list
				   SET @SQL =
				   ''      SELECT
								 SD.name AS database_name
						  FROM sys.databases SD
						  Where sd.name not in (''''tempdb'''',''''model'''')
				   ''
				   -- Prepare database name list
				   INSERT INTO @database_names
						   ( database_name )
				   EXEC (@SQL)
      
				   DECLARE db_cursor CURSOR FOR SELECT database_name FROM @database_names
				   OPEN db_cursor
				   FETCH NEXT FROM db_cursor INTO @database_name
				   WHILE @@FETCH_STATUS = 0
				   BEGIN
						  SET @sql_command_to_execute = REPLACE(@sql_command, ''?'', @database_name) -- Replace "?" with the database name
       
						  EXEC sp_executesql @sql_command_to_execute
						  FETCH NEXT FROM db_cursor INTO @database_name
				   END
				   CLOSE db_cursor;
				   DEALLOCATE db_cursor;
			END;
		');
End;

--check quotename on DB
SET @db		=Trim(Replace(Replace(@db,'[',''),']',''))
--Trim spaces on @search term
SET @search = Trim(@search)

-------------------------------------------------------------------------------------------------------
--General Object Search + SQL Agent
-------------------------------------------------------------------------------------------------------
IF @type IS NULL
	BEGIN
		--create randomized temp  table
		SET @sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([Source] nvarchar(500), [ID] nvarchar(500), [Name] nvarchar(500), [Definition] nvarchar(max), [DataLengthBytes] int, [Type] nvarchar(500));
				  '
		EXEC (@sql);

		--gather information for all object ID's
		select @sql = N'use '+coalesce(Quotename(@db),'[?]')+';
		begin
			exec ##sp_message '''+coalesce(@db,'[?]')+' started general search'';
		end
		begin
			--get object definitions first
			insert into '+@randtbl+' ([Source],[ID],[Name], [Definition], [DataLengthBytes],[Type])
			select ''DB'' as [Source]
			,o.object_id [ID]
			,quotename(db_name()) +''.''+ quotename(object_schema_name(o.object_id,db_id())) +''.''+ quotename(o.[name]) [Name]
			,char(10) +''/*''+ char(10) +
			''Object Type:''+ Isnull(o.[type_desc],''NA'') + char(10) +
			''Object Name:'' + Isnull(quotename(db_name()) +''.''+ quotename(object_schema_name(o.object_id,db_id())) +''.''+ quotename(o.[name]) ,''NA'') + char(10) +
			''Definition:''+ char(10) +
			''*/''+ char(10) +
				''Use '' + Isnull(quotename(db_name()),''NA'') + '';'' + char(10) + ''GO'' + char(10) + 
				Isnull(Cast(object_definition(o.object_id) as varchar(max)),''NA'')  + char(10) + 
				''GO'' + char(10) AS Definition
			,Datalength(Cast(object_definition(o.object_id) as varchar(max))) AS DataLengthBytes
			,o.[type_desc] [Type]
			from [sys].[all_objects] o with (nolock)
			where (Cast(object_definition(o.object_id) as varchar(max)) like ''%!' + @search + '%'' ESCAPE ''!''
				or o.name like ''%!' + @search + '%'' ESCAPE ''!''
				) 
			'+IIF(@sys_obj=0,'','--')+'and o.is_ms_shipped = 0 --Dont include SQL packaged objects if @sys_obj = 0.
			and o.Type_Desc not in (''SYSTEM_TABLE'',''INTERNAL_TABLE'');
		end
		' 
		;
		--print @sys_obj;
		print IIF(@Print =1,@sql,'');

		If @db is null --run over all DB's
			begin
				exec ##sp_ForEachDB @sql; 
			end;
		Else --else only run for single db
			begin
				exec (@sql);
			end;
	

	--get agent jobs which contain search string
		set @sql='
		insert into '+@randtbl+' ([source],[id],[name], [definition], [DataLengthBytes],[type])
		select ''Agent'' as [source]
		,cast(a.job_id as varchar(50)) [id]
		,a.name
		,char(10) +''/*''+ char(10) +
		 ''--Step ID:''+ cast(b.step_id as varchar(10)) + char(10) +
		 ''--Step Name:'' + Isnull(b.step_name,''NA'') + char(10) +
		 ''--Subsystem:'' + Isnull(b.subsystem,''NA'') + char(10) +
		 ''--Database Name:'' + Isnull(b.database_name,''NA'') + char(10) +
		 ''--Command:''+ char(10) + 
		 ''*/''+ char(10) +
		 Isnull(b.command,''NA'') as [definition]
		,Datalength(Isnull(b.command,'''')) AS DataLengthBytes
		,''SQL_AGENT_JOB'' [type]
		from [msdb].[dbo].[sysjobs] a with (nolock)
		left join [msdb].[dbo].[sysjobsteps] b with (nolock) on a.[job_id] = b.[job_id]
		where (b.command like ''%!' + @search + '%''  ESCAPE ''!''
			or b.step_name like ''%!' + @search + '%'' ESCAPE ''!''
			or a.name like ''%!' + @search + '%'' ESCAPE ''!''
			or a.description like ''%!' + @search + '%'' ESCAPE ''!''
			  )
		';
		print IIF(@Print =1,@sql,'');
		Exec(@sql);

		set @sql='Select * From '+@randtbl+' a '+IIF(@sort is not null, 'Order by '+@sort,'Order by [source],[Type],[name]')+';';
		print IIF(@Print =1,@sql,'');
		Exec(@sql);
	
		Return;
	End;

-------------------------------------------------------------------------------------------------------
--Index Search
-------------------------------------------------------------------------------------------------------
--future development. The index script can be shortened now with string_agg() function instead of the for xml path. sp_msforeachdb wont run a script longer than 2000 char.
If @type in ('index','ix','i')
	Begin
		set @sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([Database] Nvarchar(100),[SchemaName] nvarchar(128), [TableName] nvarchar(128), [Published] varchar(3), [IndexName] nvarchar(128), [IndexType] varchar(30), [Disabled] varchar(3), [PrimaryKey] varchar(3), [Unique] varchar(10), [IndexedColumns] nvarchar(MAX), [IncludedColumns] nvarchar(MAX), [AllowsRowLocks] varchar(3), [AllowsPageLocks] varchar(3), [FillFactor] nvarchar(4000), [Padded] varchar(3), [Filter] nvarchar(MAX), [IndexRowCount] bigint, [TotalSpaceMB] numeric, [UsedSpaceMB] numeric, [UnusedSpaceMB] numeric, [UserSeeks] varchar(100), [LastUserSeek] nvarchar(4000), [UserScans] varchar(100), [LastUserScan] nvarchar(4000), [UserLookups] varchar(100), [LastUserLookup] nvarchar(4000), [UserUpdates] varchar(100), [LastUserUpdate] nvarchar(4000), [SystemSeeks] varchar(100), [LastSystemSeek] nvarchar(4000), [SystemScans] varchar(100), [LastSystemScan] nvarchar(4000), [SystemLookups] varchar(100), [LastSystemLookup] nvarchar(4000), [SystemUpdates] varchar(100), [LastSystemUpdate] nvarchar(4000));
				  '
		exec (@sql);
		 

		Set @sql ='use '+coalesce(Quotename(@db),'[?]')+';
		begin
			exec ##sp_message '''+coalesce(@db,'[?]')+' started'';
		end;
		begin
			Insert into '+@randtbl+'
			SELECT DB_Name() [Database]
			, S.[name]	[SchemaName]
			, o.[name] [TableName]
			, o.Is_Published [Published]
			, I.[name] [IndexName]
			, I.[Type_Desc] [IndexType]
			, [Is_Disabled] [Disabled]
			, is_primary_key [PrimaryKey]
			, is_unique [Unique]
			, SUBSTRING(IndexedColumns, 1, LEN(IndexedColumns) - 1)	[IndexedColumns]
			, ISNULL(SUBSTRING(IncludedColumns, 1, LEN(IncludedColumns) - 1), '''') [IncludedColumns]
			, I.[allow_row_locks] [AllowsRowLocks]
			, I.[allow_page_locks] [AllowsPageLocks]
			, FORMAT(I.fill_factor * .01, ''#0%'') [FillFactor]
			, I.is_padded [Padded]
			, ISNULL(SUBSTRING(I.filter_definition, 2, LEN(I.filter_definition) - 2), '''') [Filter]
			-- Index space stats
			, IndexStats.[RowCount] [IndexRowCount]
			, IndexStats.TotalSpaceMB [TotalSpaceMB]
			, IndexStats.UsedSpaceMB [UsedSpaceMB]
			, IndexStats.UnusedSpaceMB [UnusedSpaceMB]
			-- Index usage stats
			, IU.user_seeks [UserSeeks]
			, IU.last_user_seek [LastUserSeek]
			, IU.user_scans [UserScans]
			, IU.last_user_scan [LastUserScan]
			, IU.user_lookups [UserLookups]
			, IU.last_user_lookup [LastUserLookup]
			, IU.user_updates [UserUpdates]
			, IU.last_user_update [LastUserUpdate]
			, IU.system_seeks [SystemSeeks]
			, IU.last_system_seek [LastSystemSeek]
			, IU.system_scans [SystemScans]
			, IU.last_system_scan [LastSystemScan]
			, IU.system_lookups [SystemLookups]
			, IU.last_system_lookup [LastSystemLookup]
			, IU.system_updates [SystemUpdates]
			, IU.last_system_update [LastSystemUpdate]
			From sys.objects o with (nolock) 
			INNER JOIN sys.schemas S with (nolock) ON o.Schema_ID = S.[schema_id]
			INNER JOIN sys.indexes I with (nolock) ON o.Object_ID = I.[object_id]
			LEFT JOIN sys.dm_db_index_usage_stats IU with (nolock) ON IU.database_id = DB_ID() AND I.[object_id] = IU.[object_id] AND I.index_id = IU.index_id
			INNER JOIN (SELECT P.[object_id][TableObjectID]
							, P.index_id[IndexID]
							, P.[Rows][RowCount]
							, CAST(ROUND(((SUM(AU.total_pages) * 8) / 1024.00), 2)AS NUMERIC(36, 2))[TotalSpaceMB]
							, CAST(ROUND(((SUM(AU.used_pages) * 8) / 1024.00), 2)AS NUMERIC(36, 2))[UsedSpaceMB]
							, CAST(ROUND(((SUM(AU.total_pages) - SUM(AU.used_pages)) * 8) / 1024.00, 2)AS NUMERIC(36, 2))[UnusedSpaceMB]
						FROM sys.partitions P WITH(NOLOCK)
						INNER JOIN sys.allocation_units AU WITH(NOLOCK) ON P.[partition_id] = AU.container_id
						GROUP BY P.[object_id]
							, P.index_id
							, P.[Rows]) IndexStats ON I.[object_id] = IndexStats.TableObjectID AND I.index_id = IndexStats.IndexID
			CROSS APPLY (SELECT COL.[name] + '', ''
						   FROM sys.index_columns IC WITH(NOLOCK)
						   INNER JOIN sys.columns COL WITH(NOLOCK) ON IC.[object_id] = COL.[object_id] AND IC.[column_id] = COL.[column_id]
						   WHERE IC.[object_id] = o.Object_ID
							 AND IC.index_id = I.index_id
							 AND IC.is_included_column = 0
						 ORDER BY IC.key_ordinal
						 FOR XML PATH ('''')) IC (IndexedColumns)
			CROSS APPLY (SELECT COL.[name] + '', ''
						   FROM sys.index_columns IC WITH(NOLOCK)
						   INNER JOIN sys.columns COL WITH(NOLOCK) ON IC.[object_id] = COL.[object_id] AND IC.[column_id] = COL.[column_id]
						   WHERE IC.[object_id] = o.Object_ID
							 AND IC.index_id = I.index_id
							 AND IC.is_included_column = 1
						 ORDER BY IC.key_ordinal
						 FOR XML PATH ('''')) IC2 (IncludedColumns)
			WHERE o.[type] = ''U'' --userTables
			 and (o.[Name] = ''' + @search + ''' or I.[name] = ''' + @search + ''')
		end;
'
		print IIF(@Print =1,@sql,'');
		If @db is null --run over all DB's
			begin
				exec ##sp_ForEachDB @sql; 
			end;
		Else --else only run for single db
			begin
				exec (@sql);
			end;
		
		set @sql='Select * From '+@randtbl+' a '+IIF(@sort is not null, 'Order by '+@sort,'Order by 1,2,3,TotalSpaceMB desc')+';';
		print IIF(@Print =1,@sql,'');
		Exec(@sql);
		
		Return;
	End;
-------------------------------------------------------------------------------------------------------
--Column Search
-------------------------------------------------------------------------------------------------------
If @type in ('column','col','c')
	Begin
		set @sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' (ObjectName nvarchar(1000), OrdinalPosition Int, ColumnName nvarchar(256), ColumnDetail nvarchar(2000), ExactMatch Bit);'
		exec (@sql); 

		Set @sql ='use '+coalesce(Quotename(@db),'[?]')+';
		begin
			exec ##sp_message '''+coalesce(@db,'[?]')+' started'';
		end;
		Insert into '+@randtbl+'
		SELECT	db_name()+''.''+object_schema_name(c.Object_ID)+''.''+object_name(c.Object_ID) ObjectName,
			C.COLUMN_ID OrdinalPosition,
			QUOTENAME(C.NAME) ColumnName,
			QUOTENAME(C.NAME) +'' ''+ 
			Case when C.MAX_LENGTH = -1 then Upper(T.NAME) +''(MAX)''
				when C.MAX_LENGTH is not null and T.NAME like ''%char'' then Upper(T.NAME) +''(''+cast(Coalesce(IC.CHARACTER_MAXIMUM_LENGTH, C.MAX_LENGTH) as varchar(20))+'')''
				Else  Upper(T.NAME)
			End	+ iif(c.is_identity=1,'' IDENTITY(''+Cast(IDENT_SEED(object_schema_name(c.Object_ID)+''.''+object_name(c.Object_ID)) as varchar(50))+'',''+Cast(IDENT_INCR(object_schema_name(c.Object_ID)+''.''+object_name(c.Object_ID)) as varchar(50))+'')'','''')
				+ iif(pkc.object_id is not null,'' CONSTRAINT '' +QuoteName(PK.NAME)+'' PRIMARY KEY'','''')
				+ iif(c.is_nullable=1,'' NULL'','' NOT NULL'')
				+ iif(DC.Definition is not Null,'' DEFAULT''+DC.Definition,'''')
				+ iif(fkc.referenced_column_id is not null, '' FOREIGN KEY REFERENCES ''+QuoteName(Object_Schema_Name(FK_Object.Object_ID))+''.''+QuoteName(FK_Object.Name)+'' (''+FK_Column.Name+'')'','''')
				+ iif(c.is_computed=1,''--computed'','''')
				+ iif(c.is_hidden=1,''--hidden'','''')
			ColumnDetail,
			IIF(C.NAME='''+@search+''',1,0) ExactMatch
		FROM SYS.ALL_COLUMNS C With(Nolock) 
		INNER JOIN SYS.TYPES T With(Nolock) on C.system_Type_ID=T.User_Type_ID
		INNER JOIN SYS.ALL_OBJECTS O With(Nolock) on C.object_id=O.object_id
		INNER JOIN SYS.SCHEMAS S With(Nolock) on O.schema_id=s.schema_id
		LEFT JOIN SYS.INDEXES PK With(Nolock) on C.object_id = pk.object_id and pk.is_primary_key = 1
		LEFT JOIN SYS.INDEX_COLUMNS pkc With(Nolock) on pkc.object_id = pk.object_id and pkc.index_id = pk.index_id and c.column_id = pkc.column_id
		LEFT JOIN INFORMATION_SCHEMA.COLUMNS IC With(Nolock) on IC.Table_Name = O.Name and IC.Table_Schema = S.Name and C.Name = IC.Column_Name
		LEFT JOIN SYS.FOREIGN_KEY_COLUMNS fkc With(Nolock) ON o.object_id = fkc.parent_object_id and c.column_id = fkc.parent_column_id 
		LEFT JOIN SYS.ALL_OBJECTS FK_Object With(Nolock) ON fkc.referenced_object_id = FK_Object.object_id
		LEFT JOIN SYS.ALL_COLUMNS FK_Column With(Nolock) ON FK_Object.object_id = FK_Column.object_id AND fkc.referenced_column_id = FK_Column.column_id
		LEFT JOIN SYS.DEFAULT_Constraints DC With(NoLock) ON C.Object_ID = DC.Parent_Object_ID AND C.Column_ID = DC.Parent_Column_ID
		WHERE C.NAME LIKE ''%!' + @search + '%'' ESCAPE ''!'' 
		'+IIF(@sys_obj=0,'','--')+'and o.is_ms_shipped = 0
'
		print IIF(@Print =1,@sql,'');
		If @db is null --run over all DB's
			begin
				exec ##sp_ForEachDB @sql; 
			end;
		Else --else only run for single db
			begin
				print IIF(@Print =1,@sql,'');
				exec (@sql);
			end;
		
		set @sql='Select * From '+@randtbl+' a '+IIF(@sort is not null, 'Order by '+@sort,'Order by ExactMatch desc, 1 asc')+';'; 
		print IIF(@Print =1,@sql,'');
		Exec(@sql);
	
		Return;
	End;

-------------------------------------------------------------------------------------------------------
--Query Stats Search
-------------------------------------------------------------------------------------------------------
If @type in ('QueryStats','qs')
	Begin
		set @sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([DB] NVARCHAR(128) NULL,[Last_Execution_Time] DATETIME NULL,[Text] NVARCHAR(MAX) NULL,[Statement] NVARCHAR(MAX) NULL,[Cache_Hit_Ratio] INT NULL,[Execution_Count] BIGINT NOT NULL,[Total_CPU_Time_MS] BIGINT NOT NULL,[Total_Logical_Reads] BIGINT NOT NULL,[Total_Physical_Reads] BIGINT NOT NULL,[Total_Logical_Writes] BIGINT NOT NULL,[Total_Duration_MS] BIGINT NOT NULL,[Avg_CPU_Time_MS] BIGINT NULL,[Avg_Logical_Reads] BIGINT NULL,[Avg_Physical_Reads] BIGINT NULL,[Avg_Logical_Writes] BIGINT NULL,[Avg_Duration_MS] BIGINT NULL);'
		exec (@sql); 

		Set @sql ='use '+coalesce(Quotename(@db),'[?]')+';
		begin
			exec ##sp_message '''+coalesce(@db,'[?]')+' started'';
		end;
		Insert into '+@randtbl+'
		SELECT 
			DB_NAME(qt.dbid) AS DB,
			qs.Last_Execution_Time,
			qt.[Text],
			SUBSTRING(qt.text,qs.statement_start_offset/2 +1, 
				(IIF(qs.statement_end_offset = -1, LEN(CONVERT(NVARCHAR(MAX), qt.text)) * 2, qs.statement_end_offset - qs.statement_start_offset)/2)) 
			AS [Statement], 
			Cast(Round((qs.total_logical_reads - qs.total_physical_reads)/Nullif(Cast(qs.total_logical_reads as decimal(18,2)),0),2)*100 as int)Cache_Hit_Ratio,
			qs.Execution_Count,
			qs.total_worker_time AS Total_CPU_Time_MS,     
			qs.total_logical_reads AS Total_Logical_Reads,
			qs.total_physical_reads AS Total_Physical_Reads,
			qs.total_logical_writes AS Total_Logical_Writes,
			qs.total_elapsed_time AS Total_Duration_MS,
			qs.total_worker_time/qs.execution_count AS Avg_CPU_Time_MS,
			qs.total_logical_reads/qs.execution_count AS Avg_Logical_Reads,
			qs.total_physical_reads/qs.execution_count AS Avg_Physical_Reads,
			qs.total_logical_writes/qs.execution_count AS Avg_Logical_Writes,
			qs.total_elapsed_time/qs.execution_count AS Avg_Duration_MS

	
		FROM sys.dm_exec_query_stats AS qs  with (NOLOCK)
		Cross Apply sys.dm_exec_sql_text(qs.sql_handle) AS qt
		Where	qt.[text] not like ''%dm_exec_query_stats%''
			AND qt.[text] like ''%!' + @search + '%'' ESCAPE ''!''
		'+IIF(@db is not Null, 'AND DB_NAME(qt.dbid) ='''+@db+''' ','')+'
		;
'
		print IIF(@Print =1,@sql,'');
		exec (@sql);

		set @sql='Select * From '+@randtbl+' a '+IIF(@sort is not null, 'Order by '+@sort,'Order by Cache_Hit_Ratio ASC')+';';  
		print IIF(@Print =1,@sql,'');
		Exec(@sql);

		Return;
	End;

-------------------------------------------------------------------------------------------------------
--Reference Search
-------------------------------------------------------------------------------------------------------
--this needs Error handling.

If @type = 'Reference'
	Begin
		Set @sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([Search_Database] varchar(128), [Search_Term] varchar(500), [Referenced_Object] varchar(500), [Referenced_Object_ID] int, [Referenced_Column] varchar(150), [Referenced_Seq] int, [is_caller_dependent] int,	[is_ambiguous] int,	[is_selected] int,	[is_updated] int,	[is_select_all] int, [is_all_columns_found] int, [is_insert_all] int, [is_incomplete] int);
				  '
		Exec (@sql);

		Set @sql ='	Use '+coalesce(Quotename(@db),'[?]')+';
					Begin
						exec ##sp_message '''+coalesce(@db,'[?]')+' started'';
					End;

					Insert into '+@randtbl+'
					Select '''+coalesce(@db,'[?]')+''' AS [Search_Database]
					,'''+@search+''' AS [Search_Term]
					,Quotename(Coalesce(referenced_database_name,'''+coalesce(@db,'[?]')+''')) + ''.'' + QuoteName(referenced_schema_name) +''.''+ QuoteName(referenced_entity_name) AS  Referenced_Object
					,Object_ID(Quotename(Coalesce(referenced_database_name,'''+coalesce(@db,'[?]')+''')) + ''.'' + QuoteName(referenced_schema_name) +''.''+ QuoteName(referenced_entity_name)) AS  Referenced_Object_ID
					,referenced_minor_name AS Referenced_Column
					,referenced_minor_id AS Referenced_Seq
					,[is_caller_dependent]
					,[is_ambiguous]
					,[is_selected]
					,[is_updated]
					,[is_select_all]
					,[is_all_columns_found]
					,[is_insert_all]
					,[is_incomplete] 
					From sys.dm_sql_referenced_entities ('''+@search+''',''Object'')
					'
		print IIF(@Print =1,@sql,'');
		If @db is null --run over all DB's
			begin
				exec ##sp_ForEachDB @sql; 
			end;
		Else --else only run for single db
			begin
				exec (@sql);
			end;
		
		set @sql='Select * From '+@randtbl+' a; ';
		print IIF(@Print =1,@sql,'');
		Exec(@sql);

		Return;
	End;
-------------------------------------------------------------------------------------------------------
--Help Documentation
-------------------------------------------------------------------------------------------------------
help:
If @search is null
	Begin
		print '
This proc allows a user to search object metadata for terms over all databases or just one database.  
It also searches SQL agent jobs based on job name, step name, or command definition.

PARAMETERS:
	@search nvarchar(500)	-- This is the term to be searched.  % can be used mid string wildcard operations. ex. @search = ''From %account'' will return procs containing the string "From dbo.accounts"
	@db varchar(128)		-- Specify the database if trying to limit results, else the entire server will be searched per the granted user permissions.
	@type varchar(50)		-- Distinguishes the type of search being performed. See below for examples of types.
	@sys_obj bit			-- Suppress system objects by default
	@sort varchar(1000)		-- Pass in a list of comma separated columns to get a custom sort order for returned data.

TYPES: 
	sp_search will also allow searches by type.  Such as column searches and index searches. There are additional search types as well, some less common in usage.
	See examples below.

**Note** - Some of these executions require View Definition as well as View Server State permission.

--------------------------------------------------------------------

--Search for any object or sql agent job that has ''Search_term'' in the name.
sp_search @search =''Search_term'' 

--Search for any object or sql agent job that has ''Search_term'' in the name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'' 

--Search for any object (including system object names) or sql agent job that has ''Search_term'' in the name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @sys_obj = 1 

--Search for any column (EXCLUDING system columns) that has ''Search_term'' in the column name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''column'' --You can also supply ''col'' or simply ''c'' to denote you want the search type on columns.

--Search for any column (including system columns) that has ''Search_term'' in the column name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @sys_obj = 1 , @type = ''column'' --You can also supply ''col'' or simply ''c'' to denote you want the search type on columns.

--Search index metadata for ''Search_term'' in the table name or index name over the entire server.
sp_search @search =''Search_term'', @type = ''index'' --You can also supply ''ix'' or simply ''i'' to denote you want the search type on indexes.

--Search index metadata for ''Search_term'' in the table name or index name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''index'' --You can also supply ''ix'' or simply ''i'' to denote you want the search type on indexes.

--Search sys.dm_exec_query_stats for ''Search_term'' in the query text.  This function can be filtered just to a specific db, as query_stats are server wide.  
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''QueryStats'' --You can also supply ''qs'' to denote you want the search type on query stats.

'
		Return;
	End





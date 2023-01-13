USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_Search]    Script Date: 1/13/2023 2:50:52 PM ******/
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
00004			Brennan.Webb	01/13/2023			 Changed agent specific output script
________________________________________________________________________________________________________________
*/

Create proc [dbo].[sp_Search]
(
	@search nvarchar(max)= null,
	@db varchar(128) = null,
	@type varchar(50) = null
	
)
as
set nocount on

declare @sql nvarchar(max),
		@randtbl varchar(10)= '##'+(Select left(newID(),8))
	   --,@db varchar(128) = '[selectCare-sqs]'
	   --,@search varchar(max)='mapdps'
	   --,@type varchar(50) = 'index';

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

-------------------------------------------------------------------------------------------------------
--General Object Search
-------------------------------------------------------------------------------------------------------
If @type is null
	Begin
		--create randomized temp  table
		set @sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([source] nvarchar(max), [object_id|job_id] nvarchar(max), [name] nvarchar(max), [definition] nvarchar(max), [type] nvarchar(max));
				  '
		exec (@sql);

		--gather information for all object ID's
		select @sql = N'use '+coalesce(@db,'[?]')+';
		begin
			exec ##sp_message '''+coalesce(@db,'[?]')+' started'';
			--if db_id()=2 return;
		end
		begin
			insert into '+@randtbl+' ([source],[object_id|job_id],[name], [definition],[type])
			select ''DB'' as [source]
			,Coalesce(o.object_id,m.[object_id]) [object_id]
			,quotename(db_name()) +''.''+ quotename(object_schema_name(Coalesce(o.object_id,m.[object_id]),db_id())) +''.''+ quotename(o.[name]) [name]
			,m.[definition]
			,cast(o.[type_desc] collate latin1_general_ci_ai as nvarchar(max))[type]
			from [sys].[all_objects] o
			left join [sys].[all_sql_modules] m on m.[object_id]=o.[object_id]
			where (m.definition like ''%' + @search + '%''
				or o.name like ''%' + @search + '%''
					)
			and o.Object_id > 0 --Dont include SQL packaged objects.
			and o.Type_Desc not in (''SYSTEM_TABLE'',''INTERNAL_TABLE'')
			;
		end
		' 
		;

		--print @sql;

		If @db is null --run over all DB's
			begin
				exec sp_msforeachdb @sql; 
			end;
		Else --else only run for single db
			begin
				exec (@sql);
			end;


		--get agent jobs which contain search string
		set @sql='
		insert into '+@randtbl+' ([source],[object_id|job_id],[name], [definition],[type])
		select ''Agent'' as [source]
		,cast(a.job_id as varchar(50)) job_id
		,a.name
		,char(10) +''--------------------------------------------------------''+ char(10) +
		 ''--Step ID:''+ cast(b.step_id as varchar(10)) + char(10) +
		 ''--Step Name:'' + Isnull(b.step_name,''NA'') + char(10) +
		 ''--Subsystem:'' + Isnull(b.subsystem,''NA'') + char(10) +
		 ''--Database Name:'' + Isnull(b.database_name,''NA'') + char(10) +
		 ''--Command:''+ char(10) + Isnull(b.command,''NA'') as [definition]
		,''SQL_AGENT_JOB'' [type]
		from [msdb].[dbo].[sysjobs] a
		left join [msdb].[dbo].[sysjobsteps] b on a.[job_id] = b.[job_id]
		where (b.command like ''%' + @search + '%'' 
			or b.step_name like ''%' + @search + '%''
			or a.name like ''%' + @search + '%''
			  )
		';
		Exec(@sql);


		set @sql='Select * From '+@randtbl+' a Order by [source],[name]; ';
		Exec(@sql);
	
	End;

-------------------------------------------------------------------------------------------------------
--Index Search
-------------------------------------------------------------------------------------------------------
If @type = 'index'
	Begin
		set @sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([SchemaName] nvarchar(128), [TableName] nvarchar(128), [Published] varchar(3), [IndexName] nvarchar(128), [IndexType] varchar(30), [Disabled] varchar(3), [PrimaryKey] varchar(3), [Unique] varchar(10), [IndexedColumns] nvarchar(MAX), [IncludedColumns] nvarchar(MAX), [AllowsRowLocks] varchar(3), [AllowsPageLocks] varchar(3), [FillFactor] nvarchar(4000), [Padded] varchar(3), [Filter] nvarchar(MAX), [IndexRowCount] bigint, [TotalSpaceMB] numeric, [UsedSpaceMB] numeric, [UnusedSpaceMB] numeric, [UserSeeks] varchar(100), [LastUserSeek] nvarchar(4000), [UserScans] varchar(100), [LastUserScan] nvarchar(4000), [UserLookups] varchar(100), [LastUserLookup] nvarchar(4000), [UserUpdates] varchar(100), [LastUserUpdate] nvarchar(4000), [SystemSeeks] varchar(100), [LastSystemSeek] nvarchar(4000), [SystemScans] varchar(100), [LastSystemScan] nvarchar(4000), [SystemLookups] varchar(100), [LastSystemLookup] nvarchar(4000), [SystemUpdates] varchar(100), [LastSystemUpdate] nvarchar(4000));
				  '
		exec (@sql);
		 

		Set @sql ='use '+coalesce(@db,'[?]')+';
begin
	exec ##sp_message '''+coalesce(@db,'[?]')+' started'';
end;
begin
	Insert into '+@randtbl+'
	SELECT S.[name]	[SchemaName]
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
	From sys.objects o  
	INNER JOIN sys.schemas S WITH(NOLOCK) ON o.Schema_ID = S.[schema_id]
	INNER JOIN sys.indexes I WITH(NOLOCK) ON o.Object_ID = I.[object_id]
	LEFT JOIN sys.dm_db_index_usage_stats IU ON IU.database_id = DB_ID() AND I.[object_id] = IU.[object_id] AND I.index_id = IU.index_id
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
	and (o.[Name] like ''%' + @search + '%'' or I.[name] like ''%' + @search + '%'')
end;
'

		If @db is null --run over all DB's
			begin
				exec sp_msforeachdb @sql; 
			end;
		Else --else only run for single db
			begin
				exec (@sql);
			end;
		
		set @sql='Select * From '+@randtbl+' a Order by 1,2,TotalSpaceMB desc; ';
		Exec(@sql);

	End;

-------------------------------------------------------------------------------------------------------
--Help Documentation
-------------------------------------------------------------------------------------------------------
help:
If @search is null
	Begin
		print '
		Allows a user to search object metadata for terms over all databases or just one database.  
		It also searches SQL agent jobs based on job name, step name, or command definition.
		sp_search will also allow searches by type.  Such as index searches, which searches metadata by table name, index name, or column name.
		See examples below.
		--------------------------------------------------------------------

		sp_search @search =''Search_term'' --this will search for any object or sql agent job that has ''Search_term'' in the name.
		sp_search @search =''Search_term'', @db =''Database_Name'' --this will search for any object or sql agent job that has ''Search_term'' in the name and exist only in the specified DB.
		sp_search @search =''Search_term'', @type = ''index''--this will search index metadata for ''Search_term'' in the table name, index name, indexed column over the entire server.
		sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''index''--this will search index metadata for ''Search_term'' in the table name , index name, indexed column and exist only in the specified DB.
		'
	End





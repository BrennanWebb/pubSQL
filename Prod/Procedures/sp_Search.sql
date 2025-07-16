USE [master]
GO

CREATE or ALTER   proc [dbo].[sp_Search]
(
	@search nvarchar(max)= null,
	@db nvarchar(4000) = null,
	@type varchar(50) = null,
	@sys_obj bit = 0, --Suppress system objects by default
	@sort varchar(1500) = Null,
	@print bit = 0,
	@debug bit = 0,
	@filter nvarchar(1000) = Null
)
as
SET NOCOUNT ON
DECLARE @VersionHistory VARCHAR(MAX) ='Version 29 | Release Notes: https://github.com/BrennanWebb/pubSQL/blob/main/Prod/Procedures/sp_Search%20Release%20Notes.txt'
DECLARE @start_time DATETIME = GETDATE();
declare @end_time datetime 
declare @nvar_sql nvarchar(max);
declare @var_sql  varchar(max);
declare	@randtbl nvarchar(10)= '##'+(Select left(newID(),8));
declare @randtbl_loop nvarchar(20) = @randtbl+'_loop';
declare	@sp_randForeachDb nvarchar(15)= Replace(@randtbl,'##','##sp_');
declare @object_id bigint, @object_id_nvar nvarchar(max) 
declare	@object_id_tbl nvarchar(50)= Replace(@randtbl,'##','##object_id_tbl_');
declare @object_id_tbl_cnt int;
declare @error nvarchar(max) = null;
declare @loop int = null;

-------------------------------------------------------------------------------------------------------
--Universal Operation Creation and Param Cleanup
-------------------------------------------------------------------------------------------------------
--Split comma separated @DB, clean it, then bring it back together.
Select @db=String_Agg(Trim(Replace(Replace(Value,'[',''),']','')),',')
From String_Split(coalesce(@db,parsename(@search,3)),',');
IF @debug= 1 Print '@db String: '+@db;

--Trim spaces on @search term
SET @search = Trim(@search)

-------------------------------------------------------------------------------------------------------
--create temp proc to handle messages.
-------------------------------------------------------------------------------------------------------
If object_ID('tempdb..##sp_message')is null
Begin
	Set @nvar_sql='
	Create proc ##sp_message (@string varchar(100) = '''', @int int = '''', @errorseverity int = 0)
	as
		Begin
			Declare @timestamp varchar (19) =convert(varchar,getdate(),121)
			RAISERROR (''Message: %s | %d | %s'', @errorseverity, 1, @String, @int, @timestamp) WITH NOWAIT;
			Return;
		End;
	';
	IF @debug= 1 Print @nvar_sql;
	EXEC sp_executesql @nvar_sql;
End;

-------------------------------------------------------------------------------------------------------
--If @search is blank, we will throw errors and refer to help section.
-------------------------------------------------------------------------------------------------------
--if @Search is blank/null (after trim) and @Type is null (general search), raise error and goto help:
If (Len(@Search)=0 or @Search is null) and @type is null
	Begin
		exec ##sp_message @string ='Exited general search due to zero length or null @search string.  See help documentation below.', @errorseverity=11;
		Goto help
	End;

-------------------------------------------------------------------------------------------------------
--Since @search is not blank, lets see if it is SQL.  We will test if the user is trying to submit a list of terms to be iterated through. 
--Only the first ordinal column will be used (column_id=1). @search must match the pattern 'Select %% From %'.
--This is testing script until further notice.
-------------------------------------------------------------------------------------------------------
If @search like'Select %% From %'
Begin
	SET @nvar_sql = N'		
	Begin Try
		Drop table if exists '+@randtbl_loop+';
		Select *,Identity(int,1,1) RID
		Into '+@randtbl_loop+'
		From ('+@search+')as L;
		
		Set @loop=(Select Count(*) from '+@randtbl_loop+');

		If @loop > 0 
			Begin
				Exec ##sp_message @string =''@search parameter is executable SQL. First column will be used as iterable search terms.''
			End
		Else
			Begin
				Set @error = ''@search parameter is executable SQL. However, no results were returned.''
			End
	End Try
	Begin Catch
	End Catch;
	';
	IF @debug= 1 Print @nvar_sql;
	Exec sp_executeSQL @nvar_sql,N'@loop int Output, @error nvarchar(max) Output', @loop=@loop Output,@error=@error Output;
	If @error is not null
		Begin
			Set @error = @error +' See help documentation below.'
			Exec ##sp_message @string =@error, @errorseverity=11;
			Goto help;
		End
End;
-------------------------------------------------------------------------------------------------------
--See if we can determine any unique object id's by @search string and or @db x @search string.
-------------------------------------------------------------------------------------------------------
Begin
	Set @nvar_sql ='
	Drop table if exists '+@object_id_tbl+';
	Create table '+@object_id_tbl+' (ID int identity(1,1),[DatabaseName] NVARCHAR(128) NULL,[SchemaName] NVARCHAR(128) NULL,[ObjectName] NVARCHAR(128) NULL,[FullObjectName] NVARCHAR(1500) NULL,[Object_ID] INT NULL);
	
	Insert into '+@object_id_tbl+' ([DatabaseName],[SchemaName],[ObjectName],[FullObjectName],[Object_ID])
	Select *
	From (
		Select 
			Parsename(Trim(s.value),3) [DatabaseName],
			Parsename(Trim(s.value),2) [SchemaName],
			Parsename(Trim(s.value),1) [ObjectName],
			QuoteName(Parsename(Trim(s.value),3))+''.''+QuoteName(Parsename(Trim(s.value),2))+''.''+QuoteName(Parsename(Trim(s.value),1)) [FullObjectName],
			Object_ID(QuoteName(Parsename(Trim(s.value),3))+''.''+QuoteName(Parsename(Trim(s.value),2))+''.''+QuoteName(Parsename(Trim(s.value),1)))[Object_ID]
		From String_Split(Replace(Replace(@search,''['',''''),'']'',''''),'','') s
		Where Len(@Search)>0
	)A
	Where [Object_ID] is not null;
	'
	IF @debug= 1 Print @nvar_sql;
	EXEC sp_executesql @nvar_sql, N'@search nvarchar(500), @db nvarchar(4000)',@search=@search, @db=@db;
	Set @object_id_tbl_cnt=@@Rowcount;

	--Object_id search is only available for particular search types. This will limit @db to exactly what is specified.
	If @object_id_tbl_cnt>0 and @type in ('index', 'ix','i')
		Begin
			Set @nvar_sql = 'Select @db= String_Agg([DatabaseName],'','') From '+@object_id_tbl+';'
			IF @debug= 1 Print @nvar_sql;
			EXEC sp_executesql @nvar_sql, N'@db varchar(4000) Output', @db Output;
		End

	If @debug = 1
		Begin
			Set @nvar_sql = 'Select * From '+@object_id_tbl+';'
			EXEC sp_executesql @nvar_sql;
		End;
End;

-------------------------------------------------------------------------------------------------------
--create temp proc to handle for each db request.
-------------------------------------------------------------------------------------------------------
Set @nvar_sql = 'Drop proc if exists '+@sp_randForeachDb+';'; 
IF @debug= 1 Print @nvar_sql;
EXEC sp_executesql @nvar_sql;

Set @nvar_sql ='CREATE PROCEDURE '+@sp_randForeachDb+'
		@nvar_sql_command NVARCHAR(MAX)
		AS
		BEGIN
				SET NOCOUNT ON;
				DECLARE @database_name VARCHAR(300) -- Stores database name for use in the cursor
				DECLARE @nvar_sql_command_to_execute NVARCHAR(MAX) -- Will store the TSQL after the database name has been inserted
				-- Stores our final list of databases to iterate through, after filters have been applied
				DECLARE @database_names TABLE
						(database_name VARCHAR(100))
				DECLARE @nvar_sql NVARCHAR(MAX) -- Will store TSQL used to determine database list
				SET @nvar_sql =
				''      SELECT SD.name AS database_name
						FROM sys.databases SD
						Where sd.name not in (''''tempdb'''',''''model'''')
						and HAS_DBACCESS(SD.name) = 1
						and state_desc = ''''ONLINE''''
						'+IIF(@db like '%!%%' Escape'!',' and sd.name like '''''+@db+''''' ',
						  IIF((@db is null or Len(@db)=0),'',' and sd.name in ('''''+Replace(@db,',',''''',''''')+''''')'))+'
				''
				-- Prepare database name list
				INSERT INTO @database_names( database_name )
				EXEC sp_executesql @nvar_sql;
      
				DECLARE db_cursor CURSOR FOR SELECT database_name FROM @database_names
				OPEN db_cursor
				FETCH NEXT FROM db_cursor INTO @database_name
				WHILE @@FETCH_STATUS = 0
				BEGIN
						SET @nvar_sql_command_to_execute = REPLACE(@nvar_sql_command, ''?'', @database_name) -- Replace "?" with the database name
						--'+IIF(@Print =1,' PRINT @nvar_sql_command_to_execute; ','')+'
						EXEC sp_executesql @nvar_sql_command_to_execute
						FETCH NEXT FROM db_cursor INTO @database_name
				END
				CLOSE db_cursor;
				DEALLOCATE db_cursor;
		END;
	';
IF @debug= 1 Print @nvar_sql;
EXEC sp_executesql @nvar_sql;

-------------------------------------------------------------------------------------------------------
--General Object + SQL Agent Search Module
-------------------------------------------------------------------------------------------------------
IF @type IS NULL
	BEGIN
		--create randomized temp  table
		SET @nvar_sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([Source] nvarchar(500), [ID] nvarchar(500), [Name] nvarchar(500), [Definition] nvarchar(max), [DataLengthBytes] int, [Type] nvarchar(500), [Created] datetime, [Modified] datetime, [Notes] varchar(max) null);
				  '
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql;

		--Search over all object ID's
		select @nvar_sql = N'use [?];
		begin
			exec ##sp_message ''[?] started general search'';
		end
		begin
			--get object definitions first
			insert into '+@randtbl+' ([Source],[ID],[Name], [Definition], [DataLengthBytes], [Type], [Created], [Modified])
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
			,o.create_date	
			,o.modify_date
			from [sys].[all_objects] o with (nolock)
			where (Cast(object_definition(o.object_id) as varchar(max)) like ''%' + @search + '%'' ESCAPE ''!''
				or o.name like ''%' + @search + '%'' ESCAPE ''!''
				) 
			'+IIF(@sys_obj=0,'','--')+'and o.is_ms_shipped = 0 --Dont include SQL packaged objects if @sys_obj = 0.
			and o.Type_Desc not in (''SYSTEM_TABLE'',''INTERNAL_TABLE'')
			
			UNION ALL
			
			--Search over DATABASE Level Triggers
			select ''DB'' as [Source]
			,t.object_id [ID]
			,quotename(db_name()) +''.''+ quotename(object_schema_name(t.object_id,db_id())) +''.''+ quotename(t.[name]) [Name]
			,char(10) +''/*''+ char(10) +
			''Object Type:''+ Isnull(t.[type_desc],''NA'') + char(10) +
			''Object Name:'' + Isnull(quotename(db_name()) +''.''+ quotename(object_schema_name(t.object_id,db_id())) +''.''+ quotename(t.[name]) ,''NA'') + char(10) +
			''Definition:''+ char(10) +
			''*/''+ char(10) +
				''Use '' + Isnull(quotename(db_name()),''NA'') + '';'' + char(10) + ''GO'' + char(10) + 
				Isnull(Cast(object_definition(t.object_id) as varchar(max)),''NA'')  + char(10) + 
				''GO'' + char(10) AS Definition
			,Datalength(Cast(object_definition(t.object_id) as varchar(max))) AS DataLengthBytes
			,t.[type_desc] [Type]
			,t.create_date	
			,t.modify_date
			from [sys].[triggers] t with (nolock)
			where (Cast(object_definition(t.object_id) as varchar(max)) like ''%' + @search + '%'' ESCAPE ''!''
				or t.name like ''%' + @search + '%'' ESCAPE ''!''
				) 
			'+IIF(@sys_obj=0,'','--')+'and t.is_ms_shipped = 0 --Dont include SQL packaged objects if @sys_obj = 0.
			and t.Type_Desc in (''DATABASE'');
			;
		end
		
		exec ##sp_message ''[?] Results Found'', @@Rowcount;

		' 
		;
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);

	--get agent jobs which contain search string
		set @nvar_sql='
		insert into '+@randtbl+' ([source],[id],[name], [definition], [DataLengthBytes], [type], [Created], [Modified])
		select ''Agent'' as [source]
		,cast(a.job_id as varchar(50)) [id]
		,a.name
		,char(10) +''/*''+ char(10) +
		 ''--Job Name:''+ a.name + char(10) +
		 ''--Step ID:''+ cast(b.step_id as varchar(10)) + char(10) +
		 ''--Step Name:'' + Isnull(b.step_name,''NA'') + char(10) +
		 ''--Subsystem:'' + Isnull(b.subsystem,''NA'') + char(10) +
		 ''--Database Name:'' + Isnull(b.database_name,''NA'') + char(10) +
		 ''--Command:''+ char(10) + 
		 ''*/''+ char(10) +
		 Isnull(b.command,''NA'') as [definition]
		,Datalength(Isnull(b.command,'''')) AS DataLengthBytes
		,''SQL_AGENT_JOB'' [type]
		,a.date_created	
		,a.date_modified
		from [msdb].[dbo].[sysjobs] a with (nolock)
		left join [msdb].[dbo].[sysjobsteps] b with (nolock) on a.[job_id] = b.[job_id]
		left join [msdb].[dbo].[sysjobschedules] js ON a.[job_id] = js.[job_id] 
		left join [msdb].[dbo].[sysschedules] s ON js.[schedule_id] = s.[schedule_id]
		where (b.command like ''%' + @search + '%''  ESCAPE ''!''
			or b.step_name like ''%' + @search + '%'' ESCAPE ''!''
			or a.name like ''%' + @search + '%'' ESCAPE ''!''
			or a.description like ''%' + @search + '%'' ESCAPE ''!''
			  )
		';
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql; 

		--Set notes for Agent jobs.  This is a custom script which aggs the job schedules.
		Set @nvar_sql ='
Drop table if exists '+@randtbl+'_Agent_Notes;
Select a.id, 
[Notes] =''Schedule Count: ''+Cast(Count(Distinct s.Schedule_id)as varchar(50))+'' | ''+
String_Agg(CONVERT(VARCHAR(max),
	CASE s.[freq_type]
		WHEN   1 THEN ''Once''
		WHEN   4 THEN ''Daily''
		WHEN   8 THEN ''Weekly''
		WHEN  16 THEN ''Monthly''
		WHEN  32 THEN ''Monthly Relative''
		WHEN  64 THEN ''When SQL Server Agent starts''
		WHEN 128 THEN ''Start whenever the CPU(s) become idle'' 
		ELSE ''''
	END
+'' ''+
CASE s.[freq_type]
	WHEN   1 THEN ''O''
	WHEN   4 THEN ''Every '' + CONVERT(VARCHAR, s.[freq_interval]) + '' day(s)''
	WHEN   8 THEN ''Every '' + CONVERT(VARCHAR, s.[freq_recurrence_factor]) + '' weeks(s) on '' + 
		LEFT(
			CASE WHEN s.[freq_interval] &  1 =  1 THEN ''Sunday, ''    ELSE '''' END + 
			CASE WHEN s.[freq_interval] &  2 =  2 THEN ''Monday, ''    ELSE '''' END + 
			CASE WHEN s.[freq_interval] &  4 =  4 THEN ''Tuesday, ''   ELSE '''' END + 
			CASE WHEN s.[freq_interval] &  8 =  8 THEN ''Wednesday, '' ELSE '''' END + 
			CASE WHEN s.[freq_interval] & 16 = 16 THEN ''Thursday, ''  ELSE '''' END + 
			CASE WHEN s.[freq_interval] & 32 = 32 THEN ''Friday, ''    ELSE '''' END + 
			CASE WHEN s.[freq_interval] & 64 = 64 THEN ''Saturday, ''  ELSE '''' END , 
			LEN(
				CASE WHEN s.[freq_interval] &  1 =  1 THEN ''Sunday, ''    ELSE '''' END + 
				CASE WHEN s.[freq_interval] &  2 =  2 THEN ''Monday, ''    ELSE '''' END + 
				CASE WHEN s.[freq_interval] &  4 =  4 THEN ''Tuesday, ''   ELSE '''' END + 
				CASE WHEN s.[freq_interval] &  8 =  8 THEN ''Wednesday, '' ELSE '''' END + 
				CASE WHEN s.[freq_interval] & 16 = 16 THEN ''Thursday, ''  ELSE '''' END + 
				CASE WHEN s.[freq_interval] & 32 = 32 THEN ''Friday, ''    ELSE '''' END + 
				CASE WHEN s.[freq_interval] & 64 = 64 THEN ''Saturday, ''  ELSE '''' END 
			) - 1
		)
	WHEN  16 THEN ''Day '' + CONVERT(VARCHAR, s.[freq_interval]) + '' of every '' + CONVERT(VARCHAR, s.[freq_recurrence_factor]) + '' month(s)''
	WHEN  32 THEN ''The '' + 
			CASE s.[freq_relative_interval]
				WHEN  1 THEN ''First''
				WHEN  2 THEN ''Second''
				WHEN  4 THEN ''Third''
				WHEN  8 THEN ''Fourth''
				WHEN 16 THEN ''Last'' 
			END +
			CASE s.[freq_interval]
				WHEN  1 THEN '' Sunday''
				WHEN  2 THEN '' Monday''
				WHEN  3 THEN '' Tuesday''
				WHEN  4 THEN '' Wednesday''
				WHEN  5 THEN '' Thursday''
				WHEN  6 THEN '' Friday''
				WHEN  7 THEN '' Saturday''
				WHEN  8 THEN '' Day''
				WHEN  9 THEN '' Weekday''
				WHEN 10 THEN '' Weekend Day'' 
			END + '' of every '' + CONVERT(VARCHAR, s.[freq_recurrence_factor]) + '' month(s)'' 
	ELSE ''''
END
+'' ''+ 
CASE s.[freq_subday_type]
	WHEN 1 THEN ''Occurs once at '' + 
				STUFF(STUFF(RIGHT(''000000'' + CONVERT(VARCHAR(8), s.[active_start_time]), 6), 5, 0, '':''), 3, 0, '':'')
	WHEN 2 THEN ''Occurs every '' + 
				CONVERT(VARCHAR, s.[freq_subday_interval]) + '' Seconds(s) between '' + 
				STUFF(STUFF(RIGHT(''000000'' + CONVERT(VARCHAR(8), s.[active_start_time]), 6), 5, 0, '':''), 3, 0, '':'') + '' and '' + 
				STUFF(STUFF(RIGHT(''000000'' + CONVERT(VARCHAR(8), s.[active_end_time]), 6), 5, 0, '':''), 3, 0, '':'')
	WHEN 4 THEN ''Occurs every '' + 
				CONVERT(VARCHAR, s.[freq_subday_interval]) + '' Minute(s) between '' + 
				STUFF(STUFF(RIGHT(''000000'' + CONVERT(VARCHAR(8), s.[active_start_time]), 6), 5, 0, '':''), 3, 0, '':'') + '' and '' + 
				STUFF(STUFF(RIGHT(''000000'' + CONVERT(VARCHAR(8), s.[active_end_time]), 6), 5, 0, '':''), 3, 0, '':'')
	WHEN 8 THEN ''Occurs every '' + 
				CONVERT(VARCHAR, s.[freq_subday_interval]) + '' Hour(s) between '' + 
				STUFF(STUFF(RIGHT(''000000'' + CONVERT(VARCHAR(8), s.[active_start_time]), 6), 5, 0, '':''), 3, 0, '':'') + '' and '' + 
				STUFF(STUFF(RIGHT(''000000'' + CONVERT(VARCHAR(8), s.[active_end_time]), 6), 5, 0, '':''), 3, 0, '':'')
	ELSE '''' END),'' | '')
Into '+@randtbl+'_Agent_Notes
from '+@randtbl+' a with (nolock)
left join [msdb].[dbo].[sysjobschedules] js ON try_Cast(a.[id] as uniqueidentifier) = js.[job_id] 
left join [msdb].[dbo].[sysschedules] s ON js.[schedule_id] = s.[schedule_id]
Group by a.id
'
;
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql; 

		--Lets take our output of agent notes and update it to the agent records.
		Set @nvar_sql = '
		Update a
		Set a.[Notes]=b.[Notes]
		From '+@randtbl+' a
		Inner join '+@randtbl+'_Agent_Notes b
			On a.id=b.id
			and a.source=''Agent''
		'
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql; 

		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by [source],[Type],[name]')+';';
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

	End;

-------------------------------------------------------------------------------------------------------
--Index Search Module
-------------------------------------------------------------------------------------------------------
If @type in ('index','ix','i')
	Begin
		set @nvar_sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' (ID Int Identity(1,1),[Database] Nvarchar(100),[SchemaName] nvarchar(128), [TableName] nvarchar(128), ObjectID int, [Published] varchar(3), [IndexName] nvarchar(128), [IndexType] varchar(30), [Disabled] varchar(3), [PrimaryKey] varchar(3), [Unique] varchar(10), [IndexedColumns] nvarchar(MAX), [IncludedColumns] nvarchar(MAX), Suggestion varchar(150), [AllowsRowLocks] varchar(3), [AllowsPageLocks] varchar(3), [FillFactor] nvarchar(4000), [Padded] varchar(3), [Filter] nvarchar(MAX), [IndexRowCount] bigint, [TotalSpaceMB] numeric, [UsedSpaceMB] numeric, [UnusedSpaceMB] numeric, [UserSeeks] varchar(100), [LastUserSeek] nvarchar(4000), [UserScans] varchar(100), [LastUserScan] nvarchar(4000), [UserLookups] varchar(100), [LastUserLookup] nvarchar(4000), [UserUpdates] varchar(100), [LastUserUpdate] nvarchar(4000), [SystemSeeks] varchar(100), [LastSystemSeek] nvarchar(4000), [SystemScans] varchar(100), [LastSystemScan] nvarchar(4000), [SystemLookups] varchar(100), [LastSystemLookup] nvarchar(4000), [SystemUpdates] varchar(100), [LastSystemUpdate] nvarchar(4000),DropScript Varchar(max),CreateScript Varchar(max));
				  '
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql;
		 
		Set @nvar_sql ='Use [?];
		Begin
			exec ##sp_message ''[?] started'';
		End;
		begin
			Insert into '+@randtbl+'
			SELECT 
			  DB_Name() [Database]
			, S.[name]	[SchemaName]
			, o.[name] [TableName]
			, o.Object_ID as ObjectID
			, o.Is_Published [Published]
			, I.[name] [IndexName]
			, I.[Type_Desc] [IndexType]
			, [Is_Disabled] [Disabled]
			, is_primary_key [PrimaryKey]
			, is_unique [Unique]
			, IndexedColumns.Cols [IndexedColumns]
			, IncludedColumns.Cols [IncludedColumns]
			, Null as Suggestion
			, I.[allow_row_locks] [AllowsRowLocks]
			, I.[allow_page_locks] [AllowsPageLocks]
			, FORMAT(I.fill_factor * .01, ''#0%'') [FillFactor]
			, I.is_padded [Padded]
			, SUBSTRING(I.filter_definition, 2, LEN(I.filter_definition) - 2) [Filter]
			-- Index space stats
			, IndexStats.[RowCount] [IndexRowCount]
			, IndexStats.TotalSpaceMB
			, IndexStats.UsedSpaceMB
			, IndexStats.UnusedSpaceMB
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
			, NULL as DropScript
			, NULL as CreateScript
			From sys.objects o with (nolock) 
			INNER JOIN sys.schemas S with (nolock) ON o.Schema_ID = S.[schema_id]
			INNER JOIN sys.indexes I with (nolock) ON o.Object_ID = I.[object_id]
			LEFT JOIN sys.dm_db_index_usage_stats IU with (nolock) ON IU.database_id = DB_ID() AND I.[object_id] = IU.[object_id] AND I.index_id = IU.index_id
			INNER JOIN (SELECT ps.[object_id]
							, ps.index_id
							, Sum(ps.row_count) [RowCount]
							, SUM(ps.reserved_page_count) * 8 / 1024.0 AS TotalSpaceMB
							, SUM(ps.used_page_count) * 8 / 1024.0 AS UsedSpaceMB
							, (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8 / 1024.0 AS UnusedSpaceMB
						FROM sys.dm_db_partition_stats ps WITH(NOLOCK)
						GROUP BY ps.[object_id]
							, ps.index_id
						) IndexStats ON I.[object_id] = IndexStats.[object_id] AND I.index_id = IndexStats.index_id
			OUTER APPLY (SELECT STRING_AGG(QuoteName(COL.[name]) + IIF(is_descending_key = 1,'' desc '',''''), '', '') WITHIN GROUP (ORDER BY IC.key_ordinal) AS Cols
						   FROM sys.index_columns IC WITH(NOLOCK)
						   INNER JOIN sys.columns COL WITH(NOLOCK) ON IC.[object_id] = COL.[object_id] AND IC.[column_id] = COL.[column_id]
						   WHERE IC.[object_id] = o.Object_ID
							 AND IC.index_id = I.index_id
							 AND IC.is_included_column = 0) AS IndexedColumns
			OUTER APPLY (SELECT STRING_AGG(QuoteName(COL.[name]), '', '') WITHIN GROUP (ORDER BY IC.key_ordinal) AS Cols
						   FROM sys.index_columns IC WITH(NOLOCK)
						   INNER JOIN sys.columns COL WITH(NOLOCK) ON IC.[object_id] = COL.[object_id] AND IC.[column_id] = COL.[column_id]
						   WHERE IC.[object_id] = o.Object_ID
							 AND IC.index_id = I.index_id
							 AND IC.is_included_column = 1) AS IncludedColumns
			WHERE 1=1
			'+IIF(@sys_obj=0,'','--')+'and o.is_ms_shipped = 0 --Dont include SQL packaged objects if @sys_obj = 0.
			'+IIF((len(@search) = 0 or @search is Null), '',
			  IIF(@object_id_tbl_cnt>0
				,' and exists (Select * From '+@object_id_tbl+' oit Where oit.[DatabaseName]= DB_Name() and o.[object_id]=oit.[object_id]) '
				,' and o.[type] = ''U'' --userTables
			       and (o.[Name] = ''' + @search + ''' or I.[name] = ''' + @search + ''')'
				 )
				 )+'
			;
		end;
'
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql); 

		Set @nvar_sql ='
		Update A
		Set  DropScript = IIF([PrimaryKey]=1
								,''Alter Table ''+ QuoteName([Database])+''.''+QuoteName([SchemaName])+''.''+QuoteName([TableName]) + CHAR(10)+'' Drop Constraint ''+ QuoteName([IndexName])+'';''
								,''Drop Index ''+ QuoteName([IndexName]) + CHAR(10)+ '' ON ''+QuoteName([Database])+''.''+QuoteName([SchemaName])+''.''+QuoteName([TableName])+'';''
							 )+ CHAR(10) 
			,CreateScript = CHAR(10) + 
							IIF([PrimaryKey]=1
									,''ALTER TABLE ''+ QuoteName([Database])+''.''+QuoteName([SchemaName])+''.''+QuoteName([TableName]) + CHAR(10)+ ''ADD CONSTRAINT ''+ QuoteName([IndexName])+ '' PRIMARY KEY ''+ [IndexType]+'' (''+[IndexedColumns]+'');''
									,''Create ''+[IndexType]+'' Index ''+ QuoteName([IndexName])
										+ CHAR(10)+'' ON ''+QuoteName([Database])+''.''+QuoteName([SchemaName])+''.''+QuoteName([TableName]) 
										+ ''(''+ [IndexedColumns]+ '')''
										+ IIF(Len([IncludedColumns]) <>0, CHAR(10)+'' Include( ''+[IncludedColumns]+ '')'', '''')
										+ IIF(Len([Filter])<>0, CHAR(10)+'' Where ''+ [Filter], '''')
										+'';''
								)
		From '+@randtbl+' A
		'
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);

		
		Set @nvar_sql ='
		Update A
		Set Suggestion = IIF(c.Merge_ID is not null,''Merge into #''+Cast(c.Merge_ID as varchar(25)),
						 IIF(b.Dup_ID is not null and c.Merge_ID is null and a.PrimaryKey = 1,''Merge: PK for #''+Cast(b.Dup_ID as varchar(25)),
						 IIF(b.Dup_ID is not null and c.Merge_ID is null,''Drop: Dup of #''+Cast(b.Dup_ID as varchar(25)),
						 Null))) 
		From '+@randtbl+' A
		--Dups
		Outer Apply (Select Min(ID) Dup_ID From  '+@randtbl+' b 
						Where  a.[Database] = b.[Database]
						and a.ObjectID = b.ObjectID
						and a.[IndexedColumns] = b.[IndexedColumns]
						and IsNull(a.[IncludedColumns],'''') =  IsNull(b.[IncludedColumns],'''')
						and a.id > b.id)b
		--Merge
		Outer Apply (Select Min(ID) Merge_ID From  '+@randtbl+' c 
						Where  a.[Database] = c.[Database]
						and a.ObjectID = c.ObjectID
						and a.[IndexedColumns] = c.[IndexedColumns]
						and IsNull(a.[IncludedColumns],'''') <>  IsNull(c.[IncludedColumns],'''')
						and a.id > c.id)c
		'
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);
		
		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by 1,2,3,TotalSpaceMB desc')+';';
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;
		
	End;
-------------------------------------------------------------------------------------------------------
--Column Search Module
-------------------------------------------------------------------------------------------------------
If @type in ('column','col','c')
	Begin
		--if @Search is blank/null (after trim) and @Type = 'column' (column search module), raise error and goto help:
		If (Len(@Search)=0 or @Search is null)
			Begin
				exec ##sp_message @string ='Exited column search due to zero length or null @search string.  See help documentation below.', @errorseverity=11;
				Goto help
			End

		set @nvar_sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' (ObjectName nvarchar(1000), OrdinalPosition Int, ColumnName nvarchar(256), ColumnDetail nvarchar(2000), ExactMatch Bit);'
		EXEC sp_executesql @nvar_sql; 

		Set @nvar_sql ='Use [?];
		Begin
			exec ##sp_message ''[?] started'';
		End;
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
		WHERE C.NAME LIKE ''%' + @search + '%'' ESCAPE ''!'' 
		'+IIF(@sys_obj=0,'','--')+'and o.is_ms_shipped = 0
		;

		Begin
			exec ##sp_message ''[?] Results Found'', @@Rowcount;
		End;
		'
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);
		
		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by ExactMatch desc, 1 asc')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;
	
	End;


-------------------------------------------------------------------------------------------------------
--Schema Search Module
-------------------------------------------------------------------------------------------------------
If @type in ('schema','s')
	Begin
		--if @Search is blank/null (after trim) and @Type = 'column' (column search module), raise error and goto help:
		If (Len(@Search)=0 or @Search is null)
			Begin
				exec ##sp_message @string ='Exited schema search due to zero length or null @search string.  See help documentation below.', @errorseverity=11;
				Goto help
			End

		set @nvar_sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' (ObjectName nvarchar(1000), ExactMatch Bit);'
		EXEC sp_executesql @nvar_sql; 

		Set @nvar_sql ='Use [?];
		Begin
			exec ##sp_message ''[?] started'';
		End;
		Insert into '+@randtbl+'
		SELECT	db_name()+''.''+object_schema_name(o.Object_ID)+''.''+object_name(o.Object_ID) ObjectName,
			IIF(s.NAME='''+@search+''',1,0) ExactMatch
		FROM SYS.ALL_OBJECTS O With(Nolock)
		INNER JOIN SYS.SCHEMAS S With(Nolock) on O.schema_id=s.schema_id
		WHERE S.NAME LIKE ''%' + @search + '%'' ESCAPE ''!'' 
		'+IIF(@sys_obj=0,'','--')+'and o.is_ms_shipped = 0
		;

		Begin
			exec ##sp_message ''[?] Results Found'', @@Rowcount;
		End;
		'
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);
		
		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by 1 asc')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;
	
	End;

-------------------------------------------------------------------------------------------------------
--Query Stats Search Module
-------------------------------------------------------------------------------------------------------
If @type in ('QueryStats','qs')
	Begin
		Set @nvar_sql ='
		begin
			exec ##sp_message ''sys.dm_exec_query_stats started'';
		end;

		Drop table if exists '+@randtbl+';
		SELECT 
			DB_NAME(qt.dbid) AS DB,
			qs.Last_Execution_Time,
			qt.[Text],
			SUBSTRING(qt.text,qs.statement_start_offset/2 +1, 
				(IIF(qs.statement_end_offset = -1, LEN(CONVERT(NVARCHAR(MAX), qt.text)) * 2, qs.statement_end_offset - qs.statement_start_offset)/2)) 
			AS [Statement], 
			qs.Execution_Count,
			------
			Cast(Round(Nullif(Cast(qs.last_logical_reads as decimal(18,2)),0)/(qs.last_logical_reads + qs.last_physical_reads),2)*100 as Int) Last_Cache_Hit_Ratio,
			qs.last_logical_reads						AS Last_Logical_Reads,
			qs.last_physical_reads						AS Last_Physical_Reads,
			qs.last_logical_writes						AS Last_Logical_Writes,
			(qs.last_elapsed_time/ 1000)				AS Last_Duration_MS,
			(qs.last_worker_time/ 1000)					AS Last_CPU_Time_MS,
			qs.last_rows								AS Last_RowCount,
			qs.last_spills								AS Last_Spills,
			qs.last_dop									AS Last_DOP,
			Cast(Round(Cast(qs.Last_used_grant_kb  as decimal(18,2))/Nullif(qs.last_grant_kb,0),2)*100 as Int)			AS Last_Used_Memory_Grant_Ratio,
			Cast(Round(Cast(qs.Last_used_threads  as decimal(18,2)) /Nullif(qs.Last_reserved_threads,0),2)*100 as Int)	AS Last_Used_Thread_Ratio,
			------
			Cast(Round(Nullif(Cast(qs.total_logical_reads as decimal(18,2)),0)/(qs.total_logical_reads + qs.total_physical_reads),2)*100 as Int) Total_Cache_Hit_Ratio,
			qs.total_logical_reads						AS Total_Logical_Reads,
			qs.total_physical_reads						AS Total_Physical_Reads,
			qs.total_logical_writes						AS Total_Logical_Writes,
			(qs.total_elapsed_time / 1000)				AS Total_Duration_MS,
			(qs.total_worker_time / 1000)				AS Total_CPU_Time_MS,
			qs.total_rows								AS Total_RowCount,
			qs.total_spills								AS Total_Spills,
			qs.total_dop								AS Total_DOP,
			Cast(Round(Cast(qs.total_used_grant_kb  as decimal(18,2)) /Nullif(qs.total_grant_kb,0),2)*100 as Int)			AS Total_Used_Memory_Grant_Ratio,
			Cast(Round(Cast(qs.total_used_threads  as decimal(18,2)) /Nullif(qs.total_reserved_threads,0),2)*100 as Int)	AS Total_Used_Thread_Ratio,
			------
			(qs.total_worker_time / 1000)	/qs.execution_count AS Avg_CPU_Time_MS,
			(qs.total_logical_reads	/ 1000)	/qs.execution_count AS Avg_Logical_Reads,
			(qs.total_physical_reads / 1000)/qs.execution_count AS Avg_Physical_Reads,
			(qs.total_logical_writes / 1000)/qs.execution_count AS Avg_Logical_Writes,
			(qs.total_elapsed_time / 1000)	/qs.execution_count AS Avg_Duration_MS
		
		Into '+@randtbl+'
		FROM sys.dm_exec_query_stats AS qs  with (NOLOCK)
		Cross Apply sys.dm_exec_sql_text(qs.sql_handle) AS qt
		Where qt.[text] not like ''%dm_exec_query_stats%'' 
		'+IIF((len(@search) = 0 or @search is Null), '',' AND qt.[text] like ''%' + @search + '%'' ESCAPE ''!'' ')+'
		;
		Print ''QueryStats @@Rowcount: ''+Cast(@@Rowcount as varchar(50));
		'
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql;

		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by Last_Cache_Hit_Ratio ASC')+';';  
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

	End;

-------------------------------------------------------------------------------------------------------
--Replication Search Module
-------------------------------------------------------------------------------------------------------
If @type in ('replication','repl','r')
	Begin
		set @nvar_sql='drop table if exists '+@randtbl+','+@randtbl+'2;
				  create table '+@randtbl+' ([Category] VARCHAR(100) NOT NULL,[PublicationServer] NVARCHAR(500) NULL,[PublicationDB] NVARCHAR(128) NULL,[Publication] NVARCHAR(128) NOT NULL,[PublicationFrequency] VARCHAR(50) NULL,[PublicationStatus] VARCHAR(50) NULL,[PublicationSyncMethod] VARCHAR(55) NULL,[PublicationTableOwner] NVARCHAR(128) NULL,[PublicationTable] NVARCHAR(128) NOT NULL,[SubscriptionServer] NVARCHAR(128) NULL,[SubscriptionDB] NVARCHAR(128) NOT NULL,[SubscriptionOwner] NVARCHAR(128) NULL,[SubscriptionTable] NVARCHAR(128) NOT NULL,SubscriptionFullObjectName NVARCHAR(1000) NULL,[SubscriptionStatus] VARCHAR(50) NULL,[SubscriptionSyncType] VARCHAR(50) NULL,[SubscriptionType] VARCHAR(50) NULL,[SubscriptionUpdateMode] VARCHAR(55) NULL);
				  create table '+@randtbl+'2 ([Category] VARCHAR(100) NOT NULL,[SubscriptionDB] NVARCHAR(128),[SubscriptionSchema] NVARCHAR(128),SubscriptionTable NVARCHAR(250), [SubscriptionFullObjectName] NVARCHAR(500) NULL,[PublicationServer] NVARCHAR(128) NULL,[PublicationDB] NVARCHAR(128) NULL,[Publication] NVARCHAR(128) NULL,[Article] NVARCHAR(128) NULL);
				 '
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql; 

		Set @nvar_sql ='Use [?];
		Begin
			exec ##sp_message ''[?] started'';
		End;

		Declare @nvar_sql nvarchar(max);
		If (Select object_ID(''dbo.syspublications'')) is not null
			Begin
				Set @nvar_sql= 
				''Select 
				  ''''Publication'''' as Category
				, @@SERVERNAME PublicationServer
				, db_name() PublicationDB 
				, sp.name as Publication
				, IIF(sp.repl_freq =0,''''Transaction'''',IIF(sp.repl_freq  =1,''''Scheduled '''',''''Unknown PublicationFrequency: ''''+Cast(sp.repl_freq  as varchar(20)))) PublicationFrequency
				, IIF(sp.status =0,''''Inactive'''',IIF(sp.status  =1,''''Active '''',''''Unknown PublicationStatus: ''''+Cast(sp.status  as varchar(20)))) PublicationStatus
				, IIF(sp.sync_method  =0,''''Native-Mode BCP'''',
				  IIF(sp.sync_method  =1,''''Character-Mode BCP'''',
				  IIF(sp.sync_method  =3,''''Concurrent - Native-Mode BCP with (NOLOCK)'''',
				  IIF(sp.sync_method  =3,''''Concurrent_C - Character-Mode BCP with (NOLOCK)'''',
				  ''''Unknown PublicationSyncMethod: ''''+Cast(sp.sync_method  as varchar(20)))))) PublicationSyncMethod	

				--articles
				, object_schema_Name(sa.objID) PublicationTableOwner
				, sa.name as PublicationTable 

				--subscriptions
				, UPPER(srv.srvname) as SubscriptionServer 
				, s.dest_db as SubscriptionDB
				, sa.dest_owner as SubscriptionOwner
				, sa.dest_table SubscriptionTable
				, s.dest_db +''''.''''+ sa.dest_owner +''''.''''+ sa.dest_table AS SubscriptionFullObjectName
				, IIF(s.status =0,''''Inactive'''',IIF(s.status =1,''''Subscribed'''',IIF(s.status =2,''''Active'''',''''Unknown SubscriptionStatus: ''''+Cast(s.status as varchar(20))))) SubscriptionStatus
				, IIF(s.sync_type =1,''''Automatic'''',IIF(s.sync_type  =2,''''None'''',''''Unknown SubscriptionSyncType: ''''+Cast(s.sync_type  as varchar(20)))) SubscriptionSyncType
				, IIF(s.subscription_type =0,''''Push'''',IIF(s.subscription_type  =1,''''Pull'''',''''Unknown SubscriptionType: ''''+Cast(s.subscription_type  as varchar(20)))) SubscriptionType
				, IIF(s.update_mode =0,''''Read only'''',IIF(s.update_mode  =1,''''Immediate-Updating'''',''''Unknown SubscriptionUpdateMode: ''''+Cast(s.update_mode  as varchar(20)))) SubscriptionUpdateMode
				from dbo.syspublications sp  
				join dbo.sysarticles sa on sp.pubid = sa.pubid 
				join dbo.syssubscriptions s on sa.artid = s.artid 
				join master.dbo.sysservers srv on s.srvid = srv.srvid
				WHERE 1=1
				'+IIF((len(@search) = 0 or @search is Null), '',' AND  (sp.name LIKE ''''%' + @search + '%'''' ESCAPE ''''!''''
												OR sa.name LIKE ''''%' + @search + '%'''' ESCAPE ''''!''''
												OR sa.dest_table LIKE ''''%' + @search + '%'''' ESCAPE ''''!''''
												  )'
					 )+'
				;''

				Insert into '+@randtbl+'
				EXEC sp_executesql @nvar_sql;
			End
		Else
			Begin
				Print ''No Publication Objects''
			End
		;

		If (Select object_ID(''dbo.MSreplication_objects'')) is not null
			Begin
				Set @nvar_sql= 
				''SELECT Distinct
				''''Subscription'''' As Category
				,DB_Name() AS SubscriptionDB
				,Object_Schema_Name(so.object_id) as SubscriptionSchema
				,Object_Name(so.object_id) AS SubscriptionTable
				,DB_Name()+''''.''''+Object_Schema_Name(so.object_id)+''''.''''+Object_Name(so.object_id) SubscriptionFullObjectName
				,r.Publisher  as PublicationServer
				,r.publisher_db as PublicationDB
				,r.Publication
				,r.Article
				FROM dbo.MSreplication_objects R
						INNER JOIN sys.objects so ON Coalesce(r.article,r.object_name) = so.name
				WHERE 1=1
				'+IIF((len(@search) = 0 or @search is Null), '',' AND (Object_Name(so.object_id) LIKE ''''%' + @search + '%'''' ESCAPE ''''!''''
												Or r.Publication LIKE ''''%' + @search + '%'''' ESCAPE ''''!''''
												)'
						)+'
				;''

				Insert into '+@randtbl+'2
				EXEC sp_executesql @nvar_sql;
			End
		Else
			Begin
				Print ''No Subscription Objects''
			End
		;		
'
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);
		
		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by 1 asc')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

		set @nvar_sql='Select * From '+@randtbl+'2 a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by 1 asc')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;
	
	End;

-------------------------------------------------------------------------------------------------------
--Reference Search Module
-------------------------------------------------------------------------------------------------------
If @type in('Reference', 'ref')
	Begin
		Set @nvar_sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([Search_Database] varchar(128), [Search_Term] varchar(500), [Referencing_Object_Type] NVARCHAR(150) NULL,[Referencing_Object_Name] NVARCHAR(1500) NULL,[Referenced_Object] NVARCHAR(1500) NULL,[Referenced_Object_ID] INT NULL,[Referenced_Column] NVARCHAR(128) NULL,[Referenced_Seq] INT NULL,[is_caller_dependent] BIT NOT NULL,[is_ambiguous] BIT NOT NULL,[is_selected] BIT NOT NULL,[is_updated] BIT NOT NULL,[is_select_all] BIT NOT NULL,[is_all_columns_found] BIT NOT NULL,[is_insert_all] BIT NOT NULL,[is_incomplete] BIT NOT NULL)
				  drop table if exists '+@randtbl+'_Messages;
				  create table '+@randtbl+'_Messages ([Messages] varchar(max));
				  '
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql;

		Set @nvar_sql ='	Use [?];
					Begin
						exec ##sp_message ''[?] started'';
					End;
					Begin Try
						Insert into '+@randtbl+'
						Select ''[?]'' AS [Search_Database]
						,'''+@search+''' AS [Search_Term]
						,o.type_desc AS Referencing_Object_Type
						,QuoteName(DB_Name())+''.''+QuoteName(Object_Schema_Name(o.Object_id))+''.''+QuoteName(Object_Name(o.Object_id))AS Referencing_Object_Name
						,Quotename(Coalesce(referenced_database_name,DB_NAME())) + ''.'' + QuoteName(referenced_schema_name) +''.''+ QuoteName(referenced_entity_name) AS  Referenced_Object
						,Object_ID(Quotename(Coalesce(referenced_database_name,DB_NAME())) + ''.'' + QuoteName(referenced_schema_name) +''.''+ QuoteName(referenced_entity_name)) AS  Referenced_Object_ID
						,re.referenced_minor_name AS Referenced_Column
						,re.referenced_minor_id AS Referenced_Seq
						,re.[is_caller_dependent]
						,re.[is_ambiguous]
						,re.[is_selected]
						,re.[is_updated]
						,re.[is_select_all]
						,re.[is_all_columns_found]
						,re.[is_insert_all]
						,re.[is_incomplete] 
					FROM sys.objects AS o
					CROSS APPLY sys.dm_sql_referenced_entities(QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name), ''OBJECT'') AS re
					Where o.is_ms_shipped<>1
					and (re.referenced_entity_name LIKE ''%' + @search + '%'' ESCAPE ''!'' --Referenced_Object
						Or re.referenced_minor_name  LIKE ''%' + @search + '%'' ESCAPE ''!'' --Referenced_Object_Column
						Or o.name LIKE ''%' + @search + '%'' ESCAPE ''!''--Referencing Object
						)
					End Try
						
					Begin Catch
						--We are just catching the errors.  We will do nothing with it.
						Insert into '+@randtbl+'_Messages ([Messages])
						Values(ERROR_MESSAGE());
					End Catch;
					
					Begin
						Exec ##sp_message ''[?] Results Found'', @@Rowcount;
					End;
					'
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);
		
		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by Referencing_Object_Name, Referenced_Object ')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

		set @nvar_sql='Select * From '+@randtbl+'_Messages a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by 1 ')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

	End;

-------------------------------------------------------------------------------------------------------
--Permission Search Module
-------------------------------------------------------------------------------------------------------
If @type in('Permission','Permissions','perm','pm')
	Begin
		Set @nvar_sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([Database] Nvarchar(100),[principal_name] NVARCHAR(128) NOT NULL,[class_desc] NVARCHAR(100) NULL,[Securable] NVARCHAR(500) NULL,[permission_name] NVARCHAR(128) NULL,[state_desc] NVARCHAR(100) NULL,[Script] NVARCHAR(Max) NULL)
				  drop table if exists '+@randtbl+'2;
				  create table '+@randtbl+'2 ([Database] Nvarchar(100),[RoleName] NVARCHAR(128) NOT NULL,[RoleMember] NVARCHAR(128) NOT NULL, [CreateScript] NVARCHAR(500) NOT NULL,[DropScript] NVARCHAR(500) NOT NULL) 
				  '
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql;

		Set @nvar_sql ='	Use [?];
					Begin
						exec ##sp_message ''[?] started'';
					End;

					Insert into '+@randtbl+'
					Select db_name() as DB,
					dps.name principal_name,
					dpm.class_desc, 
					Coalesce(s.[Name],OBJECT_Schema_Name(dpm.Major_ID)+''.''+OBJECT_Name(dpm.Major_ID)) Securable, 
					dpm.permission_name, 
					dpm.state_desc,
					''Use '' + QuoteName(db_name()) + Char(10)+ '''' + dpm.state_desc + '' '' + dpm.permission_name + '' ''
						+IIF(dpm.class_desc = ''DATABASE'', ''TO ''+QuoteName(dps.name),
						+IIF(dpm.class_desc =''SCHEMA'', ''ON SCHEMA::''+QuoteName(Coalesce(s.[Name],OBJECT_Schema_Name(dpm.Major_ID)))+'' TO ''+QuoteName(dps.name),
						+IIF(dpm.class_desc =''OBJECT_OR_COLUMN'', ''ON ''+QuoteName(Coalesce(s.[Name],OBJECT_Schema_Name(dpm.Major_ID)))+''.''+QuoteName(OBJECT_Name(dpm.Major_ID))+'' TO ''+QuoteName(dps.name),
						''''))) collate SQL_Latin1_General_CP1_CI_AS AS Script 
					From sys.database_principals dps 
					Left join sys.database_permissions dpm 
						on dpm.grantee_principal_id =dps.principal_id
					Left join sys.schemas s on dpm.Major_ID  = IIF(dpm.class_desc = ''SCHEMA'', s.schema_ID, Null) 
					Where 1=1
					'+IIF((len(@search) = 0 or @search is Null), '',' AND (dps.name like ''%' + @search + '%'' ESCAPE ''!'' 
													OR s.[Name] like ''%' + @search + '%'' ESCAPE ''!''
													OR OBJECT_Name(dpm.Major_ID) like ''%' + @search + '%'' ESCAPE ''!'' 
													)')+';

					Insert into '+@randtbl+'2
					Select db_name() as DB, rl.name RoleName, QuoteName(p.name) RoleMember, 
					''Use '' + QuoteName(db_name()) + Char(10) + '' Alter Role '' + rl.name + '' Add Member '' + QuoteName(p.name) CreateScript,
					''Use '' + QuoteName(db_name()) + Char(10) + '' Alter Role '' + rl.name + '' Drop Member '' + QuoteName(p.name) DropScript
					From sys.database_role_members drm
					inner join sys.sysusers rl on drm.role_principal_id = rl.uid 
					inner join sys.sysusers p on drm.member_principal_id = p.uid 
					Where 1=1
					'+IIF((len(@search) = 0 or @search is Null), '',' AND (rl.name like ''%' + @search + '%'' ESCAPE ''!'' 
													OR p.name like ''%' + @search + '%'' ESCAPE ''!'' 
													)')+'
					;

					Begin
						Exec ##sp_message ''[?] Results Found'', @@Rowcount;
					End;
					'
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);
		
		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by principal_name, class_desc, permission_name ')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

		set @nvar_sql='Select * From '+@randtbl+'2 a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by 1,2 ')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

	End;

-------------------------------------------------------------------------------------------------------
--Partition Search Module
-------------------------------------------------------------------------------------------------------
If @type in('Partition','part','pd')
	Begin
	Set @nvar_sql='drop table if exists '+@randtbl+';
				  create table '+@randtbl+' ([Database] NVARCHAR(128) NULL, [Schema] NVARCHAR(128) NULL,[Table] NVARCHAR(128) NOT NULL,[IndexName] NVARCHAR(128) NULL,[PartitionNumber] INT NOT NULL,[PartitionFunctionName] NVARCHAR(128) NOT NULL,[Rows] BIGINT NULL,[BoundaryValue] SQL_VARIANT NULL,[TextComparison] VARCHAR(139) NOT NULL)
				  '
		IF @Print = 1 Print @nvar_sql;
		EXEC sp_executesql @nvar_sql;

		Set @nvar_sql ='	Use [?];
					Begin
						exec ##sp_message ''[?] started'';
					End;

					Insert into '+@randtbl+'
					SELECT db_name() as [Database], SCHEMA_NAME(t.schema_id) AS SchemaName, t.name AS TableName, i.name AS IndexName, 
						p.partition_number AS PartitionNumber, f.name AS PartitionFunctionName, p.rows AS Rows, rv.value AS BoundaryValue, 
					CASE WHEN ISNULL(rv.value, rv2.value) IS NULL THEN ''N/A'' 
					ELSE
						CASE WHEN f.boundary_value_on_right = 0 AND rv2.value IS NULL THEN ''>='' 
							WHEN f.boundary_value_on_right = 0 THEN ''>'' 
							ELSE ''>='' 
						END + '' '' + ISNULL(CONVERT(varchar(64), rv2.value), ''Min Value'') + '' '' + 
							CASE f.boundary_value_on_right WHEN 1 THEN ''and <'' 
									ELSE ''and <='' END 
							+ '' '' + ISNULL(CONVERT(varchar(64), rv.value), ''Max Value'') 
					END AS TextComparison
					FROM sys.tables AS t  
					JOIN sys.indexes AS i  
						ON t.object_id = i.object_id  
					JOIN sys.partitions AS p  
						ON i.object_id = p.object_id AND i.index_id = p.index_id   
					JOIN  sys.partition_schemes AS s   
						ON i.data_space_id = s.data_space_id  
					JOIN sys.partition_functions AS f   
						ON s.function_id = f.function_id  
					LEFT JOIN sys.partition_range_values AS r   
						ON f.function_id = r.function_id and r.boundary_id = p.partition_number  
					LEFT JOIN sys.partition_range_values AS rv
						ON f.function_id = rv.function_id
						AND p.partition_number = rv.boundary_id     
					LEFT JOIN sys.partition_range_values AS rv2
						ON f.function_id = rv2.function_id
						AND p.partition_number - 1= rv2.boundary_id
					Where 1=1
					'+IIF((len(@search) = 0 or @search is Null), '',' AND (t.name like ''%' + @search + '%'' ESCAPE ''!'' 
													OR i.name like ''%' + @search + '%'' ESCAPE ''!''
													OR f.name like ''%' + @search + '%'' ESCAPE ''!''
													)')+'
					;
			'
		Set @nvar_sql = 'Exec '+@sp_randForeachDb+' N'''+Replace(@nvar_sql,'''','''''')+''''
		IF @Print = 1 Print @nvar_sql;
		EXEC (@nvar_sql);

		set @nvar_sql='Select * From '+@randtbl+' a '+Char(10)+'Where 1=1 '+IIF(@filter is not null, Char(10)+'AND '+@filter,'')+IIF(@sort is not null, Char(10)+'Order by '+@sort,Char(10)+'Order by 1,2,3,4 ')+';'; 
		print char(10)+@nvar_sql;
		EXEC sp_executesql @nvar_sql;

	End;

-------------------------------------------------------------------------------------------------------
--Master Return
-------------------------------------------------------------------------------------------------------
Set @end_time = getdate();
print char(10)+char(10)+'sp_search run time (seconds):'+Cast(DateDiff(s,@start_time,@end_time)as varchar(50));
Return;
-------------------------------------------------------------------------------------------------------
--Help Documentation
-------------------------------------------------------------------------------------------------------

help:
print '
/*
This proc allows a user to search object metadata for terms over all databases, some databases, or just one database.  
It also searches SQL agent jobs based on job name, step name, or command definition.

GitHub: https://github.com/BrennanWebb/pubSQL/blob/main/Prod/Procedures/sp_Search.sql

'+@VersionHistory+'

PARAMETERS:
	@search nvarchar(500)	-- This is the term to be searched.  % can be used mid string wildcard operations. 
								ex. @search = ''From %account'' will return procs containing the string "From dbo.accounts". 
								An exclamation point in your search term "!" can be used to handle special characters (such as underscores and brackets) normally reserved for SQL LIKE operations to be handled as a string literal.
	@db varchar(128)		-- Specify the database(s) if trying to limit results. Use comma separated string, else the entire server will be searched per the granted user permissions. Single db wildcard also allowed for @db if % character is present. (ex.@db =''DatabaseN%'')
	@type varchar(50)		-- Distinguishes the type of search being performed. See below for short codes and examples of types.
	@sys_obj bit			-- Suppress system objects by default
	@sort varchar(1000)		-- Pass in a list of comma separated columns to get a custom sort order for returned data.
	@print bit				-- Use this parameter to have the proc print the exec''d code.
	@filter varchar(1000)	-- Post query filter on the returned data set.  This is executed inside of a where clause. Ex. @filter=''[Database]=''''GIS_Household'''''', 

TYPES: 
	sp_search will also allow searches by type, such as column searches and index searches. There are additional search types as well, some less common in usage.
	
	@type IS NULL --General search
	@type in (''column'',''col'',''c'')
	@type in (''schema'',''s'')
	@type in (''index'',''ix'',''i'')
	@type in (''QueryStats'',''qs'')
	@type in (''replication'',''repl'',''r'')
	@type in(''reference'', ''ref'')
	@type in(''permission'',''permissions'',''perm'',''pm'')
	@type in(''partition'',''part'',''pd'')

See usage examples below.

--------------------------------------------------------------------
**Note** - Some of these executions require View Definition as well as View Server State permission.
*/
-------------------------------------------------------------------------------------------------------
--General Object Search
-------------------------------------------------------------------------------------------------------
--Search for any object or sql agent job that has ''Search_term'' in the name over the entire server.
sp_search @search =''Search_term'' 

--Search for any object (EXCLUDING system object names) or sql agent job that has ''Search_term'' in the name and exist only in the specified DB.  Use @sys_obj = 1 to include system related objects.
sp_search @search =''Search_term'', @db =''Database_Name'' 


-------------------------------------------------------------------------------------------------------
--Column Search
-------------------------------------------------------------------------------------------------------
--Search for any column (EXCLUDING system columns) that has ''Search_term'' in the column name and exist only in the specified DB.
sp_search @search =''Search_term'', @db =''Database_Name'', @type = ''column'' --You can also supply ''col'' or simply ''c'' to denote you want the search type on columns.  Use @sys_obj = 1 to include system related objects.


-------------------------------------------------------------------------------------------------------
--Schema Search
-------------------------------------------------------------------------------------------------------
--Search for any schema that has ''Search_term'' in the column name and exist only in the specified DB.
sp_search @search =''<Schema Name>'', @db =''<Database_Name>'', @type = ''schema'' --You can also supply ''s''to denote you want the search type on schema. Use @sys_obj = 1 to include system related objects.


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
--Search sys.dm_exec_query_stats for ''Search_term'' in the query text.  This function cannot be filtered to a specific db, as query_stats are server wide. @db will be ignored.
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
Return;





GO



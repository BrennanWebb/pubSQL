USE [Master]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE proc [dbo].[sp_search_module_definitions]
(
@db varchar(50) = null,
@searchforstring nvarchar(max)= null,
@returnfirstfind int = 0
)
as
set nocount on
declare
	@sql varchar(max),
	@i int =1
	;

	--collect all db's
	if object_id('tempdb..##db_loop','u') is not null drop table ##db_loop;
	select name, database_id 
	into ##db_loop
	from master.sys.databases
	where name in (case when @db is null then (Select name from master.sys.databases) else @db end)
	and database_id>4 and database_id not in (11,12);

	--setup loop table for matching records.
	if object_id('tempdb..##search_results','u') is not null drop table ##search_results;
	create table ##search_results ([object_id/job_id] nvarchar(max), [definition/command] nvarchar(max),[name] nvarchar(max),[type_desc/step_name] nvarchar(max));

	--loop through db instances unless explicit instance is provided.
	while @i<=(select max(database_id) from ##db_loop)
		begin
			set @db=(select name from ##db_loop where database_id=@i);
			if @db is null goto skip1;
			
			--search module definitions within in each db.
			if object_id('tempdb..##sproc_loop','u') is not null drop table ##sproc_loop;
			set @sql='select cast(m.[object_id] as varchar(500))[object_id]
			              ,m.[definition]
						  ,'''+@db+'''+''.''+object_schema_name(m.[object_id],db_id('''+@db+'''))+''.''+ o.[name] [name]
						  ,cast(o.[type_desc] collate latin1_general_ci_ai as nvarchar(max))[type_desc]
						  into ##sproc_loop 
						  from '+@db+'.[sys].[all_sql_modules]  m
						  left join '+@db+'.[sys].[all_objects] o on m.[object_id]=o.[object_id]
						  where definition like ''%' + @searchforstring + '%''
					 ' 
					  ; 
			print @sql;
			exec (@sql);

			insert into ##search_results ([object_id/job_id], [definition/command],[name],[type_desc/step_name])
			select [object_id],[definition],[name],[type_desc] from ##sproc_loop;
			
			skip1:
			set @i=@i+1
		end

	select *
	from ##search_results
	union all
	select cast(a.job_id as varchar(500))job_id
	,a.name
	,b.step_name
	,b.command collate latin1_general_ci_ai
	from [msdb].[dbo].[sysjobs] a
	left join [msdb].[dbo].[sysjobsteps] b on a.[job_id] = b.[job_id]
	where b.command like '%' + @searchforstring + '%'
GO


DECLARE @COMMAND VARCHAR(1000) 
	   ,@SEARCHFORSTRING VARCHAR(MAX)='USER';

DROP TABLE IF EXISTS ##SEARCH_RESULTS;
CREATE TABLE ##SEARCH_RESULTS ([OBJECT_ID/JOB_ID] NVARCHAR(MAX), [DEFINITION/COMMAND] NVARCHAR(MAX),[NAME] NVARCHAR(MAX),[TYPE_DESC/STEP_NAME] NVARCHAR(MAX));
SELECT @COMMAND = 'USE [?] 
					Begin
						Print ''? Started'';
						IF DB_ID()=2 Return;
					End
					Begin
						INSERT INTO ##SEARCH_RESULTS ([OBJECT_ID/JOB_ID], [DEFINITION/COMMAND],[NAME],[TYPE_DESC/STEP_NAME])
						SELECT CAST(M.[OBJECT_ID] AS VARCHAR(500))[OBJECT_ID]
						,M.[DEFINITION]
						,''[?].''+OBJECT_SCHEMA_NAME(M.[OBJECT_ID],DB_ID(QUOTENAME(''?'')))+''.''+ O.[NAME] [NAME]
						,CAST(O.[TYPE_DESC] COLLATE LATIN1_GENERAL_CI_AI AS NVARCHAR(MAX))[TYPE_DESC]
						FROM [SYS].[ALL_SQL_MODULES]  M
						LEFT JOIN [SYS].[ALL_OBJECTS] O ON M.[OBJECT_ID]=O.[OBJECT_ID]
						WHERE DEFINITION LIKE ''%' + @SEARCHFORSTRING + '%''
						;
					End
					Begin
						Print ''? Complete'';
					End
				  ' 
				;

PRINT @COMMAND;
EXEC SP_MSFOREACHDB @COMMAND; 

SELECT *
FROM ##SEARCH_RESULTS
UNION ALL
SELECT CAST(A.JOB_ID AS VARCHAR(500))JOB_ID
,A.NAME
,B.STEP_NAME
,B.COMMAND COLLATE LATIN1_GENERAL_CI_AI
FROM [MSDB].[DBO].[SYSJOBS] A
LEFT JOIN [MSDB].[DBO].[SYSJOBSTEPS] B ON A.[JOB_ID] = B.[JOB_ID]
WHERE B.COMMAND LIKE '%' + @SEARCHFORSTRING + '%'
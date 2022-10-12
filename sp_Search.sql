USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_Search]    Script Date: 10/12/2022 10:35:12 AM ******/
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
________________________________________________________________________________________________________________
*/

ALTER proc [dbo].[sp_Search]
(
	@search nvarchar(max)= null,
	@db varchar(128) = null,
	@returnfirstfind int = 0
	
)
as
set nocount on
declare @sql varchar(max),
		@randtbl varchar(10)= '##'+(Select left(newID(),8))
	   --,@db varchar(128) = 'commissions_sqs'
	   --,@search varchar(max)='Kratos';

set @sql='drop table if exists '+@randtbl+';
		  create table '+@randtbl+' ([source] nvarchar(max), [object_id|job_id] nvarchar(max), [name] nvarchar(max), [definition] nvarchar(max), [type] nvarchar(max));
		  '
exec (@sql);
select @sql = 'use '+coalesce(@db,'[?]')+'
					begin
						exec sp_message ''? started'';
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
						and o.Type_Desc not in (''SYSTEM_TABLE'')
						;
					end
				  ' 
				;

--print @sql;

if @db is null --run over all DB's
	begin
		exec sp_msforeachdb @sql; 
	end
Else --else only run for single db
	begin
		exec (@sql)
	end



set @sql='
insert into '+@randtbl+' ([source],[object_id|job_id],[name], [definition],[type])
select ''Agent'' as [source]
,cast(a.job_id as varchar(50)) job_id
,a.name
,''--Step ID:''+ cast(b.step_id as varchar(10)) + char(10) +
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


set @sql='Select * From '+@randtbl+' a ; ';
Exec(@sql);



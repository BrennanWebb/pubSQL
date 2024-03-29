USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_Search_Module_Definitions]    Script Date: 2/12/2021 5:14:54 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb

Purpose: Will search module definitions and sql agent jobs for a user supplied search string 
Example Usage Script (highlight the lines below and Execute): NA

Exec sp_Search_Module_Definitions 'sys.columns';

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision		Author			Date                 Reason
-------------	---------		-------------------- -------------------------------------------------------------------------------------
00000			Brennan.Webb	9/05/2020			 Implemented
00001			Brennan.Webb	5/09/2021			 Added DB filter
________________________________________________________________________________________________________________
*/

create proc [dbo].[sp_Search_Module_Definitions]
(
	@searchforstring nvarchar(max)= null,
	@returnfirstfind int = 0,
	@db varchar(128) = null
)
as
set nocount on
declare @sql varchar(max),
		@randtbl varchar(10)= '##'+(Select left(newID(),8))
	   --,@db varchar(128) = 'commissions_sqs'
	   --,@searchforstring varchar(max)='Kratos';

set @sql='drop table if exists '+@randtbl+';
		  create table '+@randtbl+' ([object_id/job_id] nvarchar(max), [definition/command] nvarchar(max),[name] nvarchar(max),[type_desc/step_name] nvarchar(max));
		  '
exec (@sql);
select @sql = 'use '+coalesce(@db,'[?]')+'
					begin
						exec sp_message ''? started'';
						if db_id()=2 return;
					end
					begin
						insert into '+@randtbl+' ([object_id/job_id], [definition/command],[name],[type_desc/step_name])
						select cast(m.[object_id] as varchar(500))[object_id]
						,m.[definition]
						,quotename(db_name()) +''.''+ quotename(object_schema_name(m.[object_id],db_id())) +''.''+ quotename(o.[name]) [name]
						,cast(o.[type_desc] collate latin1_general_ci_ai as nvarchar(max))[type_desc]
						from [sys].[all_sql_modules]  m
						left join [sys].[all_objects] o on m.[object_id]=o.[object_id]
						where definition like ''%' + @searchforstring + '%''
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
select *
from '+@randtbl+'
union all
select cast(a.job_id as varchar(50))job_id
,a.name
,b.step_name
,b.command collate latin1_general_ci_ai
from [msdb].[dbo].[sysjobs] a
left join [msdb].[dbo].[sysjobsteps] b on a.[job_id] = b.[job_id]
where b.command like ''%' + @searchforstring + '%''
';
Exec(@sql);



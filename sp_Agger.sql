﻿alter proc [dbo].[sp_Agger](@agg varchar(25),@fields varchar(5000),@isnull varchar(50) = null)
as
/*
________________________________________________________________________________________________________________
Purpose: Allows a user to supply a comma separated list of fields (ex [F1],[F2],[F3],etc) and a SQL function string which will be concatenated together and string endings renamed.
Example Usage Script (just highlight the lines below and execute):

	exec sp_agger 'count',
	',[ProviderKey]
	,[LastName]
	,[FirstName]
	,[MiddleName]
	,[Suffix]
	,[Title]
	' 
________________________________________________________________________________________________________________
*/

declare @leading_comma char  =''
		,@xmlstring xml
		,@i int               =1 
		,@sql varchar(max)    =''
		,@sql1 varchar(max)    =''
		,@f varchar(500)
		,@fs_out varchar(max)=''
		--,@agg varchar(25)='count'
		--,@fields varchar(5000) =',[c0d],[c1],[c1d]'      
		  
if left(@fields,1)in (',') --check if leading comma exists
	begin
		set @fields=stuff(@fields, 1, 1, ''); --remove leading comma
		set @leading_comma=',' --set leading comma variable.  will be used at the end if it was removed at the start.
	end;
if object_id('tempdb..##agger') is not null drop table ##agger;
select convert(xml,'<fs><f>'+replace(@fields,',','</f><f>') + '</f></fs>')xmlstring--convert to xml string
into ##agger;

while @i<=(select xmlstring.value('count(/fs/*)', 'int') from ##agger) --count subnodes and begin looping
	begin
		if object_id('tempdb..##fholder') is not null drop table ##fholder;
		set @sql='create table ##fholder(['+@agg+'] varchar(max));
		insert into ##fholder
		select rtrim(ltrim(xmlstring.value(''/fs[1]/f['+cast(@i as nvarchar(3))+']'',''varchar(100)'')))
		from ##agger '
		--print @sql
		exec (@sql);
		set @sql='';
		-----------------
		set @f=(select * from ##fholder);
		set @sql1=@sql1+'select '''+(case when @i=1 then @leading_comma else ',' end)
					  +@agg+'('+(case when @isnull is not null then 'isnull(' else'' end)
		              +@f+(case when @isnull is not null then ','+@isnull+')' else'' end) --still need to account for varchar possibilities
					  +') '+@f+''' as['+@agg+']'+
		              'from ##agger'
		              +char(13)+' union all '+char(13); 
	set @i=@i+1;
	end;
set @sql1=ltrim(stuff(@sql1,len(@sql1)-len(' union all '+char(13)),len(' union all '+char(13)),''));
--print @sql1;
exec(@sql1);

GO

/*
________________________________________________________________________________________________________________
Purpose: Scrub table columns keeping only the designated @extracttype.  
Multiple column names may be specified as long as they are comma separated.  See example below.

Example Usage Script (highlight the lines below and execute once sproc is installed):

	Begin
		if object_id('tempdb..#test_table') is not null drop table #test_table;
		with num1 (n) as (
		select 1 as n
		union all 
		select n+1 as n
		from num1 
		where n < 249)
		,num2 (n) as (select 1 from num1 as x, num1 as y)
		,nums (n) as (select row_number() over(order by n) from num2)

		select n, char(n) charLiteral
		into #test_table
		from nums
		where len(char(n))>0 
		OPTION ( MAXRECURSION 0 )
		;

		Exec sp_scrub '#test_table','charLiteral','N'; 
	End

Parameter Definitions
---------- 
@inputstring      -- string from which the values to be extracted 
@extracttype      -- n  = extracts only numbers 
                     c  = extracts only alphabetic characters 
                     nc = extracts both alphanumeric characters 
@additionalchars  -- additional special characters to be extracted along with the above. 
________________________________________________________________________________________________________________
*/

CREATE proc [dbo].[sp_Scrub] (
	@tablename varchar(500),
	@columns varchar(500),
	@extracttype varchar(10),
	@additionalchars nvarchar(50) = null
)
as

set nocount on
declare @db varchar(25)=Null,
        @sql nvarchar(max)
;

if @tablename like'#%' 
begin
	set @db='TempDB.'
end;

set @sql='
	declare @pat varchar(25),
			@sql nvarchar(max),
			@i int =1,
			@col varchar(50),
			@columns varchar(500),
			@extracttype varchar(10),
			@additionalchars nvarchar(50)
			;
	set @additionalchars='+@additionalchars+'
	set @extracttype='+@extracttype+'
	set @columns=replace(replace(replace(replace(ltrim(rtrim('+@columns+')),'' '',''''),''['',''''),'']'',''''),char(9),'''');

	if @extracttype = ''n'' 
		begin
			set @pat=''^0-9''
		end;
	if @extracttype = ''c''
		begin
			set @pat=''^a-z''
		end;
	if @extracttype = ''nc''
		begin
			set @pat=''^a-z^0-9''
		end;

	declare @splitcols table (col varchar(500))
	insert into @splitcols values(@columns);
	if object_id(''tempdb..#columns'') is not null drop table #columns;

	with num1 (n) as (
	select 1 as n
	union all 
	select n+1 as n
	from num1 
	where n<101)
	,num2 (n) as (select 1 from num1 as x, num1 as y)
	,nums (n) as (select row_number() over(order by n) from num2)
 
	select substring([col], n, charindex('','', [col] + '','', n) - n)  col
	into #columns
	from @splitcols    
	cross apply nums
	where n <= len([col]) and substring('','' + [col], n, 1) = '',''
	;

	if object_id(''tempdb..##tablecols'') is not null drop table ##tablecols
	select identity(int,1,1) rid, column_name col
	into #tablecols
	from '+Isnull(@db,'')+'information_schema.columns
	where table_name = parsename('+@tablename+',1)
	and column_name in (select col from #columns);

	print ''Processed column count:''+cast(@@rowcount as varchar(10));

	while @i<=(select max(rid) from #tablecols)
		begin
			set @col=(select quotename(col) from #tablecols where rid=@i);
			set @sql=''
			declare @rowcount int
			while 1 = 1 
			begin
				update '+@tablename+'
				set ''+@col+'' = replace(''+@col+'', substring(''+@col+'', patindex(''''%[''+@pat+isnull(@additionalchars,'''')+'']%'''', ''+@col+''), 1), '''''''')
				where ''+@col+'' like ''''%[''+@pat+isnull(@additionalchars,'''')+'']%''''
				if @@rowcount = 0 break;
			end;
			''
			--print @sql
			exec sp_executesql @sql;
		
			set @i=@i+1
		end;
'

GO

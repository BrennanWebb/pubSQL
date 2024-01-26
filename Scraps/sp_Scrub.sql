
use [master]
go
/*
________________________________________________________________________________________________________________
Purpose: Scrub table columns keeping only the designated @extracttype.  
Multiple column names may be specified as long as they are comma separated.  See example below.

Example Usage Script (highlight the lines below and execute once sproc is installed):

	Begin
		drop table if exists #trash_data;
		go
		Create table #trash_data (Col1 varchar(250),Col2 varchar(250))
		Insert into #trash_data (Col1, Col2)
		Values ('{Tg3<E_5=Wum+8g7','0X[0I@;_3o":Oan'),
			   ('YMVVb7MXnaWYTkE5mW4V6x55bA6RvpqPsJDZNfhB76Ee9tW8JkB5Y6z3wfKz','{,{_}!@~"+([@+#:,/#&[+(]##@-,$)\~#@!\?"#{\\_<!@>&,}-%!/^-'),
			   ('#>%=#$@?=[.:)=}};/.}_^"##.[{;)}\`#*|&}=\?~|=&`#>*".##:%:&!','What @ mess!*10			?
			   ')

		Exec sp_scrub '#trash_data','Col1,Col2','C',' ?'; 
		Select * from #trash_data;
	End

Parameter Definitions
---------- 
@tablename		  -- server table object, full 3 part naming convention is allowed.
@columns		  -- multiple columns may be supplied and must be comma separated.
@inputstring      -- string from which the values to be extracted 
@extracttype      -- n  = extracts only numbers 
                     c  = extracts only alphabetic characters 
                     nc = extracts both alphanumeric characters 
@additionalchars  -- additional special characters to be extracted along with the above. 
________________________________________________________________________________________________________________
*/

create proc [dbo].[sp_Scrub] (
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
	set @additionalchars='''+isnull(@additionalchars,'')+'''
	set @extracttype='''+@extracttype+'''
	set @columns=replace(replace(replace(replace(ltrim(rtrim('''+@columns+''')),'' '',''''),''['',''''),'']'',''''),char(9),'''');

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

	if object_id(''tempdb..#tablecols'') is not null drop table #tablecols;
	select identity(int,1,1) rid, column_name col
	into #tablecols
	from '+Isnull(@db,'')+'information_schema.columns
	where table_name like ''%''+parsename('''+@tablename+''',1)+''%''
	and column_name in (select col from #columns);

	print ''Processed column count:''+cast(@@rowcount as varchar(10));

	while @i<=(select max(rid) from #tablecols)
		begin
			print @i
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
print @sql
exec sp_executesql @sql;

GO



USE [AdHocData]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_Scrub]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE proc [PSLAO].[sp_Scrub] (
	@tablename varchar(500),
	@columns varchar(500),
	@extracttype varchar(10),
	@additionalchars nvarchar(50) = null
)
as
/* 
parameters 
---------- 
@inputstring      -- string from which the values to be extracted 
@extracttype      -- n  = extracts only numbers 
                     c  = extracts only alphabetic characters 
                     nc = extracts both alphanumeric characters 
@additionalchars  -- additional special characters to be extracted along with the above. 
*/

set nocount on

declare @pat varchar(25),
		@sql nvarchar(max),
		@i int =1,
		@col varchar(50)
		;

set @columns=replace(replace(replace(replace(ltrim(rtrim(@columns)),' ',''),'[',''),']',''),char(9),'');
--If len(@additionalchars)>0
--	Begin
--		set @additionalchars='^'+@additionalchars;
--	End;

if @extracttype = 'n' 
	begin
		set @pat='^0-9'
	end;
if @extracttype = 'c'
	begin
		set @pat='^a-z'
	end;
if @extracttype = 'nc'
	begin
		set @pat='^a-z^0-9'
	end;

declare @splitcols table (col varchar(500))
insert into @splitcols values(@columns);
exec adhocdata.pslao.sp_drop_object '#columns';

with num1 (n) as (
select 1 as n
union all 
select n+1 as n
from num1 
where n<101)
,num2 (n) as (select 1 from num1 as x, num1 as y)
,nums (n) as (select row_number() over(order by n) from num2)
 
select substring([col], n, charindex(',', [col] + ',', n) - n)  col
into #columns
from @splitcols    
cross apply nums
where n <= len([col]) and substring(',' + [col], n, 1) = ','
;

exec adhocdata.pslao.sp_drop_object '#tablecols';
select identity(int,1,1) rid, column_name col
into #tablecols
from adhocdata.information_schema.columns
where table_name = parsename(@tablename,1)
and column_name in (select col from #columns);

exec adhocdata.pslao.sp_message 'Processed column count:',@@rowcount;

while @i<=(select max(rid) from #tablecols)
	begin
		set @col=(select quotename(col) from #tablecols where rid=@i);
		set @sql='
		declare @rowcount int
		while 1 = 1 
		begin
			update '+@tablename+'
			set '+@col+' = replace('+@col+', substring('+@col+', patindex(''%['+@pat+isnull(@additionalchars,'')+']%'', '+@col+'), 1), '''')
			where '+@col+' like ''%['+@pat+isnull(@additionalchars,'')+']%''
			if @@rowcount = 0 break;
		end;
		'
		--print @sql
		exec sp_executesql @sql;
		
		set @i=@i+1
	end;

GO

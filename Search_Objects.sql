Declare @search_term varchar(500) = 'PolicyMart_Reload',
		@i int =1,
		@sql nvarchar(max),
		@db varchar(50);

Drop table if exists #loop;
Select name, identity(int, 1,1) ID
Into #loop
From [Master].Sys.databases
Where name NOT IN('model','tempdb');

Drop table if exists #T1;
Create table #T1 ([name] varchar(500), [Type] varchar(50));

While @i<=(Select max(id) from #loop)
Begin
	Set @db = (Select [name] from #loop where id=@i)
	Set @SQL = 'Select '''+quotename(@db)+'''''.''+quotename(s.[Name])+''.''+quotename(o.[Name]), o.[Type_Desc] 
				From '+quotename(@db)+'.[sys].[Objects] o
				inner join '+quotename(@db)+'.sys.schemas s on o.schema_id=s.schema_id
				Where o.name like ''%'+@search_term+'%'';'
				Print @sql
	--Insert into #T1 ([name],[Type])
	Exec (@sql); 
	set @i=@i+1;
End;

Select Distinct *
From #T1;


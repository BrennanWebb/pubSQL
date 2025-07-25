USE [master]
GO

/************************************************************************************************************************
 Author:		Brennan Webb
 Create date:	2022-10-31
 Jira Ticket:	NA
 Description:	Allows a user to supply a table name to return metadata on the table in different concatenated forms. See help section below.
 SLA:			Server Level
 Caller:		Adhoc Users / Devs
 Audience:		Adhoc Users / Devs
 Change Log
--------------------------------------------------------------------------------------------------------------------------
| Date       |	 Developer           | Change Summarized                                                  |
--------------------------------------------------------------------------------------------------------
| 2023-07-03 |	 Brennan Webb        | Added ability to survey target                                     |
| 2023-09-18 |	 Brennan Webb        | Added default constraint to output                                 |
| 2023-10-31 |	 Brennan Webb        | Added check for object_id resolution                               |
| 2024-01-26 |	 Brennan Webb        | Fix for missed column name			                              |
| 2024-01-31 |	 Brennan Webb        | Fix for Object_ID() check accidentally left from testing		      |
| 2024-02-08 |	 Brennan Webb        | Added additional ability to compare two tables in column naming    |
| 2024-03-25 |	 Brennan Webb        | Fix for sorting	on both horizontal and vertical				      |
| 2024-04-18 |	 Brennan Webb        | Added mismatch flag to column comparison tool				      |
| 2024-07-22 |	 Brennan Webb        | Integrated sp_agger as temp sproc rather than stand alone	      |
| 2025-07-16 |	 Brennan Webb        | Fixed survey last row output									      |
--------------------------------------------------------------------------------------------------------------------------
**************************************************************************************************************************/

CREATE or ALTER proc [dbo].[sp_Columnizer] (@object varchar(1000)=null, @agg varchar(25)=null, @isnull varchar(50) = null, @sort bit = 0, @survey int = 0)
as

Set NoCount On;

Declare	 @sql				nvarchar(max)
		,@db				varchar(150)
		,@Nid				varchar(8)		= Cast(left(NewID(),8) as varchar(8))
		,@Columns			varchar(max)
		,@Columns2			varchar(max)
		,@L1				int				= 1
		;

If @object is null 
	Begin
		GOTO help;
	End


-------------------------------------------------------------------------------------------------------
--Universal Operations
-------------------------------------------------------------------------------------------------------
--create temp proc to handle aggregations.
If object_ID('tempdb..##sp_Agger')is null
Begin
	Set @sql = '
		CREATE proc ##sp_Agger (@agg varchar(25)=null,@columns varchar(max)=null,@isnull varchar(50) = null)
		as

		Set NoCount On;
		If @columns is null or @agg is null goto help;

		declare @leading_comma char  =''''
				,@xmlstring xml
				,@i int               =1 
				,@sql varchar(max)    =''''
				,@sql1 varchar(max)   =''''
				,@f varchar(500)
				,@fs_out varchar(max) =''''
				--,@agg varchar(25)   =''count''
				--,@columns varchar(5000) ='',[c0d],[c1],[c1d]''      
		  
		if left(@columns,1)in ('','') --check if leading comma exists
			begin
				set @columns=stuff(@columns, 1, 1, ''''); --remove leading comma
				set @leading_comma='','' --set leading comma variable.  will be used at the end if it was removed at the start.
			end;
		drop table if exists ##agger;
		select convert(xml,''<fs><f>''+replace(@columns,'','',''</f><f>'') + ''</f></fs>'')xmlstring--convert to xml string
		into ##agger;

		while @i<=(select xmlstring.value(''count(/fs/*)'', ''int'') from ##agger) --count subnodes and begin looping
			begin
				drop table if exists ##fholder;
				set @sql=''create table ##fholder([''+@agg+''] varchar(max));
				insert into ##fholder
				select rtrim(ltrim(xmlstring.value(''''/fs[1]/f[''+cast(@i as nvarchar(3))+'']'''',''''varchar(100)'''')))
				from ##agger ''
				--print @sql
				exec (@sql);
				set @sql='''';
				-----------------
				set @f=(select * from ##fholder);
				set @sql1=@sql1+''select ''''''+(case when @i=1 then @leading_comma else '','' end)
							  +@agg+''(''+(case when @isnull is not null then ''isnull('' else'''' end)
							  +@f+(case when @isnull is not null then '',''+@isnull+'')'' else'''' end) --still need to account for varchar possibilities
							  +'') ''+@f+'''''' as[''+@agg+'']''+
							  ''from ##agger''
							  +char(13)+'' union all ''+char(13); 
			set @i=@i+1;
			end;
		set @sql1=ltrim(stuff(@sql1,len(@sql1)-len('' union all ''+char(13)),len('' union all ''+char(13)),''''));
		--print @sql1;
		exec(@sql1);

		Return;

		help:

		print ''
		sp_Agger needs at least two parameter inputs:
			1. Aggregation method.
			2. List of columns.

			--example usage of sp_Agger
			exec sp_agger ''''count'''', --this is the aggregation method which will be applied to all columns.
						  '''',[ProviderKey]
						  ,[LastName]
						  ,[FirstName]
						  ,[MiddleName]
						  ,[Suffix]
						  ,[Title]
						  '''' --this is the list of columns.
		''
	';
	--Print @sql;
	Exec(@sql);
End;


--Table objects and assign a NewID for global temp table purposes.
Begin
	Drop table if exists #Object_List;
	Select identity(int, 1,1) ID
	 ,Trim([value]) as [Object]
	 ,isnull(parsename(Trim([value]),3),DB_NAME()) DB
	 ,Cast(left(NewID(),8) as varchar(8)) NID
	Into #Object_List
	From string_split(@Object, ',');
End;

While @L1<=(Select max(ID) From #Object_List)
Begin
	Set @nid =(Select NID From #Object_List Where ID = @L1)
	Set @object =(Select [Object] From #Object_List Where ID = @L1)
	Set @db =(Select [DB] From #Object_List Where ID = @L1)
	--Horizontal Column outputs
	Set @sql='
		Use '+Quotename(@db)+';
		Declare @db varchar(150) = '''+@db+''', @object varchar(500) = '''+@object+''';
		Begin
			DROP TABLE IF EXISTS ##H'+@Nid+';
			SELECT  1 as RID,
					Columns_Horizontal = String_Agg(QUOTENAME(C.NAME),'','') '+iif(@sort=1,'WITHIN GROUP (Order by C.NAME asc)','')+',
					Columns_Horizontal_Detail = String_Agg(QUOTENAME(C.NAME) +'' ''+ 
						Case	when C.MAX_LENGTH = -1 then Upper(T.NAME) +''(MAX)''
								when C.MAX_LENGTH is not null and T.NAME like ''%char'' then Upper(T.NAME) +''(''+cast(Coalesce(IC.CHARACTER_MAXIMUM_LENGTH, C.MAX_LENGTH) as varchar(20))+'')''
							Else  Upper(T.NAME)
						End + iif(c.is_identity=1,'' IDENTITY(''+Cast(IDENT_SEED('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'',''+Cast(IDENT_INCR('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'')'','''')
							+ iif(pkc.object_id is not null,'' CONSTRAINT '' +QuoteName(PK.NAME)+'' PRIMARY KEY'','''')
							+ iif(c.is_nullable=1,'' NULL'','' NOT NULL'')
							+ iif(DC.Definition is not Null,'' DEFAULT''+DC.Definition,'''')
							+ iif(fkc.referenced_column_id is not null, '' FOREIGN KEY REFERENCES ''+QuoteName(Object_Schema_Name(FK_Object.Object_ID))+''.''+QuoteName(FK_Object.Name)+'' (''+FK_Column.Name+'')'','''')
							+ iif(c.is_computed=1,''--computed'','''')
							+ iif(c.is_hidden=1,''--hidden'','''')
							,'','') '+iif(@sort=1,'WITHIN GROUP (Order by C.NAME asc)','')+'
			INTO ##H'+@Nid+'
			FROM '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_COLUMNS C With(Nolock) 
			INNER JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.TYPES T With(Nolock) on C.system_Type_ID=T.User_Type_ID
			INNER JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_OBJECTS O on C.object_id=O.object_id
			INNER JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.SCHEMAS S on O.schema_id=s.schema_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.INDEXES PK on C.object_id = pk.object_id and pk.is_primary_key = 1
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.INDEX_COLUMNS pkc on pkc.object_id = pk.object_id and pkc.index_id = pk.index_id and c.column_id = pkc.column_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.INFORMATION_SCHEMA.COLUMNS IC on IC.Table_Name = O.Name and IC.Table_Schema = S.Name and C.Name = IC.Column_Name
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.FOREIGN_KEY_COLUMNS fkc With(Nolock) ON o.object_id = fkc.parent_object_id and c.column_id = fkc.parent_column_id 
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_OBJECTS FK_Object With(Nolock) ON fkc.referenced_object_id = FK_Object.object_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_COLUMNS FK_Column With(Nolock) ON FK_Object.object_id = FK_Column.object_id AND fkc.referenced_column_id = FK_Column.column_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.DEFAULT_Constraints DC With(NoLock) ON C.Object_ID = DC.Parent_Object_ID AND C.Column_ID = DC.Parent_Column_ID
			Where c.[Object_ID] = object_id('+iif(@object like '#%','''tempdb..''+','')+'@object)
			;
			
			Select @Column_List  = Columns_Horizontal
				  ,@Column_List2 = Columns_Horizontal_Detail
			From ##H'+@NID+';
		End;
		'
	--Print @SQL
	--Print len(@SQL)
	print 'sp_columnizer output for '+ @Object;
	Exec sp_executesql @sql,N'@Column_List varchar(max) Output,@Column_List2 varchar(max) Output', @Columns Output,@Columns2 Output;
	
	--------------- Vertical column outputs
	Set @sql='
	Use '+Quotename(@db)+';
	Declare @db varchar(150) = '''+@db+''', @object varchar(500) = '''+@object+''';
	Begin
		DROP TABLE IF EXISTS ##V'+@Nid+';
		SELECT	C.COLUMN_ID RID,
				Case when C.COLUMN_ID =1 then '''' else '','' end+'' ''+QUOTENAME(C.NAME) Columns_Vertical,
				Case when C.COLUMN_ID =1 then '''' else '','' end+'' ''+QUOTENAME(C.NAME) +'' ''+ 
				Case	when C.MAX_LENGTH = -1 then Upper(T.NAME) +''(MAX)''
						when C.MAX_LENGTH is not null and T.NAME like ''%char'' then Upper(T.NAME) +''(''+cast(Coalesce(IC.CHARACTER_MAXIMUM_LENGTH, C.MAX_LENGTH) as varchar(20))+'')''
						Else  Upper(T.NAME)
				End		+ iif(c.is_identity=1,'' IDENTITY(''+Cast(IDENT_SEED('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'',''+Cast(IDENT_INCR('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'')'','''')
							+ iif(pkc.object_id is not null,'' CONSTRAINT '' +QuoteName(PK.NAME)+'' PRIMARY KEY'','''')
							+ iif(c.is_nullable=1,'' NULL'','' NOT NULL'')
							+ iif(DC.Definition is not Null,'' DEFAULT''+DC.Definition,'''')
							+ iif(fkc.referenced_column_id is not null, '' FOREIGN KEY REFERENCES ''+QuoteName(Object_Schema_Name(FK_Object.Object_ID))+''.''+QuoteName(FK_Object.Name)+'' (''+FK_Column.Name+'')'','''')
							+ iif(c.is_computed=1,''--computed'','''')
							+ iif(c.is_hidden=1,''--hidden'','''')
				Columns_Vertical_Detail

				'+iif(@survey>=1,'
				,T.NAME as Data_Type
				,Cast(Null as VARCHAR(MAX)) as Distinct_Top10
				'+iif(@survey>=2,',Cast(Null as INT) as Distinct_Count',''),'')+'
			INTO ##V'+@Nid+'
		    FROM '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_COLUMNS C With(Nolock) 
			INNER JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.TYPES T With(Nolock) on C.system_Type_ID=T.User_Type_ID
			INNER JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_OBJECTS O on C.object_id=O.object_id
			INNER JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.SCHEMAS S on O.schema_id=s.schema_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.INDEXES PK on C.object_id = pk.object_id and pk.is_primary_key = 1
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.INDEX_COLUMNS pkc on pkc.object_id = pk.object_id and pkc.index_id = pk.index_id and c.column_id = pkc.column_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.INFORMATION_SCHEMA.COLUMNS IC on IC.Table_Name = O.Name and IC.Table_Schema = S.Name and C.Name = IC.Column_Name
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.FOREIGN_KEY_COLUMNS fkc With(Nolock) ON o.object_id = fkc.parent_object_id and c.column_id = fkc.parent_column_id 
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_OBJECTS FK_Object With(Nolock) ON fkc.referenced_object_id = FK_Object.object_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.ALL_COLUMNS FK_Column With(Nolock) ON FK_Object.object_id = FK_Column.object_id AND fkc.referenced_column_id = FK_Column.column_id
			LEFT JOIN '+iif(@object like '#%','TEMPDB',quotename(@db))+'.SYS.DEFAULT_Constraints DC With(NoLock) ON C.Object_ID = DC.Parent_Object_ID AND C.Column_ID = DC.Parent_Column_ID
			Where c.[Object_ID] = object_id('+iif(@object like '#%','''tempdb..''+','')+'@object);
			End;
			
			Select A.RID
			,A.Columns_Vertical
			,A.Columns_Vertical_Detail	
			,B.Columns_Horizontal
			,B.Columns_Horizontal_Detail
			From ##V'+@NID+' A
			Full Outer Join ##H'+@NID+' B ON A.RID=B.RID
			'+iif(@sort=1,'Order by Columns_Vertical asc','ORDER BY 1')+'
			;
			'
	--Print @SQL
	--Print len(@SQL)
	Exec sp_executesql @sql;

	--If survey is requested, we are going to survey the table for each column: distinct top 10 and total count (which will help show used cells, aka not nulls)
	If @survey>=1
	Begin
		Begin
			Set @Sql =' 
			Declare @i int = 1, @Col varchar(250), @sql nvarchar(max);
			While @i<=(Select Max(RID) From ##V'+@Nid+')
				Begin
					Set @Col = (Select Columns_Vertical from ##V'+@Nid+' Where RID= @i);
					If @Col is not null
					Begin
						Set @sql = ''
						Update ##V'+@Nid+'
						Set  Distinct_Top10 = iif( (Data_Type not like ''''%time%'''' 
													AND Data_Type not like ''''%Date%'''' 
													AND Data_Type not like ''''%Bit%'''' 
													AND Data_Type not like ''''%uniqueidentifier%''''
													) --ignore these data types, since they are very predictable.
													OR (Columns_Vertical_Detail Like ''''%KEY%'''') --always sample columns if they are key fields
												,(Select string_agg(Cast(N as varchar(Max)),'''', '''') From (Select Distinct top 10 ''+Trim(Replace(@Col,'','',''''))+'' as N From '+@Object+' With (NoLock) )A)
												,''''No Survey'''')
							'+iif(@survey>=2,', Distinct_Count = (Select Count(Distinct ''+Trim(Replace(@Col,'','',''''))+'') From '+@Object+' With (NoLock))','')+'
						Where Columns_Vertical = ''''''+@Col+''''''
						''
						Exec sp_executesql @sql;
					End;
					Set @i=@i+1;
				End;
			'
			--Print @sql
			Exec sp_executesql @sql;
		End;
		Begin
			Set @SQL='Select * From ##V'+@Nid+''+iif(@sort=1,' ORDER BY Columns_Vertical ASC',' ORDER BY RID')+';';
			--Print @SQL
			Exec sp_executesql @sql;
		End;
	End;
	Set @L1 = @L1+1;
End;

If (Select count(*) From #Object_List)=2
Begin
	Set @SQL= (Select 
		'SELECT '+ STRING_AGG('V'+Cast(ID as varchar(1))+'.Columns_Vertical_Detail as '+Quotename([object],'"'),Char(10)+',')+ Char(10)
		 +',IIF('+String_AGG('Trim(Right(V'+Cast(ID as varchar(1))+'.Columns_Vertical_Detail,LEN(V'+Cast(ID as varchar(1))+'.Columns_Vertical_Detail)-CHARINDEX('']'', V'+Cast(ID as varchar(1))+'.Columns_Vertical_Detail)))',Char(10)+'<>')+	',1,0) MetadataMismatch'+ Char(10)
	     +'FROM ' + STRING_AGG('##V'+NID+' as V'+Cast(ID as varchar(1)), ' Full Outer Join ') + Char(10)
	     +'ON ' + STRING_AGG('Replace(V'+Cast(ID as varchar(1))+'.Columns_Vertical,'','','''')',' = ') +';'
		From #Object_List);
		--Print @SQL
		Exec sp_executesql @sql;
End;

If @Columns is null
	Begin
		Print'Looks like the output is null.'+Char(10)+
		'Check to ensure all desired variables are supplied.'+Char(10)+ 
		'If you are trying to query an object in a different database than your current session, please add the database to the object parameter.'+Char(10)+ 
		'For more help and examples, execute the following:'+Char(10)+ 
	    ''+Char(10)+ 
		'Exec sp_columnizer;
		'
	End;

--If aggregation is needed, @Columns must be populated.
If @agg is not null
Begin
	Exec ##sp_Agger @agg=@agg, @columns=@columns, @isnull=@isnull;
End;


return;
help:
Declare @print varchar(max) ='
sp_Columnizer allows a user to supply a table name to return metadata on the table in different concatenated forms.
Use at least a 2 part naming convention for object references.
1. Will output column headers in a single line comma separated string + dataType with lengths in horizontal position.
2. Will output column headers in Vertical position + dataType with lengths in Vertical position.
3. Can  output column headers with aggregations already scripted.
4. Can  output a table survey.  See notes below for explaination of options.
5. Can perform comparisons of tables if two tables are provided via comma separations.  Works even for temp tables.
--------------------------------------------------------------------------------------------
				
Example Usage Script (just highlight the lines below and execute):

	Exec sp_Columnizer @object=''msdb.dbo.restorehistory'';
--------------------------------------------------------------------------------------------
				
This also works with tempdb.  No need to switch databases.

	Drop table if exists #'+@Nid+';
	Create table #'+@Nid+'(id int, Name varchar(20), Address varchar(50), DOB Date);
	Exec sp_Columnizer ''#'+@Nid+'''
--------------------------------------------------------------------------------------------
				
@agg=1 can also be used with other tools in the DB such as ##sp_agger.  Example below.

	Declare @Columns Varchar(max);
	Exec sp_Columnizer @object=''sys.columns'',@agg=''sum'',@isnull=''0''; --change @isnull= whatever value you want in an isnull() wrapper, second position.
--------------------------------------------------------------------------------------------

sp_Columnizer can also be used to survey a target table.  
	Options are as follows: 
		1 = Top ten distinct sampling of the column. 
		2 = Distinct count of all records in the column.

	Exec sp_Columnizer @object=''sys.columns'',@survey=1;
	Exec sp_Columnizer @object=''sys.columns'',@survey=2;
--------------------------------------------------------------------------------------------
Comparing two tables

	Exec sp_Columnizer @object=''sys.columns, sys.tables'';
--------------------------------------------------------------------------------------------
'
Print @print 
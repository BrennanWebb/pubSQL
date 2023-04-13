USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
| Date       | Ticket ID		| Developer           | Change Summarized                                                  |
--------------------------------------------------------------------------------------------------------------------------
| XX/XX/XXXX |					|                     |                                                                    |
--------------------------------------------------------------------------------------------------------------------------
**************************************************************************************************************************/

ALTER proc [dbo].[sp_Columnizer] (@object varchar(500)=null, @agg varchar(25)=null, @isnull varchar(50) = null, @sort bit =0)
as

Set NoCount On;

Declare	@sql nvarchar(max)
		,@db  varchar(150)= isnull(parsename(@object,3),DB_NAME())
		,@Nid varchar(8) = Cast(left(NewID(),8) as varchar(8))
		,@Columns varchar(max)
		,@Columns2 varchar(max)
		,@Columns3 varchar(max)
		,@Columns4 varchar(max)
		;

If @object is null goto help;

Begin
	--Horizontal Column outputs
	Set @sql='
		Use '+Quotename(@db)+';
		Declare @db varchar(150) = '''+@db+''', @object varchar(500) = '''+@object+''';
		Begin
			SELECT  @Column_List = COALESCE(@Column_List + '', '','''') + QUOTENAME(C.NAME),
					@Column_List2 = COALESCE(@Column_List2 + '', '','''') + 
						QUOTENAME(C.NAME) +'' ''+ 
						Case	when C.MAX_LENGTH = -1 then T.NAME +''(MAX)''
								when C.MAX_LENGTH is not null and T.NAME like ''%char'' then T.NAME +''(''+cast(Coalesce(IC.CHARACTER_MAXIMUM_LENGTH, C.MAX_LENGTH) as varchar(20))+'')''
							Else  T.NAME
						End + iif(c.is_identity=1,'' IDENTITY(''+Cast(IDENT_SEED('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'',''+Cast(IDENT_INCR('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'')'','''')
							+ iif(pkc.object_id is not null,'' PRIMARY KEY'','''')
							+ iif(c.is_nullable=1,'' NULL'','' NOT NULL'')
							+ iif(fkc.referenced_column_id is not null, '' FOREIGN KEY REFERENCES ''+QuoteName(Object_Schema_Name(FK_Object.Object_ID))+''.''+QuoteName(FK_Object.Name)+'' (''+FK_Column.Name+'')'','''')
							+ iif(c.is_computed=1,''--computed'','''')
							+ iif(c.is_hidden=1,''--hidden'','''')
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
			Where c.[Object_ID] = object_id('+iif(@object like '#%','''tempdb..''+','')+'@object)
			ORDER BY C.COLUMN_ID;
			Select @Column_List as Columns_Horizontal_String, @Column_List2 as Columns_Horizontal_wType;
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
		SELECT Case when C.COLUMN_ID =1 then '''' else '','' end+'' ''+QUOTENAME(C.NAME) Columns_Vertical,
					Case when C.COLUMN_ID =1 then '''' else '','' end+'' ''+QUOTENAME(C.NAME) +'' ''+ 
					Case	when C.MAX_LENGTH = -1 then T.NAME +''(MAX)''
							when C.MAX_LENGTH is not null and T.NAME like ''%char'' then T.NAME +''(''+cast(Coalesce(IC.CHARACTER_MAXIMUM_LENGTH, C.MAX_LENGTH) as varchar(20))+'')''
							Else  T.NAME
					End		+ iif(c.is_identity=1,'' IDENTITY(''+Cast(IDENT_SEED('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'',''+Cast(IDENT_INCR('+iif(@object like '#%','''tempdb..''+','')+'@object) as varchar(50))+'')'','''')
							+ iif(pkc.object_id is not null,'' PRIMARY KEY'','''')
							+ iif(c.is_nullable=1,'' NULL'','' NOT NULL'')
							+ iif(fkc.referenced_column_id is not null, '' FOREIGN KEY REFERENCES ''+QuoteName(Object_Schema_Name(FK_Object.Object_ID))+''.''+QuoteName(FK_Object.Name)+'' (''+FK_Column.Name+'')'','''')
							+ iif(c.is_computed=1,''--computed'','''')
							+ iif(c.is_hidden=1,''--hidden'','''')
					Columns_Vertical_wType
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
			Where c.[Object_ID] = object_id('+iif(@object like '#%','''tempdb..''+','')+'@object)
			'+iif(@sort=1,'Order by 1 asc','ORDER BY C.COLUMN_ID')+';
			End
			'
	--Print @SQL
	--Print len(@SQL)
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
	Exec sp_Agger @agg=@agg, @columns=@columns, @isnull=@isnull;
End;


return;
help:
print '
sp_Columnizer allows a user to supply a table name to return metadata on the table in different concatenated forms.
Use at least a 2 part naming convention for object references.
1. Will output column headers in a single line comma separated string + dataType with lengths in horizontal position.
2. Will output column headers in Vertical position + dataType with lengths in Vertical position.
--------------------------------------------------------------------------------------------
				
--Example Usage Script (just highlight the lines below and execute):	
	Exec sp_Columnizer @object=''msdb.dbo.restorehistory'';
--------------------------------------------------------------------------------------------
				
--This also works with tempdb.  No need to switch databases.
	Drop table if exists #'+@Nid+';
	Create table #'+@Nid+'(id int, Name varchar(20), Address varchar(50), DOB Date);
	Exec sp_Columnizer ''#'+@Nid+'''
--------------------------------------------------------------------------------------------
				
--@agg=1 can also be used with other tools in the DB such as sp_agger.  Example below.
	Declare @Columns Varchar(max);
	Exec sp_Columnizer @object=''#test_columnizer'',@agg=''sum'',@isnull=''0''; --change @isnull= whatever value you want in an isnull() wrapper, second position.
--------------------------------------------------------------------------------------------
'


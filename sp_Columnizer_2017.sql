USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_Columnizer]    Script Date: 12/1/2022 10:54:21 AM ******/
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

ALTER proc [dbo].[sp_Columnizer] (@object varchar(500)=null, @action varchar(25)=null, @isnull varchar(50) = null)
as

Set NoCount On;

If @object is null goto help;
Declare	@sql nvarchar(max)
		,@db  varchar(150)= isnull(parsename(@object,3),DB_NAME())
		,@Columns varchar(max)
		,@Columns2 varchar(max)
		;
If @Action in (1,2)
Begin
	Set @sql='
		Use '+Quotename(@db)+';
		Declare @db varchar(150) = '''+@db+''', @object varchar(500) = '''+@object+''' , @action int = '''+@action+''';

		If @action = 1 goto one; 
		If @action = 2 goto two; 
		return;
		one:
		Begin
			If @object like ''#%'' 
			Begin
				SELECT @Column_List = COALESCE(@Column_List + '', '','''') + QUOTENAME(COLUMN_NAME),
					@Column_List2 = COALESCE(@Column_List2 + '', '','''') + 
					QUOTENAME(COLUMN_NAME) +'' ''+ 
					Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
						when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +''(MAX)''
						when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +''(''+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+'')''
						End
				FROM TEMPDB.INFORMATION_SCHEMA.COLUMNS C With(Nolock) 
				Where TABLE_NAME like parsename(@object,1)+''\_%'' ESCAPE ''\''
				ORDER BY ORDINAL_POSITION;
				Select @Column_List as Columns_Horizontal_String, @Column_List2 as Columns_Horizontal_wType;
				Return;
			End
			Else
			SELECT @Column_List = COALESCE(@Column_List + '', '','''') + QUOTENAME(COLUMN_NAME),
					@Column_List2 = COALESCE(@Column_List2 + '', '','''') + 
					QUOTENAME(COLUMN_NAME) +'' ''+ 
					Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
						when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +''(MAX)''
						when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +''(''+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+'')''
						End
			FROM INFORMATION_SCHEMA.COLUMNS C  With(Nolock)
			Where TABLE_CATALOG = @db
			and TABLE_SCHEMA = parsename(@object,2)
			and TABLE_NAME = parsename(@object,1)
			ORDER BY ORDINAL_POSITION;
			Select @Column_List as Columns_Horizontal_String, @Column_List2 as Columns_Horizontal_wType;
			Return;
		End;
		two:
		Begin
			If @object like ''#%'' 
			Begin
				SELECT Case when ORDINAL_POSITION=1 then '''' else '','' end+
				'' ''+QUOTENAME(COLUMN_NAME) Column_Verticle,
				Case when ORDINAL_POSITION=1 then '''' else '','' end+
				'' ''+QUOTENAME(COLUMN_NAME) +
				'' ''+ Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
				when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +''(MAX)''
				when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +''(''+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+'')''
				End Column_Verticle_wType
				FROM Tempdb.INFORMATION_SCHEMA.COLUMNS C With(Nolock)
				Where TABLE_NAME like parsename(@object,1)+''\_%'' ESCAPE ''\''
				ORDER BY ORDINAL_POSITION;
				Return;
			End
			Else
			SELECT Case when ORDINAL_POSITION=1 then '''' else '','' end+
			'' ''+QUOTENAME(COLUMN_NAME) Columns_Verticle,
			Case when ORDINAL_POSITION=1 then '''' else '','' end+
				'' ''+QUOTENAME(COLUMN_NAME) +
				'' ''+ Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
				when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +''(MAX)''
				when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +''(''+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+'')''
				End Columns_Verticle_wType
			FROM INFORMATION_SCHEMA.COLUMNS C  With(Nolock)
			Where TABLE_CATALOG = @db
			and TABLE_SCHEMA = parsename(@object,2)
			and TABLE_NAME = parsename(@object,1)
			ORDER BY ORDINAL_POSITION;
			Return;
		End;
		'
	Exec sp_executesql @sql,N'@Column_List varchar(max) Output,@Column_List2 varchar(max) Output', @Columns Output,@Columns2 Output;
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

--If aggregation is needed, it must be a version 1.
If @action not in (1,2)
Begin
	Exec sp_Agger @agg=@action, @columns=@columns, @isnull=@isnull;
End;


return;
help:
print '
Allows a user to supply a table name to return metadata on the table in different concatenated forms.
Use at least a 2 part naming convention for object references.

--@action=1 will output column headers in a single line comma separated string + dataType with lengths in horizontal position.
--@action=2 will output column headers in vertical position + dataType with lengths in vertical position.
--------------------------------------------------------------------------------------------
				
--Example Usage Script (just highlight the lines below and execute):	
	Exec sp_Columnizer @action=1,@object=''msdb.dbo.restorehistory'';
	Exec sp_Columnizer @action=2,@object=''msdb.dbo.restorehistory'';

--------------------------------------------------------------------------------------------
				
--This also works with tempdb.  No need to switch databases like master.sys.sp_columns
	Drop table if exists #test_columnizer;
	Create table #test_columnizer(id int, Name varchar(20), Address varchar(50), DOB Date);
	Exec sp_Columnizer ''#test_columnizer'', 1;
	Exec sp_Columnizer ''#test_columnizer'', 2;

--------------------------------------------------------------------------------------------
				
--@action=1 can also be used with other tools in the DB such as sp_agger.  Example below.
	Declare @Columns Varchar(max);
	Exec sp_Columnizer @action=1,@object=''#test_columnizer'',@action=''sum'',@isnull=''0''; --change @isnull= whatever value you want in an isnull() wrapper, second position.
--------------------------------------------------------------------------------------------
'

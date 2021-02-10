USE [AdHocData]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_Columnizer]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
Date Written: 12/18/2020
Called From:  For Adhoc Use

Purpose: Allows a user to supply a table name to return metadata on the table in different concatenated forms.  Use at least a 3 part naming convention for object references.
Example Usage Script (just highlight the lines below and execute):

	Exec AdHocData.pslao.sp_Columnizer @version=1,@object='AdhocData.pslao.DPM_CASMap';
	Exec AdHocData.pslao.sp_Columnizer @version=2,@object='AdhocData.pslao.DPM_CASMap';
	Exec AdHocData.pslao.sp_Columnizer @version=3,@object='AdhocData.pslao.DPM_CASMap';
	Exec AdHocData.pslao.sp_Columnizer @version=4,@object='AdhocData.pslao.DPM_CASMap';

@Version=1 can also be used with other tools in the DB such as sp_agger.  Example below.

Declare @Columns Varchar(max);
Exec AdHocData.pslao.sp_Columnizer @version=1,@object='AdhocData.pslao.DPM_CASMap',@Columns=@Columns Output;
Exec AdHocData.pslao.sp_Agger 'Sum',@Columns;

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision      Author        Date                 Reason
------------- ---------     -------------------- -------------------------------------------------------------------------------------
00000         BBW			12/18/2020           Implemented
________________________________________________________________________________________________________________
*/
CREATE proc [PSLAO].[sp_Columnizer] (@version int, @object varchar(200),@Columns varchar(max)=Null Output)
as
BEGIN
	If @version = 1 goto one; --@version=1 will output column headers only in a single line comma separated string.
	If @version = 2 goto two; --@version=2 will output column headers + dataType with lengths in a single line comma separated string. Helpful for create table statements.
	If @version = 3 goto three; --@version=3 will output column headers only in vertical position.
	If @version = 4 goto four; --@version=4 will output column headers + dataType with lengths in vertical position.
	return;
END

one:
	Begin
		If @object like '#%' 
			Begin
				SELECT @Columns = COALESCE(@Columns + ', ','') + QUOTENAME(COLUMN_NAME)
				FROM TEMPDB.INFORMATION_SCHEMA.COLUMNS C
				Where TABLE_NAME like parsename(@object,1)+'%'
				ORDER BY ORDINAL_POSITION;
				Select @Columns as Columns_to_String_1;
				Return;
			End
		Else
		SELECT @Columns = COALESCE(@Columns + ', ','') + QUOTENAME(COLUMN_NAME)
		FROM AdhocData.INFORMATION_SCHEMA.COLUMNS C
		Where TABLE_CATALOG = parsename(@object,3)
		and TABLE_SCHEMA = parsename(@object,2)
		and TABLE_NAME = parsename(@object,1)
		ORDER BY ORDINAL_POSITION;
		Select @Columns as Columns_to_String_1;
		Return;
	End;

two:
	Begin
		If @object like '#%' 
			Begin
				SELECT @Columns = COALESCE(@Columns + ', ','') + QUOTENAME(COLUMN_NAME) +' '+ Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
																						   when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +'(MAX)'
																						   when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +'('+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+')'
																						   End
				FROM tempdb.INFORMATION_SCHEMA.COLUMNS C
				Where TABLE_NAME like parsename(@object,1)+'%'
				ORDER BY ORDINAL_POSITION;
				Select @Columns as Columns_to_String_2;
				Return;
			End
		Else
		SELECT @Columns = COALESCE(@Columns + ', ','') + QUOTENAME(COLUMN_NAME) +' '+ Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
																						   when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +'(MAX)'
																						   when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +'('+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+')'
																						   End
		FROM AdhocData.INFORMATION_SCHEMA.COLUMNS C
		Where TABLE_CATALOG = parsename(@object,3)
		and TABLE_SCHEMA = parsename(@object,2)
		and TABLE_NAME = parsename(@object,1)
		ORDER BY ORDINAL_POSITION;
		Select @Columns as Columns_to_String_2;
		Return;
	End;

three:
	Begin
		If @object like '#%' 
			Begin
				SELECT Case when ORDINAL_POSITION=1 then '' else ',' end+
				' '+QUOTENAME(COLUMN_NAME) Columns_Vertical_3
				FROM Tempdb.INFORMATION_SCHEMA.COLUMNS C
				Where TABLE_NAME like parsename(@object,1)+'%'
				ORDER BY ORDINAL_POSITION;
				Return;
			End
		Else
		SELECT Case when ORDINAL_POSITION=1 then '' else ',' end+
		' '+QUOTENAME(COLUMN_NAME) Columns_Vertical_3
		FROM AdhocData.INFORMATION_SCHEMA.COLUMNS C
		Where TABLE_CATALOG = parsename(@object,3)
		and TABLE_SCHEMA = parsename(@object,2)
		and TABLE_NAME = parsename(@object,1)
		ORDER BY ORDINAL_POSITION;
		Return;
	End;

four:
	Begin
		If @object like '#%' 
			Begin
				SELECT Case when ORDINAL_POSITION=1 then '' else ',' end+
				' '+QUOTENAME(COLUMN_NAME) +
				' '+ Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
				when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +'(MAX)'
				when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +'('+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+')'
				End Columns_Vertical_4
				FROM Tempdb.INFORMATION_SCHEMA.COLUMNS C
				Where TABLE_NAME like parsename(@object,1)+'%'
				ORDER BY ORDINAL_POSITION;
				Return;
			End
		Else
		SELECT Case when ORDINAL_POSITION=1 then '' else ',' end+
		' '+QUOTENAME(COLUMN_NAME) +
		' '+ Case when CHARACTER_MAXIMUM_LENGTH is null then Data_Type
		when CHARACTER_MAXIMUM_LENGTH = -1 then Data_Type +'(MAX)'
		when CHARACTER_MAXIMUM_LENGTH is not null then Data_Type +'('+cast(CHARACTER_MAXIMUM_LENGTH as varchar(20))+')'
		End Columns_Vertical_4
		FROM AdhocData.INFORMATION_SCHEMA.COLUMNS C
		Where TABLE_CATALOG = parsename(@object,3)
		and TABLE_SCHEMA = parsename(@object,2)
		and TABLE_NAME = parsename(@object,1)
		ORDER BY ORDINAL_POSITION;
		Return;
	End;
GO

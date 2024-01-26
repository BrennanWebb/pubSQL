USE [Master]
GO
/****** Object:  StoredProcedure [dbo].[test_temp]    Script Date: 6/16/2021 2:41:38 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

Create proc [dbo].[test_temp] (@query nvarchar(max), @HTML nvarchar(MAX)=Null output)
as
DECLARE	@i int = 1,
		@sql nvarchar(max),
		@htmlLoop varchar(max)
		;

drop proc if exists #sp_Query_to_HTML;
--create temp sproc which will create html based tables.
set @SQL='
Create Proc #sp_Query_to_HTML 
(
  @query nvarchar(MAX), --A query to turn into HTML format. It should not include an ORDER BY clause.
  @orderBy nvarchar(MAX) = NULL, --An optional ORDER BY clause. It should contain the words ''ORDER BY''.
  @html nvarchar(MAX) = NULL OUTPUT --The HTML output of the procedure.
)
AS
BEGIN   
  SET NOCOUNT ON;

  IF @orderBy IS NULL BEGIN
    SET @orderBy = ''''  
  END

  SET @orderBy = REPLACE(@orderBy, '''''''', '''''''''''');

  DECLARE @realQuery nvarchar(MAX) = ''
    DECLARE @headerRow nvarchar(MAX);
    DECLARE @cols nvarchar(MAX);    

    SELECT * INTO #dynSql FROM ('' + @query + '') sub;

    SELECT @cols = COALESCE(@cols + '''', '''''''''''''''', '''', '''''''') + ''''['''' + name + ''''] AS ''''''''td''''''''''''
    FROM tempdb.sys.columns 
    WHERE object_id = object_id(''''tempdb..#dynSql'''')
    ORDER BY column_id;

    SET @cols = ''''SET @html = CAST(( SELECT '''' + @cols + '''' FROM #dynSql '' + @orderBy + '' FOR XML PATH(''''''''tr''''''''), ELEMENTS XSINIL) AS nvarchar(max))''''    

    EXEC sys.sp_executesql @cols, N''''@html nvarchar(MAX) OUTPUT'''', @html=@html OUTPUT
	--Set @html=replace(replace(@html,''''&lt;'''',''''<''''),''''&gt;'''',''''>'''');

    SELECT @headerRow = COALESCE(@headerRow + '''''''', '''''''') + ''''<th>'''' + name + ''''</th>'''' 
    FROM tempdb.sys.columns 
    WHERE object_id = object_id(''''tempdb..#dynSql'''')
    ORDER BY column_id;

    SET @headerRow = ''''<tr>'''' + @headerRow + ''''</tr>'''';

    SET @html = ''''<table>'''' + @headerRow + @html + ''''</table>'''';    
    '';

  EXEC sp_executesql @realQuery, N''@html nvarchar(MAX) OUTPUT'', @html=@html OUTPUT;
END
'
EXEC sp_executesql @SQL;

Drop table if exists #querylist
Select identity(int,1,1) ID
,Trim(ListValue)ListValue 
Into #querylist
From Apps.rpt.Split(@query,',')
;

While @i<=(Select Max(ID) from #QueryList)
Begin
	Set @query=(Select ListValue from #QueryList where ID=@i);
	If @query is null goto skp;
	Exec #sp_Query_to_HTML @query, @html=@html Output
	set @htmlLoop=Isnull(@htmlLoop,'')+@Html;
	skp:
	set @i=@i+1;
End

Set @html=@htmlLoop;

Return;




--Use Master
--go
--drop table if exists #test_table_data
--Select top 10 * 
--into #test_table_data
--From tempdb.[sys].[procedures]

--Declare @html varchar(max)
--       ,@query varchar(1000)='Select * from #test_table_data'
--Exec test_temp @query,@html=@html output
--Select @html


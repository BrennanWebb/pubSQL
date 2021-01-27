USE [AdHocData]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_Query_to_HTML]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
Date Written: 12/05/2020
Called From:  Production Script

Purpose: Turns a query into a formatted HTML table. Useful for emails. Any ORDER BY clause needs to be passed in the separate ORDER BY parameter.
Example Usage Script (highlight the lines below and Execute): NA

Declare @HTML varchar(max);
Exec AdhocData.PSLAO.sp_Query_to_HTML @Query='Select 1 F1,2 F2,3F3', @OrderBy = '',@HTML=@HTML Output;
Select @HTML HTML;

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision      Author        Date                 Reason
------------- ---------     -------------------- -------------------------------------------------------------------------------------
00000         BBW			9/05/2020           Implemented
________________________________________________________________________________________________________________
*/

CREATE PROC [PSLAO].[sp_Query_to_HTML] 
(
  @query nvarchar(MAX), --A query to turn into HTML format. It should not include an ORDER BY clause.
  @orderBy nvarchar(MAX) = NULL, --An optional ORDER BY clause. It should contain the words 'ORDER BY'.
  @html nvarchar(MAX) = NULL OUTPUT --The HTML output of the procedure.
)
AS
BEGIN   
  SET NOCOUNT ON;
  SET ANSI_WARNINGS OFF;

  IF @orderBy IS NULL BEGIN
    SET @orderBy = ''  
  END

  SET @orderBy = REPLACE(@orderBy, '''', '''''');

  DECLARE @realQuery nvarchar(MAX) = '
    DECLARE @headerRow nvarchar(MAX);
    DECLARE @cols nvarchar(MAX);    

    SELECT * INTO #dynSql FROM (' + @query + ') sub;

    SELECT @cols = COALESCE(@cols + '', '''''''', '', '''') + ''['' + name + ''] AS ''''td''''''
    FROM tempdb.sys.columns 
    WHERE object_id = object_id(''tempdb..#dynSql'')
    ORDER BY column_id;

    SET @cols = ''SET @html = CAST(( SELECT '' + @cols + '' FROM #dynSql ' + @orderBy + ' FOR XML PATH(''''tr''''), ELEMENTS XSINIL) AS nvarchar(max))''    

    EXEC sys.sp_executesql @cols, N''@html nvarchar(MAX) OUTPUT'', @html=@html OUTPUT
	--Set @html=replace(replace(@html,''&lt;'',''<''),''&gt;'',''>'');

    SELECT @headerRow = COALESCE(@headerRow + '''', '''') + ''<th>'' + name + ''</th>'' 
    FROM tempdb.sys.columns 
    WHERE object_id = object_id(''tempdb..#dynSql'')
    ORDER BY column_id;

    SET @headerRow = ''<tr>'' + @headerRow + ''</tr>'';

    SET @html = ''<table>'' + @headerRow + @html + ''</table>'';    
    ';

  EXEC sys.sp_executesql @realQuery, N'@html nvarchar(MAX) OUTPUT', @html=@html OUTPUT;
END
GO

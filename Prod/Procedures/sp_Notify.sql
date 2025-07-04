USE [master]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER proc [dbo].[sp_Notify] 
	( 
	@Profile_Name varchar(50)	= Null,
	@Recipients varchar(max)	= Null,
	@Subject varchar(250)		= Null,
	@Messages varchar(max)		= NULL,
	@Queries varchar(max)		= Null,
	@OrderBy varchar(500)		= Null,
	@CC	varchar(1000)			= Null,
	@Bcc varchar(1000)			= Null,
	@HTML_Header varchar(max)	= NULL,
	@HTML_Footer varchar(max)	= NULL,
	@Output varchar(max)		= Null Output,
	@MailID int					= Null Output,
	@Body_Format varchar(20)	= 'HTML',
	@print bit					= 0
	)
as
set nocount on;
Declare @VersionHistory Varchar(max) =
'Ver	|	Author			|	Date			|	Note	
0	|	Brennan Webb	|	2024-07-11		|	Implemented
1	|	Brennan Webb	|	2025-04-02		|	Added SMS options and randomized temp proc names
2	|	Brennan Webb	|	2025-05-28		|	Added @MailID as output
';

If @Profile_Name is null OR @Recipients is null OR @Subject is null goto help;

 DECLARE	
	@i int						= 1,
	@sql nvarchar(max),
	@HTML varchar(MAX)			='',
	@HTML_Body varchar(max)		='',
	@NID VARCHAR(8)				= LEFT(NEWID(),8)
	--@Messages varchar(max)	= NULL,
	--@Queries varchar(max)		= Null,
	--@OrderBy varchar(500)		= Null,
;

--------------------------------------------------------------------
/*create temp procs.*/
--------------------------------------------------------------------
If object_ID('tempdb..##sp_Query_to_HTML_'+@NID)is null
Begin
	Exec('CREATE PROCEDURE ##sp_Query_to_HTML_'+@NID+'
		(
			@Queries nvarchar(MAX), --A query to turn into HTML format. It should not include an ORDER BY clause.
			@orderBy nvarchar(MAX) = '''', --An optional ORDER BY clause. It should contain the words ''ORDER BY''.
			@html nvarchar(MAX) OUTPUT --The HTML output of the procedure.
		)
		AS
		BEGIN   
			SET NOCOUNT ON;
			SET ANSI_WARNINGS OFF;

			SET @orderBy = REPLACE(IsNull(@orderBy,''''), '''''''', '''''''''''');

			DECLARE @realQuery nvarchar(MAX) = ''
			DECLARE @headerRow nvarchar(MAX);
			DECLARE @cols nvarchar(MAX);    

			SELECT * INTO #dynSql FROM ('' + @Queries + '') sub;

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
		END;
	')
End;



If object_ID('tempdb..##sp_Email_'+@NID)is null
Begin
	Set @sql = 'Create procedure ##sp_Email_'+@NID+'
	(
		@Profile_Name   varchar(50),
		@Recipients		varchar(max),
		@cc				varchar(max)	=null,
		@Bcc			varchar(max)    =null,
		@Header			varchar(max)    =null,    
		@Subject		varchar(max),
		@Body			varchar(max)	= null,
		@Footer         varchar(max)    ='''',
		@Body_Format	varchar(max)	=''html'',
		@Output         varchar(max)    = null output,
		@MailID         Int				= null output
	)
	as

	If @body_format =''html''
	Begin
		If @Header is null
		Begin
			Set @Header=''
				<head>
				<meta charset="UTF-8">
				<meta name="viewport" content="width=device-width, initial-scale=1.0">
				<style>
					body {
						text-align: left;
						font-family: Open Sans, arial;
						font-size: 12px;
						padding: 10px;
					}

					h1 {
						color: #F17C21;
					}

					h2 {
						color: #00a5bc;
					}

					h3 {
						color: #00a5bc;
					}
		
					h4 {
						color: #656666;
					}

					h5 {
						color: #656666;
					}

					h6 {
						color: #656666;
					}

					table {
						padding: 5px;
						border-color: #656666;
						border-style: solid;
						border-width: 1px;
						border-radius: 3px;
						margin-bottom: 20px;
						text-align: left;
					}

					tr:hover {background-color: #f5f5f5;} 

					th {
						color: #656666;
						background: #e0e0e0;
						border-radius: 3px;
						padding:3px;
						text-align: center;
					}

					td {
						color: #656666;
						column-width: auto;
						padding:3px;
						border-bottom: 1px solid #ddd;
					}

					footer{
						font-size: 8px;
						color: #e0e0e0;
					}
					</style>
				</head>''
			End

		  set @body=''<!DOCTYPE html><html lang="en">''+@header+''
			<body>
			''+isnull(@body,'''')+'' 
			</body>
		</html>
		<hr>
		''
	End
	;

	SET @Body = @Body + IsNull(@Footer,''''); --Print ''@Body: ''+@Body

	set @output = @body
	if coalesce(@recipients,@cc,@bcc) is not null
	begin
		exec msdb.dbo.sp_send_dbmail
				@profile_name			= @profile_name,
				@recipients				= @recipients,
				@copy_recipients		= @cc,
				@blind_copy_recipients  = @bcc,
				@subject				= @subject,
				@body_format			= @body_format,
				@body					= @body,
				@mailitem_id			= @mailID Output					
				;
	end;
	'
Exec sp_executesql @sql;
End;
--------------------------------------------------------------------
/*split param inputs*/
--------------------------------------------------------------------
--for our recipient list, if a recipient is numeric only and is 10 digits, we will assume top US based carriers and append their gateway info to the number.
--See https://avtech.com/articles/138/list-of-email-to-sms-addresses/ for full list.

SET @Recipients = IIF(Right(Trim(@Recipients),1)=';',Left(Trim(@Recipients),Len(@Recipients)-1),@Recipients);
Drop table if exists #Recipients;
Select Identity(int,1,1) id, Trim([Value]) + IIF(v.SMSDomains IS NOT NULL,v.SMSDomains,'') [Value]
Into #Recipients
From string_split(@Recipients,';')A
LEFT JOIN (VALUES	('@vtext.com'),('@tmomail.net'),('@txt.att.net'),('@msg.fi.google.com')) v(SMSDomains)
ON IIF(ISNUMERIC(Trim([Value]))=1 AND LEN(Trim([Value]))=10,1,0)=1
--Select * From #Recipients

--Bring recipient list back together.
SELECT @Recipients = STRING_AGG([Value],'; ') FROM #Recipients

Set @Messages = IIF(Right(Trim(@Messages),1)=';',Left(Trim(@Messages),Len(@Messages)-1),@Messages);
Drop table if exists #Messages;
Select Identity(int,1,1) id, Trim([Value]) [Value]
Into #Messages
From string_split(@Messages,';')
--Select * From #Messages

Set @Queries = IIF(Right(Trim(@Queries),1)=';',Left(Trim(@Queries),Len(@Queries)-1),@Queries);
Drop table if exists #QueryLoop;
Select Identity(int,1,1) id, Trim([Value]) [Value]
Into #QueryLoop
From string_split(@Queries,';')
--Select * From #QueryLoop

Set @OrderBy = IIF(Right(Trim(@OrderBy),1)=';',Left(Trim(@OrderBy),Len(@OrderBy)-1),@OrderBy);
Drop table if exists #OrderBy;
Select Identity(int,1,1) id, Trim([Value]) [Value]
Into #OrderBy
From string_split(@OrderBy,';');
--Select * From #OrderBy

--------------------------------------------------------------------
/*Build HTML body*/
--------------------------------------------------------------------
While @i<= (Select Max(id) from #QueryLoop) or @i<= (Select Max(id) from #Messages)
Begin
	
	Set @Messages = Isnull((Select [value] from #Messages Where id=@i),'');	--Print '@Messages: '+@Messages;
	Set @Queries = (Select [value] from #QueryLoop Where id=@i); --Print '@Queries: '+@Queries;
	Set @OrderBy = Isnull((Select [value] from #OrderBy Where id=@i),'');--Print '@OrderBy: '+@OrderBy;
	
	SET @sql =	'EXEC ##sp_Query_to_HTML_'+@NID+' 
					@Queries=@Queries,
					@OrderBy = @OrderBy, 
					@HTML=@HTML OUTPUT;'
	Exec sp_executesql @sql,
			N'@Queries nvarchar(MAX),
			  @orderBy nvarchar(MAX),
			  @html nvarchar(MAX) OUTPUT
			',
			@Queries=@Queries,
			@OrderBy = @OrderBy, 
			@HTML=@HTML OUTPUT;

	Set @HTML_Body = @HTML_Body +IIF(@Body_Format='HTML' and IsNull(@Messages,'') not like '%<__>%' --Auto detect if styling is in the string.
									,'<h2>'+ IsNull(@Messages,'')+'</h2>'
									,IsNull(@Messages,''))
								+ IIF(@Body_Format='HTML',ISNULL(@HTML,'<h5>No Data</h5>'),'');
	Set @HTML =''; Set @Messages = ''; Set @Queries = 	''; Set @OrderBy = 	''
	Set @i=@i+1;
End;

--------------------------------------------------------------------
/*Send Email*/
--------------------------------------------------------------------
Begin Try
	SET @sql ='EXEC ##sp_Email_'+@NID+' 
			@Profile_Name = @Profile_Name,
			@Recipients = @Recipients,
			@cc = @cc,
			@Bcc = @Bcc,
			@Header = @Header,
			@Subject = @Subject,
			@Body = @Body,
			@Footer = @Footer,
			@Output = @Output OUTPUT,
			@MailID = @MailID OUTPUT,
			@Body_Format = @Body_Format;
			';

	Exec sp_executesql @sql,
		N'  @Profile_Name   varchar(50) ,
			@Recipients		varchar(max),
			@cc				varchar(max),
			@Bcc			varchar(max),
			@Header			varchar(max),
			@Subject		varchar(max),
			@Body			varchar(max),
			@Footer         varchar(max),
			@Output         varchar(max) OUTPUT,
			@MailID         INT			 OUTPUT,
			@Body_Format	varchar(max)
		',
		@Profile_Name = @Profile_Name,
		@Recipients = @Recipients,
		@Subject = @Subject,
		@CC = @CC,
		@Bcc = @Bcc,
		@Body = @HTML_Body,
		@Header= @HTML_Header,
		@Footer = @HTML_Footer,
		@Output = @Output Output,
		@MailID = @MailID Output,
		@Body_Format=@Body_Format;
	
		PRINT IIF(@print=1,@Output,'');

	End Try
	Begin Catch
		;Throw;
	End Catch;

RETURN;

Help:
Begin
	print '
This proc allows a user to creates a streamlined notification process with preset formatting.

REQUIRED PARAMETERS:
	@Profile_Name	= Enter a valid msdb.dbo.sp_send_dbmail registered email profile
	@Recipients		= Semicolon separated list of email recipients.
	@Subject		= Must provide a subject line.

OPTIONAL PARAMETERS:
	@Queries		= Semicolon separated queries which will be processed inline in the same email.
	@OrderBy		= Semicolon separated order by operation. Must contain the words ''ORDER BY''.
	@Messages		= Semicolon separated messages. Will be put into email body in order submitted.
	@CC				= Semicolon separated list of carbon copy email recipients.
	@Bcc			= Semicolon separated list of blind carbon copy email recipients.
	@HTML_Header	= Advanced: Custom HTML Header may be provided.  
	@HTML_Footer	= Advanced: Custom HTML Footer may be provided.
	@MailID			= Outputs the MailItem_ID for logging purposes.

See usage examples below.

--------------------------------------------------------------------
**Note** - These executions require permissions to msdb.dbo.sp_send_dbmail which should be properly configured with email profiles.

--Send an email with a subject only. No email body.  Great for quick notifications of a server job failure, etc.
sp_Notify 	
	@Profile_Name	= ''roboSQL'',
	@Recipients 	= ''Person1@Test.com; Person2@test.com'',
	@Subject 		= ''Test Email''
	;

--Send an email with a body formatted in text rather than HTML. Embedded @queries will not be included.
sp_Notify 	
	@Profile_Name	= ''roboSQL'',
	@Recipients 	= ''Person1@Test.com; Person2@test.com'',
	@Subject 		= ''Test Email'',
	@Messages		= ''Test Text Format Message'',
	@Body_Format	= ''Text''
	;

--Send an email with multiple queries in the email body with order by''s.  Great for quick report notifications.
Declare @MailID int;
sp_Notify 	
	@Profile_Name	= ''roboSQL'',
	@Recipients 	= ''Person1@Test.com; Person2@test.com'',
	@Subject 		= ''Test Email'',
	@Messages		= ''<h1>Big Title</h1><h2>Query From sys.Tables</h2><h5>This is a note for the first output</h5>;
					   <h2>Query From sys.Views</h2><h5>This is a note for the second output</h5>;'',
	@Queries		= ''Select name, object_id, type From sys.tables; Select name, object_id, type From sys.views;'',
	@OrderBy		= ''Order by 1 Desc; Order by 1 Desc'',
	@Print			= 1, --Set @Print to true to see the full HTML body.
	@MailID			=@MailID Output
	;
Select @MailID

--NOTE! Temp tables can also be used.
DROP TABLE IF EXISTS #t1,#t2;
SELECT name, object_id, type  INTO #t1 FROM sys.tables; 
SELECT name, object_id, type INTO #t2 FROM sys.views;

EXEC sp_Notify 	
	@Profile_Name	= ''roboSQL'',
	@Recipients 	= ''Person1@Test.com; Person2@test.com'',
	@Subject 		= ''Test Email'',
	@Messages		= ''<h1>Big Title</h1><h2>Query From sys.Tables USING A temp TABLE!</h2><h5>This is a note for the first output</h5>;
						<h2>Query From sys.VIEWS USING A temp TABLE! Wild!!</h2><h5>This is a note for the second output</h5>;'',
	@Queries		= ''Select name, object_id, type From #t1; Select name, object_id, type From #t2;'',
	@OrderBy		= ''Order by 1 Desc; Order by 1 Desc'',
	@Print			= 1 --Set @Print to true to see the full HTML body..
	;

--Send an email with multiple queries in the email body with order by''s and custom <head> and <footer>.  Quick styling option.  
--Note!! Not all email providers support CSS styling.
Declare @Header varchar(max) = ''<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: Arial, sans-serif;
            color: #333;
            margin: 0;
            padding: 0;
        }
        .email-container {
            width: 100%;
            max-width: 600px;
            margin: 0 auto;
            border: 1px solid #dddddd;
            border-radius: 5px;
            overflow: hidden;
        }
        .header {
            background-color: #00a5bc;
            color: white;
            text-align: center;
            padding: 20px;
            font-size: 24px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            border: 1px solid #dddddd;
            padding: 8px;
            text-align: left;
        }
        th {
            background-color: #f9f9f9;
            color: #666;
        }
        tr:nth-child(even) td {
            background-color: #f4f4f4;
            font-weight: bold;
        }
        tr:nth-child(odd) td {
            background-color: #ffffff;
        }
    </style>
</head>

''
	,@Footer varchar(max) = ''<footer><p>&copy; {Year} YourCompany</p></footer>''
sp_Notify 	
	@Profile_Name	= ''roboSQL'',
	@Recipients 	= ''Person1@Test.com; Person2@test.com'',
	@Subject 		= ''Test Email'',
	@Messages		= ''sys.tables; sys.views;'',
	@Queries		= ''Select name, object_id, type From sys.tables; Select name, object_id, type From sys.views;'',
	@OrderBy		= ''Order by 1 Desc; Order by 1 Desc'',
	@HTML_Header	= @Header,
	@HTML_Footer	= @Footer,
	@Print			= 1 --Set @Print to true to see the full HTML body.
	;
'
	Print @VersionHistory;
	Return;
End
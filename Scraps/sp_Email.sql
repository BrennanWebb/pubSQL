USE [MASTER]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_Email]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


alter proc [dbo].[sp_Email]
(
	@Profile_Name   varchar(50),
	@Recipients		varchar(max)    =null,
	@cc				varchar(max)	=null,
	@Bcc			varchar(max)    =null,
	@Header			varchar(max)    =null,    
	@Subject		varchar(max),
	@Body			varchar(max)	= null,
	@Footer         varchar(1500)   ='',
	@Body_Format	varchar(max)	='html',
	@Output         varchar(max)    = null output
)
as

/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
	
Purpose: Sproc which hold DBmail method with added html elements.
Example Usage Script (change the email address, highlight the lines below, and Execute): NA

Exec sp_Email
@profile_name = 'roboSQL',
@recipients = 'youremail@selectquote.com',
@Subj = 'Test',
@Body = 'Blah,Blah',
@Body_Format = 'HTML'
;

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision		Author        Date                 Reason
-------------	---------     -------------------- -------------------------------------------------------------------------------------
00000			Brennan.Webb	2/15/2021			 Implemented
________________________________________________________________________________________________________________
*/

--apply style
If @body_format ='html'
Begin
	If @Header is null
	Begin
		Set @Header='<!doctype html>
<html>
	<head>
	<style>
		body {
			text-align: left;
			font-family: Open Sans, arial;
			font-size: 12px;
			padding: 5px;
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
			border-radius: 5px;
		}

		tr {
			text-align: left;
		}

		th {
			text-transform: uppercase;
			text-align: left;
			color: #656666;
			background: #e0e0e0;
			border-radius: 5px;
			padding:3px;

		}

		td {
			color: #656666;
			column-width: auto;
			padding:3px;
		}

		footer{
			font-size: 8px;
			color: #e0e0e0;
		}
		</style>
	</head>'
	End
  set @body=@header+'
	<body>
	'+isnull(@body,'')+' 
	</body>
</html>
'
End
;

SET @Body = @Body+'<HR>'+@Footer;

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
			@body					= @body;
end
;
--Select @output
;




				
GO

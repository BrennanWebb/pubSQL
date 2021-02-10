USE [AdHocData]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_Email]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE proc [PSLAO].[sp_Email]
(
	@from_email     varchar(50)     ='bwebb7@humana.com',
	@to_email		varchar(max),
	@cc				varchar(max)	=null,    
	@subj			varchar(max),
	@body			varchar(max)	= null,
	@body_format	varchar(max)	='html',
	@output         varchar(max)    = null output
)
as

/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
Date Written: 12/05/2020
Called From:  Production Script

Purpose: Sproc which hold DBmail method with added html elements.
Example Usage Script (highlight the lines below and Execute): NA

Exec AdhocData.PSLAO.sp_Email
@To_Email = 'youremail@humana.com',
@Subj = 'Test',
@Body = 'Blah,Blah',
@Body_Format = 'HTML'
;

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision      Author        Date                 Reason
------------- ---------     -------------------- -------------------------------------------------------------------------------------
00000         BBW			9/05/2020           Implemented
________________________________________________________________________________________________________________
*/

--apply style
If @body_format ='html'
Begin
  set @body='
<!doctype html>
<html>
	<head>
	<style>
		body {
			font-family: arial;
			font-size: 12px;
		}

		h1 {
			padding: 5px;
			color: #78BE20;
		}

		h2 {
			color: #333333;
		}

		h3 {
			color: #333333;
		}

		table {
		    padding: 5px;
			border-color: #666666;
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
			color: #78be20;
			background: #eeeeee;
			border-radius: 5px;
			padding:3px;

		}

		td {
			color: #666666;
			column-width: auto;
			padding:3px;
		}

		footer{
			font-size: 8px;
			color: #e0e0e0;
		}
	  </style>
	</head>
	<body>
	'+@body+' 
	</body>
</html>
'
End

set @output = @body
if coalesce(@to_email,@cc) is not null
begin
	exec msdb.dbo.sp_send_dbmail
				@from_address       = @from_email,
				@recipients			= @to_email,
				@copy_recipients	= @cc,
				@subject			= @subj,
				@body_format		= @body_format,
				@body				= @body;
end
;




				
GO

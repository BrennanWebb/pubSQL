USE [AdHocData]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_SMS_Notify]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
Date Written: 12/05/2020
Called From:  Production Script

Purpose: Sproc that executes sp_Email specific to Brennan Webb cell number.
Example Usage Script (highlight the lines below and Execute): NA

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision      Author        Date                 Reason
------------- ---------     -------------------- -------------------------------------------------------------------------------------
00000         BBW			9/05/2020           Implemented
________________________________________________________________________________________________________________
*/

CREATE proc [PSLAO].[sp_SMS_Notify] (@Msg Varchar(250))
as
Set @Msg= @Msg + 'Sent by: '+current_user
Exec [PSLAO].[sp_Email]
@from_email = 'bwebb7@humana.com'
,@to_email = '5024579194@msg.fi.google.com'
,@subj = 'Work Notify'
,@body = @Msg
,@body_format='text'
;
GO

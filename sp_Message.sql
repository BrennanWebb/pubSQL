USE [Master]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_Message]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE proc [dbo].[sp_Message] (@string varchar(100) = Null, @int int = Null)
as

/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
Date Written: 12/05/2020

Purpose: Sproc used to shorthand immediate console prints using RaiseError method.
Example Usage Script (Highlight the lines below and Execute):

Exec AdhocData.[PSLAO].[sp_Message] 'Start Loop.', 5;

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision      Author        Date                 Reason
------------- ---------     -------------------- -------------------------------------------------------------------------------------
00000         BBW			9/05/2020           Implemented
________________________________________________________________________________________________________________
*/

Declare @timestamp varchar (19) =convert(varchar,getdate(),121)
Set @String = ISNULL(@String,'')
--Set @int  = Isnull(@int,0)
RAISERROR ('Message: %s | %d | %s', 0, 1, @String, @int, @timestamp) WITH NOWAIT;
return
 
GO

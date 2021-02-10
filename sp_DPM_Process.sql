USE [AdHocData]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_DPM_Process]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 CREATE proc [PSLAO].[sp_DPM_Process] (
   @Status			int,
   @Action			varchar(20),
   @Database		varchar(25),
   @Schema			varchar(25),
   @Object			varchar(150),
   @RowCount		bigint       = null,
   @StartTime		datetime,
   @EndTime			datetime     = null,
   @Notes			varchar(max) = null
   )
   as
/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
Date Written: 08/05/2020
Called From:  Production Scripts

Purpose: This script is used to Insert, Update, and Delete process data elements from process log AdHocData.PSLAO.DPM_Process.
Example Usage Script (highlight the lines below and execute): NA
-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision      Author        Date                 Reason
------------- ---------     -------------------- -------------------------------------------------------------------------------------
00000         BBW			08/05/2020           Implemented
________________________________________________________________________________________________________________
*/
SET NOCOUNT ON
Declare @User Varchar(25) =Current_User
BEGIN
	If not exists (Select * 
					From AdHocData.PSLAO.DPM_Process 
					Where [Action]   =@Action 
					  and [Database] =@Database 
					  and [Schema]   =@Schema 
					  and [Object]   =@Object)
		BEGIN
			Insert into AdHocData.PSLAO.DPM_Process 
			([Status],[Action],[Database],[Schema],[Object],[RowCount],[StartTime],[EndTime],[Notes],[User])
			Values 
			(@Status,@Action,@Database,@Schema,@Object,@RowCount,@StartTime,@EndTime,@Notes,@User)
		END

	Else 
		BEGIN
			Update AdHocData.PSLAO.DPM_Process
			Set [Status]			=@Status
			   ,[Action]			=@Action
			   ,[Database]			=@Database
			   ,[Schema]			=@Schema
			   ,[Object]			=@Object
			   ,[RowCount]			=@RowCount
			   ,[StartTime]			=@StartTime
			   ,[EndTime]			=@EndTime
			   ,[Notes]				=@Notes
			   ,[User]				=@User
		END
END
GO

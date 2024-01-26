USE [master]
GO

/****** Object:  Trigger [dbo].[trg_Notify_Modified]    Script Date: 2/16/2021 8:09:48 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TRIGGER [dbo].[trg_Notify_Modified]
ON [dbo].[Notify]
AFTER  UPDATE
AS
If TRIGGER_NESTLEVEL()>1 Return;

Update A
Set Notify_Modified = case when B.Notify_ID is not null then getdate() end
   ,Notify_Modified_By = case when B.Notify_ID is not null then coalesce(nullif(system_user,'dbo'),nullif(user_name(),'dbo'),nullif(current_user,'dbo')) end
From [master].[dbo].[Notify] A
inner join Inserted B on A.Notify_ID=B.Notify_ID
;
GO

ALTER TABLE [dbo].[Notify] ENABLE TRIGGER [trg_Notify_Modified]
GO



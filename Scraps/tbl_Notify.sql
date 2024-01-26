USE [master]
GO

/****** Object:  Table [dbo].[Notify]    Script Date: 2/16/2021 10:17:09 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[Notify](
	[Notify_ID] [int] IDENTITY(1,1) NOT NULL,
	[Notify_Owner] [varchar](50) NOT NULL,
	[Notify_Created] [datetime] NOT NULL,
	[Notify_Created_By] [varchar](50) NOT NULL,
	[Notify_Modified] [datetime] NOT NULL,
	[Notify_Modified_By] [varchar](50) NOT NULL,
	[Notify_Name] [varchar](250) NOT NULL,
	[Notify_Stage] [int] NOT NULL,
	[Notify_Seq] [int] NOT NULL,
	[Profile_Name] [varchar](50) NULL,
	[From_Address] [varchar](50) NULL,
	[Recipients] [varchar](max) NULL,
	[Subject] [varchar](250) NULL,
	[Query] [varchar](max) NULL,
	[Query_Order_By] [varchar](300) NULL,
	[HTML_Header] [varchar](max) NULL,
	[HTML_Body] [varchar](max) NULL,
	[HTML_Footer] [varchar](max) NULL,
	[Notify_Last_Exec] [datetime] NULL,
	[Notify_Err_Message] [varchar](max) NULL,
	[Notify_Err_Line] [varchar](20) NULL,
	[Notify_Err_Number] [varchar](20) NULL,
	[Notify_Err_Severity] [varchar](20) NULL,
	[Notify_Err_State] [varchar](20) NULL,
PRIMARY KEY CLUSTERED 
(
	[Notify_Name] ASC,
	[Notify_Stage] ASC,
	[Notify_Seq] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[Notify] ADD  DEFAULT (getdate()) FOR [Notify_Created]
GO

ALTER TABLE [dbo].[Notify] ADD  DEFAULT (coalesce(nullif(suser_sname(),'dbo'),nullif(user_name(),'dbo'),nullif(user_name(),'dbo'))) FOR [Notify_Created_By]
GO

ALTER TABLE [dbo].[Notify] ADD  DEFAULT (getdate()) FOR [Notify_Modified]
GO

ALTER TABLE [dbo].[Notify] ADD  DEFAULT (coalesce(nullif(suser_sname(),'dbo'),nullif(user_name(),'dbo'),nullif(user_name(),'dbo'))) FOR [Notify_Modified_By]
GO

ALTER TABLE [dbo].[Notify]  WITH CHECK ADD  CONSTRAINT [CK_HTML_Footer_Not11] CHECK  ((case when [Notify_Stage]>=(1) AND [Notify_Seq]>(1) AND [HTML_Footer] IS NOT NULL then (1)  end=(0)))
GO

ALTER TABLE [dbo].[Notify] CHECK CONSTRAINT [CK_HTML_Footer_Not11]
GO

ALTER TABLE [dbo].[Notify]  WITH CHECK ADD  CONSTRAINT [CK_HTML_Header_Not11] CHECK  ((case when [Notify_Stage]>=(1) AND [Notify_Seq]>(1) AND [HTML_Header] IS NOT NULL then (1)  end=(0)))
GO

ALTER TABLE [dbo].[Notify] CHECK CONSTRAINT [CK_HTML_Header_Not11]
GO

ALTER TABLE [dbo].[Notify]  WITH CHECK ADD  CONSTRAINT [CK_Profile_Or_From] CHECK  (([Profile_Name] IS NULL AND [From_Address] IS NOT NULL OR [Profile_Name] IS NOT NULL AND [From_Address] IS NULL))
GO

ALTER TABLE [dbo].[Notify] CHECK CONSTRAINT [CK_Profile_Or_From]
GO

ALTER TABLE [dbo].[Notify]  WITH CHECK ADD  CONSTRAINT [CK_Recipients_Not11] CHECK  ((case when [Notify_Stage]>=(1) AND [Notify_Seq]>(1) AND [Recipients] IS NOT NULL then (1)  end=(0)))
GO

ALTER TABLE [dbo].[Notify] CHECK CONSTRAINT [CK_Recipients_Not11]
GO

ALTER TABLE [dbo].[Notify]  WITH CHECK ADD  CONSTRAINT [CK_Recipients_NotNull] CHECK  ((case when [Notify_Stage]=(1) AND [Notify_Seq]=(1) AND [Recipients] IS NULL then (1)  end=(0)))
GO

ALTER TABLE [dbo].[Notify] CHECK CONSTRAINT [CK_Recipients_NotNull]
GO

ALTER TABLE [dbo].[Notify]  WITH CHECK ADD  CONSTRAINT [CK_Subject_Not11] CHECK  ((case when [Notify_Stage]>=(1) AND [Notify_Seq]>(1) AND [Subject] IS NOT NULL then (1)  end=(0)))
GO

ALTER TABLE [dbo].[Notify] CHECK CONSTRAINT [CK_Subject_Not11]
GO

ALTER TABLE [dbo].[Notify]  WITH CHECK ADD  CONSTRAINT [CK_Subject_NotNull] CHECK  ((case when [Notify_Stage]=(1) AND [Notify_Seq]=(1) AND [Subject] IS NULL then (1)  end=(0)))
GO

ALTER TABLE [dbo].[Notify] CHECK CONSTRAINT [CK_Subject_NotNull]
GO



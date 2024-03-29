USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_Notify]    Script Date: 2/16/2021 2:40:23 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



/************************************************************************************************************************
 Author:		<Author,,Name>
 Create date:	<Create Date,,>
 Jira Ticket:	<Ticket ID,,>
 Description:	<Description of what this object does>
 SLA:			<Description,,>
 Caller:		<App executing procedure>
 Audience:		<Description,,>
 Change Log
--------------------------------------------------------------------------------------------------------------------------
| Date       | Jira Ticket ID | Developer           | Change Summarized                                                  |
--------------------------------------------------------------------------------------------------------------------------
| XX/XX/XXXX |                |                     |                                                                    |
--------------------------------------------------------------------------------------------------------------------------
**************************************************************************************************************************/



ALTER proc [dbo].[sp_Notify] (@Notify_Name varchar(250))
as

/*
________________________________________________________________________________________________________________
Purpose: Notification module designed to reduce code volume, copy/paste errors-effort, and centralizes notifications.  
		 Also standardizes HTML styles, unless specified otherwise.  

Example Usage Script (highlight the lines below and execute once sproc is installed):

		 Exec sp_notify 'test1'

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision		Author        Date                 Reason
-------------	---------     -------------------- -------------------------------------------------------------------------------------
00000			Brennan.Webb	2/15/2021			 Implemented
________________________________________________________________________________________________________________
*/


set nocount on;

 DECLARE	@i int = 1,
			@HTML varchar(MAX)='',
			@Notify_ID int,
			@Notify_Owner varchar(50),
			@Notify_Created datetime,
			@Notify_Created_By varchar(50),
			@Notify_Modified datetime,
			@Notify_Modified_By varchar(50),
			--@Notify_Name varchar(250) ='Test1',
			@Notify_Stage int,
			@Notify_Seq int,
			@Profile_Name varchar(50),
			@From_Address varchar(50),
			@Recipients varchar(1000),
			@Subject varchar(250),
			@Query varchar(max) = null,
			@Query_Order_By varchar(300),
			@HTML_Header varchar(max)=null,
			@HTML_Body varchar(max) ='',
			@HTML_Body_Temp varchar(max),
			@HTML_Footer varchar(max),
			@Notify_Last_Exec datetime,
			@Notify_Err_Message varchar(max),
			@Notify_Err_Line varchar(20),
			@Notify_Err_Number varchar(20),
			@Notify_Err_Severity varchar(20),
			@Notify_Err_State varchar(20) 
;

Drop Table if exists #notify_filtered;
Select dense_rank() over (order by Notify_Stage,Notify_Seq) RID, *
into #notify_filtered
From [Master].dbo.Notify
Where Notify_Name=@Notify_Name
;

While @i<= (Select Max(rid) from #notify_filtered)
Begin
	Select  @Notify_ID = Notify_ID,
			@Notify_Owner = Notify_Owner,
			@Notify_Created = Notify_Created,
			@Notify_Created_By = Notify_Created_By,
			@Notify_Modified = Notify_Modified,
			@Notify_Modified_By = Notify_Modified_By,
			@Notify_Name = Notify_Name,
			@Notify_Stage = Notify_Stage,
			@Notify_Seq = Notify_Seq,
			@Profile_Name = coalesce(Profile_Name,@Profile_Name),
			@From_Address = coalesce(From_Address,@From_Address),
			@Recipients = coalesce(Recipients,@Recipients),
			@Subject = coalesce([Subject],@Subject),
			@Query = Query,
			@Query_Order_By = isNull(Query_Order_By,''),
			@HTML_Header = coalesce(HTML_Header, @HTML_Header),
			@HTML_Body_Temp = isNull(HTML_Body,''),
			@HTML_Footer = coalesce(HTML_Footer, @HTML_Footer)
		From #notify_filtered
		Where RID=@i
		;

	If @Query is not null
		Begin
			EXEC sp_Query_to_HTML @Query=@Query ,@OrderBy = @Query_Order_By , @HTML=@HTML OUTPUT;
			Set @HTML_Body = @HTML_Body + @HTML_Body_Temp + ISNULL(@HTML,'');
		End
	Else
		Begin
			Set @HTML_Body = @HTML_Body + @HTML_Body_Temp;
		End
	;
	
	Set @i=@i+1;
End

EXEC sp_Email
@Profile_Name = @Profile_Name,
@Recipients = @Recipients,
@Header= @HTML_Header,
@Subject = @Subject,
@Body = @HTML_Body,
@Footer = @HTML_Footer
;


/*
Enhancements
__________________
Add error logging
Add CC, BCC
Add Test Flag to email only to current dev
work on @Notify_Owner validation
Notify_Active Flag,
Add Jira_Ticket reference?
add attachment option
*/
USE [msdb]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

Create or Alter function [dbo].[fn_SysJobHistoryDateTime] (@Type varchar(5), @Run_Date int, @Run_Time int, @Run_Duration int)
Returns DateTime
as
Begin
	Declare @Datetime DateTime;
	If @Type = 'Start'
		Begin
		 Set @Datetime =  dateadd(second,  
		  (convert(int,(@Run_Time / 10000)) * 3600 )
		+ (convert(int,(@Run_Time / 100))%100) * 60 
		+ (convert(int,(@Run_Time / 1))%100)
		  ,convert(DATETIME,RTRIM(@Run_Date))); 
		End;
	Else IF @Type = 'End'
		Begin
		 Set @Datetime =  dateadd(second,  
		  (convert(int,(@Run_Time / 10000)) * 3600 )
		+ (convert(int,(@Run_Time / 100))%100) * 60 
		+ (convert(int,(@Run_Time / 1))%100)
		+ (convert(int,(@Run_Duration / 1000000))) * 3600 * 24
		+ (convert(int,(@Run_Duration / 10000))%100) * 3600
		+ (convert(int,(@Run_Duration / 100))%100) * 60
		+ (convert(int,(@Run_Duration / 1))%100)
		  ,convert(DATETIME,RTRIM(@Run_Date)));
		End;
	Return (@Datetime);
End;
GO



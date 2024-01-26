USE [Master]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_SPID_Activity]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
________________________________________________________________________________________________________________
Purpose: Displays SPID activity based on WHO2, which ships with Microsft SQL server.  
This sproc will table the results to ##SPID_Activity for further investigation.

Example Usage Script (highlight the lines below and execute once installed):

	Begin
		exec pslao.[sp_SPID_Activity] 'status=''sleeping'' '
	End
________________________________________________________________________________________________________________
*/

CREATE proc [dbo].[sp_SPID_Activity]
(
	@Where varchar(max)=Null
)
as
Declare @sql  varchar(max);

if object_id('tempdb..##SPID_Activity') is not null drop table ##SPID_Activity;

Set @SQL = '
CREATE TABLE ##SPID_Activity (SPID INT
,Status VARCHAR(255)
,Login  VARCHAR(255)
,HostName  VARCHAR(255)
,BlkBy  VARCHAR(255)
,DBName  VARCHAR(255)
,Command VARCHAR(255)
,CPUTime INT
,DiskIO INT
,LastBatch VARCHAR(255)
,ProgramName VARCHAR(255)
,SPID2 INT
,REQUESTID INT);

INSERT INTO ##SPID_Activity 
EXEC sp_who2;

SELECT *
FROM ##SPID_Activity
Where spid<>@@spid
'+Isnull('and '+@Where,'')+'
ORDER BY SPID ASC;
';

Exec(@SQL);
;
GO

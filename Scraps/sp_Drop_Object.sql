USE [AdHocData]
GO
/****** Object:  StoredProcedure [PSLAO].[sp_Drop_Object]    Script Date: 1/27/2021 10:22:02 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE proc [PSLAO].[sp_Drop_Object](@object varchar(250))
as

/*
-----------------------------------------------------------------------------------------------------------------------------------------
Author: Brennan Webb
Date Written: 2020-08-05
Called From:  Production Script 

Purpose: Sproc that calls for drop of objects within current DB or TempDb in a shorthand way.
Example Usage Script (highlight the lines below and Execute): 

Exec PSLAO.sp_Drop_Object '#test';

-----------------------------------------------------------------------------------------------------------------------------------------
Modification History
-----------------------------------------------------------------------------------------------------------------------------------------
Revision      Author        Date                 Reason
------------- ---------     -------------------- -------------------------------------------------------------------------------------
00000         BBW			2020-08-05           Implemented
________________________________________________________________________________________________________________
*/
declare  @i int               =1 
		,@sql varchar(max)    =''
		--,@object varchar(25)='#test'
;
				  
if @object like '%#%' or @object like '%##%'
begin
	set @sql = 'if object_id(''tempdb..'+@object+''') is not null drop table '+@object+';';
	--print @sql;
	exec (@sql); 
end
else
	begin
		set @sql = 'if object_id('''+@object+''') is not null drop table '+@object+';';
		--print @sql;
		exec (@sql); 
	end
	;
GO

DECLARE @sql nvarchar(max)
	  , @exec nvarchar(max)
      , @sql_out varchar(max)
      , @destination_table varchar(4000)='[Test_Sandbox].[dbo].[WhoIsActive_Profile1]';

--this is our base sp_whoisactive query with all the parameterized goodies
Set @sql='Exec sp_whoisactive 
			 @get_plans = 1
			,@get_full_inner_text = 1 
			,@get_outer_command  = 1
			,@get_memory_info = 1
			,@sort_order = ''[blocked_session_count] desc''
			,@get_additional_info = 1
			,@get_task_info = 1  
			,@find_block_leaders = 1
			,@get_locks = 1'

If Object_id(@destination_table) is null
	Begin
		--generate the create command via the schema output method included in sp_whoisactive.
		Set @exec=@sql+'
			,@return_schema = 1
			,@schema = @sql_out Output
			;'
		exec sp_executeSQL @exec, N'@sql_out varchar(max) Output',@sql_out Output ;
		SET @sql_out = REPLACE(@sql_out, '<table_name>', @destination_table);--Print @sql_out
		EXEC(@sql_out);
	End;

--Now that our create table command has been handled, lets drop data into it.
Set @exec=@sql+'
	,@destination_table = '''+@destination_table+'''
	;'
exec sp_executeSQL @exec;


--For testing only, show the outputs
Set @exec='Select Dense_Rank() over ( order by collection_time desc) Poll_ID , * From '+@destination_table+';'
exec sp_executeSQL @exec;


--Select Dense_Rank() over ( order by collection_time desc) Poll_ID , * From [Test_Sandbox].[dbo].[WhoIsActive_Profile1];

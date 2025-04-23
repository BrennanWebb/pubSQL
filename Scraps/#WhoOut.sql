Drop table if exists tempdb.dbo.WhoOut;
DECLARE @s VARCHAR(MAX)

EXEC sp_WhoIsActive
    @get_additional_info = 1, @get_task_info = 2,
    @return_schema = 1,
    @schema = @s OUTPUT
SET @s = REPLACE(@s, '<table_name>', 'tempdb.dbo.WhoOut')
EXEC(@s);

EXEC sp_WhoIsActive
	 @get_additional_info = 1, @get_task_info = 2,
     @destination_table = 'tempdb.dbo.WhoOut'

Select DateDiff(hour, Start_time, collection_time),* 
From tempdb.dbo.WhoOut
Where DateDiff(minute, Start_time, collection_time)>=5 
and [Status] not in ('sleeping')

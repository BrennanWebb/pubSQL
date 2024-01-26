Use Apps
go
drop table if exists #test_table_data1
Select top 10 TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME

into #test_table_data1
From Common.information_schema.tables

drop table if exists #test_table_data2
Select top 10 TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME
into #test_table_data2
From Apps.information_schema.tables

drop table if exists #test_table_data3
Select top 10 TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME
into #test_table_data3
From [AGENT_HUB_DB].information_schema.tables

Declare @html varchar(max)
       ,@query varchar(1000)='Select * from #test_table_data1, Select * from #test_table_data2, Select * from #test_table_data3'
Exec [apps].[dbo].[test_temp] @query,@html=@html output
Select @html
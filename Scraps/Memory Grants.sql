select 
	mg.session_id, 
	mg.dop, 
	mg.request_time, 
	mg.grant_time, 
	(mg.requested_memory_kb *.001) as requested_memory_mb,  --Any SPID > 90GB is a red flag to me.  Server has 700 GB total in memory.
	(mg.granted_memory_kb * .001) as granted_memory_mb,  --If null, the spid is waiting for memory to become available.  Almost like a blocking chain of SPIDs trying to access locked pages.
	des.host_name, 
	des.login_name, 
	sj.name as JobName,
	a.stid,
	substring(t.text, 1, 1000) sql_query
from sys.dm_exec_query_memory_grants mg
inner join sys.dm_exec_sessions des on des.session_id = mg.session_id
cross apply sys.dm_exec_sql_text(mg.sql_handle) as t
 outer apply
 (
	select  jid = substring(des.program_name, 30, 34)
		  ,stid = Trim(Replace(Substring(des.program_name, 66, 10),')',''))
	where des.program_name like 'SQLAgent - TSQL JobStep%'
 ) a
  left join msdb.dbo.sysjobs sj on jid = CONVERT(VARCHAR(34),master.dbo.fn_VarbinToHexStr(sj.Job_ID)) 
where 1=1
and mg.session_id =888
--and requested_memory_kb >= '10000000' -- and (granted_memory_kb is null or granted_memory_kb = 0)
order by granted_memory_kb desc


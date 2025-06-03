Use Test

Go

Create View dbo.vw_Audit_DDL_Perm
as

With Action_Desc as (
SELECT 
    action_id,
    name AS action_description,
    string_agg(class_desc+' - '+containing_group_name Collate  SQL_Latin1_General_CP1_CI_AS,' , ') Within Group (Order by action_id) as action_group
FROM sys.dm_audit_actions
WHERE action_id IS NOT NULL
  AND name IS NOT NULL
  AND containing_group_name IS NOT NULL
Group by action_id,
    name

)

SELECT
a.event_time,
a.class_type,
ad.action_description,
a.session_server_principal_name AS executed_by,
a.server_instance_name [client],
a.database_name,
a.schema_name,
a.object_name,
a.object_id,
STRING_AGG(Cast(a.statement as varchar(max)), '') WITHIN GROUP (ORDER BY event_time DESC) AS statement   
FROM sys.fn_get_audit_file('C:\AuditLogs\*.sqlaudit', DEFAULT, DEFAULT) A
left join Action_Desc AD on A.action_id=AD.action_id
WHERE a.action_id IN ('CR', 'AL', 'DR') -- CREATE, ALTER, DROP
AND a.class_type NOT IN ('SC')        -- Exclude schema changes on first round
--and transaction_id=5759017
AND statement IS NOT NULL
Group by 
event_time,
class_type,
ad.action_description,
session_server_principal_name,
server_instance_name,
database_name,
schema_name,
object_name,
a.object_id
;
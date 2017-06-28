select pr.name as username
,l.loginname as loginname
,pr.type_desc as logintype
,pe.state_desc as permissionstate
,pe.permission_name as permissionname
,pe.class_desc as permissionclass
,o.name as objectname
,o.type_desc as objecttype
from sys.database_principals pr join sys.database_permissions pe on pe.grantee_principal_id = pr.principal_id
join sys.sysusers u on u.uid = pr.principal_id
left join sys.objects o on o.object_id = pe.major_id
left join master..syslogins l on u.sid = l.sid

/*
create user testuser without login
grant select on {object} to {testuser'

grant unmask to testuser
execute as user = 'testuser'

revert
*/
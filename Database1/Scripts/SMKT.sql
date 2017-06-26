SELECT count(s.ad_user) 
FROM security_access a, permissions p, user_roles_ad_vw v, user_group_staff_vw s 
WHERE a.app_name = p.programs and a.access_level = p.access_level and p.id in (v.role_1, v.role_2, v.role_3, v.role_4) 
and s.ad_group = v.user_logid 
and a.app_name='smkt' 
and s.ad_user='dka' 
and a.object_path='w_smkt_endors.m_smkt_endors.m_edit.m_update'

/* SMKT Queue related 
select *
from ms_ee_queue
order by post_dt desc

select convert(date, post_dt), count(1)
from ms_ee_queue
group by convert(date, post_dt)
order by 2 desc

select distinct(user_id)
from ms_ee_queue
where user_id like 'agl\%'
*/

/* SMKT Security related query
select top 1 1
--SELECT *
--SELECT COUNT(1)
FROM [das].[dbo].[user_group_staff_vw]
WHERE 
--ad_user = 'dka'
--and 
ad_group in ( 'APP_ONL_smkt_2_edit2', 'APP_ONL_smkt_3_legal2', 'APP_ONL_smkt_4_ops2')

  APP_ONL_Dev_User
select v.*
select distinct(user_logid)
FROM security_access a, permissions p, user_roles_ad_vw v 
WHERE a.app_name = p.programs and a.access_level = p.access_level and p.id in (v.role_1, v.role_2, v.role_3, v.role_4) 
and a.app_name='smkt' 
--and v.current_member = 1 
and a.object_path='w_smkt_endors.m_smkt_endors.m_edit.m_update'

select v.*
--select count(1)
--select distinct(user_logid)
FROM security_access a, permissions p, user_roles_ad_vw v 
WHERE a.app_name = p.programs and a.access_level = p.access_level and p.id in (v.role_1, v.role_2, v.role_3, v.role_4) 
and a.app_name='smkt' 
--and v.current_member = 1 
and a.object_path='w_smkt_endors.m_smkt_endors.m_edit.m_update'

select *
from ms_ee_queue


SELECT cn as ad_group, distinguishedName as dist_name
	FROM OPENQUERY (ADSI, '<LDAP://dc=agl,dc=com>;(&(objectClass=group)(cn=*APP_ONL*));cn, distinguishedName;subtree')


select sAMAccountName as ad_user
from openquery(ADSI, '<LDAP://dc=agl,dc=com>;(&(objectCategory=person)(objectClass=user)(memberOf=CN='',OU=ACL Groups,OU=AGL Groups,DC=agl,DC=com));sAMAccountName;subtree')

select staff_fstnm , *
from fsa_staff

select *
from user_group_staff_vw
where ad_user = 'dka'

SELECT        b.init AS ad_user, b.staff_fstnm AS ad_group, b.staff_lstnm AS init, b.staff_ext AS staff_fstnm, b.staff_addr AS staff_lstnm, b.staff_city AS staff_ext, 
                         b.staff_zip AS staff_addr, b.staff_spouse_nm AS staff_city, b.dept_cd AS staff_zip, b.pers_stat AS staff_spouse_nm, b.staff_st AS dept_cd, b.staff_phone AS pers_stat,
                          b.ip_address AS staff_st, b.fsa_site AS staff_phone, b.staff_function AS ip_address, b.staff_title AS fsa_site, b.staff_title2 AS staff_function, b.email AS staff_title, 
                         b.prefix AS staff_title2, b.staff_fax AS email, b.team_cd AS prefix, b.edms_dt AS staff_fax, b.active_directory_login AS team_cd, b.domain_controller AS edms_dt, 
                         b.round_robin AS active_directory_login, b.exclude_round_robin_flg AS domain_controller, b.sid AS round_robin, b.current_login AS exclude_round_robin_flg, 
                         b.SysStartTime AS sid, b.SysEndTime AS current_login, a.ad_user AS SysStartTime, a.ad_group AS SysEndTime
FROM            OPENQUERY([LOCAL], 'exec [das].dbo.ad_user_groups') AS a LEFT OUTER JOIN
                         dbo.fsa_staff AS b ON a.ad_user = b.active_directory_login

where ad_user = 'dka'

select IS_MEMBER('AGL\APP_ONL_Dev_User')
select IS_MEMBER('AGL\APP_ONL_smkt_2_edit')
/*
[PrincipalPermission(SecurityAction.Demand, Role = "APP_ONL_smkt_2_edit")]
        [PrincipalPermission(SecurityAction.Demand, Role = "APP_ONL_smkt_3_legal")]
        [PrincipalPermission(SecurityAction.Demand, Role = "APP_ONL_smkt_4_ops")]
		*/

IF IS_ROLEMEMBER ('db_datareader') = 1  
   print 'Current user is a member of the db_datareader role'  
ELSE IF IS_ROLEMEMBER ('db_datareader') = 0  
   print 'Current user is NOT a member of the db_datareader role'  
ELSE IF IS_ROLEMEMBER ('db_datareader') IS NULL  
   print 'ERROR: The database role specified is not valid.';  

select IS_ROLEMEMBER('fsa_online_read_only_role', 'agl\dka')
select IS_ROLEMEMBER('APP_ONL_Dev_User')
select IS_ROLEMEMBER('db_datareader', 'agl\llasek')
select IS_ROLEMEMBER('smkt_entry_role', 'agl\llasek')
select IS_ROLEMEMBER('smkt_entry_role', 'agl\dka')
llasek 
fsa_online_read_only_role

smkt_entry_role
fsa_online_read_only_role
fsa_online_role

SELECT SUSER_ID('sa'); 

SELECT r.name 
  FROM sys.server_role_members AS m
  INNER JOIN sys.server_principals AS l
    ON m.member_principal_id = l.principal_id
  INNER JOIN sys.server_principals AS r
    ON m.role_principal_id = r.principal_id
  WHERE l.name = N'agl\dka';


SELECT g.[name], p.[name] 
FROM sys.database_principals g inner join sys.database_role_members r on g.principal_id = r.role_principal_id
inner join sys.database_principals p on p.principal_id = r.member_principal_id 
WHERE (g.[type] = 'R') and (p.[type] = 'G' OR p.type = 'U') and p.name like '%APP_ONL%' and g.name not like 'db_%' and g.name not like 'test%';
APP_ONL_Dev_User
 select *
 from sys.database_principals 
 where type in ('G','U')

 select *
 from sys.database_role_members


 SELECT DP1.name AS DatabaseRoleName,   
   isnull (DP2.name, 'No members') AS DatabaseUserName   
 FROM sys.database_role_members AS DRM  
 RIGHT OUTER JOIN sys.database_principals AS DP1  
   ON DRM.role_principal_id = DP1.principal_id  
 LEFT OUTER JOIN sys.database_principals AS DP2  
   ON DRM.member_principal_id = DP2.principal_id  
WHERE DP1.type = 'R'
--and DP1.name = 'db_owner'
--and DP1.name like '%smkt%'
and DP2.name like '%APP_ONL_Dev%'
order by 1
*/
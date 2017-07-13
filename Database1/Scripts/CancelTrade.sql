select ee_status_reason_cd, comment, ee_correlation_id, ee_order_id, ee_action,ee_status,ee_party_id, req_status,req_init_flg,capac_used_dt,capac_return_dt,ee_capac_used_dt,capac_return_dt,risk_no,pnum,*
from sm_request
where
 --req_id = 23747
revised_dt >= '7/13/2017'
--and 
--req_init_flg = 'T'

select req_id, revised_dt, revised_by, orig_cusip,comment,req_status
from sm_request
where
req_id = 23749
and
revised_dt >= '7/13/2017'

select req_status, *
from sm_request for system_time all
where req_id = 23743
order by SysStartTime

/*
select *
from enum_code
where field_name = 'ee_reason_code'

exec ee_request '28582227', '01', '1','B',1,'F',1500,'83710DBK3','19000101',231,3.21,'5197-5023000262-assureg1'  -- new trade
--exec ee_insure 23818
exec ee_request '28582227', '01', '1','B',9,'C',1500,'83710DBK3','19000101',0,0,'5197-5023000262-assureg1'  -- cancel trade 

-- ALTER TABLE sm_request enable TRIGGER trg_idu_sm_request
-- update sm_request set req_status = 'F' where req_id = 23737

select *
from risk_capac_adjust
order by adj_dt desc
where req_id = 23741

select req_status, *
from sm_request for system_time all
where req_id = 23741 -- 23815 --23824  --23808 
order by SysStartTime

declare @id int = 23808
set @id = 23740
select req_status, req_status_dt,comment, *
from history.sm_request
where req_id = @id
union all
select req_status, req_status_dt, comment,*
from sm_request
where req_id = @id

select *
--from cusip_db.dbo.cusip_smkt_price
from cusip_db.dbo.tmc_price_capacity_all_file
--order by avail_cap
where cusip = '003392GB7'
003392GB7

select *
from sm_request
where ee_correlation_id = 741265

select ee_status_reason_cd, comment, ee_correlation_id, ee_order_id, ee_action,ee_status,ee_party_id, req_status,*
from sm_request
where --req_id = 23808
revised_dt >= '7/10/2017'
--revised_dt >= '7/5/2017' and revised_dt < '7/6/2017'
--and revised_dt > '7/7/2017'
--AND revised_by = 'EE'

union all
select ee_status_reason_cd, comment, ee_correlation_id, ee_order_id,ee_action,ee_status, ee_party_id,*
from sm_request
where 
revised_dt between '6/1/17' and '7/5/2017'
and 
revised_by = 'EE'

select *
from ms_ee_queue
where 
post_dt >= '6/1/2017'
and 
user_id = 'agl\app_tmc_service_p'
--order by post_dt desc

--select ee_status_reason_cd, comment, *
--from sm_request
--where 
--revised_dt between '1/1/17' and '6/1/2017'

--and 
--revised_by = 'EE'

select *
from sm_request
where ee_correlation_id = 28464678

select max(value) FROM [master].sys.fn_listextendedproperty(default, default, default, default, default, default, default) WHERE [name] = 'Environment' 

Select case when datepart(dw,Dateadd(dd,3,getdate())) = 1 then dateadd(dd,4,getdate()) 
                              when  datepart(dw,Dateadd(dd,3,getdate())) = 7 then dateadd(dd,5,getdate())
                         else dateadd(dd,3,getdate())end

select art_tick, div_phone
,area_code + substring(div_phone,1,3) + substring(div_phone,5,9)
,'TheMuniCenter'
 from div 
where UPPER(comp_nm) like'THEMUNICENTER%'

select *
from div

select * from cusip_db.dbo.m_issues where cusip = '777543SB6'

select office_loc, r.*
	from risk r, risk_cap_chrg_vw b
   where     r.risk_no = 304530
         and r.risk_no = b.risk_no 

--select *
--from cusip_db.dbo.tmc_email_config 

--from User_Notification

select *
from sm_ext for system_time all
where orig_cusip = '646139ZA6'

select *
from sm_ext
order by 1, 2, 3, 4

select distinct(req_status)
from sm_request

SELECT count(*) as rCount   FROM ms_ee_queue  WHERE queue_id = '586145L51' AND msg_flag = 'S'

select *
from ms_ee_queue
where 
--queue_id = '586145L51' 
--AND 
msg_flag = 'S'
*/


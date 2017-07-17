/*
UPDATE history.pf_issue_maturities 
SET SysStartTime = DATEADD(hh,CASE WHEN SysStartTime >= dbo.GetDstStart(YEAR(SysStartTime)) AND SysStartTime < dbo.GetDstEnd(YEAR(SysStartTime)) THEN 4 ELSE 5 END,SysStartTime)
,SysEndTime = DATEADD(hh,CASE WHEN SysEndTime >= dbo.GetDstStart(YEAR(SysEndTime)) AND SysEndTime < dbo.GetDstEnd(YEAR(SysEndTime)) THEN 4 ELSE 5 END,SysEndTime);
go

ALTER TABLE dbo.pf_issue_maturities DROP PERIOD FOR SYSTEM_TIME;
go

--UPDATE dbo.pf_issue_maturities SET SysStartTime = c.SysEndTime
--FROM history.pf_issue_maturities a INNER JOIN dbo.pf_issue_maturities c
--ON a.sp_record_id = c.sp_record_id AND a.entity_id = c.entity_id
--INNER JOIN (SELECT sp_record_id,entity_id,MAX(SysEndTime)et FROM history.pf_issue_maturities GROUP BY sp_record_id,entity_id)b
--ON a.sp_record_id = b.sp_record_id AND a.entity_id = b.entity_id;
--UPDATE dbo.pf_issue_maturities SET SysStartTime = b.et
--FROM dbo.pf_issue_maturities a INNER JOIN 
--(SELECT sp_record_id,entity_id,MAX(SysEndTime)et FROM history.pf_issue_maturities GROUP BY sp_record_id,entity_id) b
--ON a.sp_record_id = b.sp_record_id AND a.entity_id = b.entity_id;

UPDATE dbo.pf_issue_maturities SET SysStartTime = b.SysStartTime
FROM dbo.pf_issue_maturities a INNER JOIN history.pf_issue_maturities b
ON a.sp_record_id = b.sp_record_id AND a.entity_id = b.entity_id
WHERE YEAR(b.SysEndTime) = 9999
go

DELETE FROM history.pf_issue_maturities WHERE YEAR(SysEndTime) = 9999
go

ALTER TABLE dbo.pf_issue_maturities ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);
go

ALTER TABLE dbo.pf_issue_maturities SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.pf_issue_maturities, DATA_CONSISTENCY_CHECK=ON));
go
-----------


select sp_record_id, entity_id, SysStartTime, SysEndTime, 1
from pf_issue_maturities
union
select sp_record_id, entity_id, SysStartTime, SysEndTime, 0
from history.pf_issue_maturities
order by 1, 2, 3 desc,4 desc


--select count(1)
--from history.pf_issue_maturities 

--UPDATE dbo.pf_issue_maturities SET SysStartTime = b.et
select SysStartTime, SysEndTime, b.et
FROM dbo.pf_issue_maturities a INNER JOIN 
(SELECT sp_record_id,entity_id,MAX(SysEndTime)et FROM history.pf_issue_maturities GROUP BY sp_record_id,entity_id) b
ON a.sp_record_id = b.sp_record_id AND a.entity_id = b.entity_id;

select a.SysStartTime, a.SysEndTime, b.SysStartTime, b.SysEndTime
FROM dbo.pf_issue_maturities a INNER JOIN history.pf_issue_maturities b
ON a.sp_record_id = b.sp_record_id AND a.entity_id = b.entity_id
WHERE year(b.SysEndTime) = 9999 and a.SysStartTime != b.SysStartTime

--SELECT * INTO _p from history.pf_issue_maturities
--SELECT * INTO _p2 from history.pf_issue_maturities

-- select count(1) from history.pf_issue_maturities

--INSERT INTO history.pf_issue_maturities select * from dbo._p2
-- select * from dbo. pf_issue_maturities where YEAR(h_end_date) != 9999
-- TRUNCATE TABLE history.pf_issue_maturities


--select * into _pf from dbo.pf_issue_maturities

UPDATE dbo.pf_issue_maturities SET SysStartTime = das.dbo.ToUTC(SysStartTime)


------------------
UPDATE dbo.pf_issue_maturities SET SysStartTime = das.dbo.ToUTC(SysStartTime);

UPDATE history.pf_issue_maturities SET SysEndTime = c.SysStartTime
FROM history.pf_issue_maturities a INNER JOIN pf_issue_maturities c
ON a.sp_record_id = c.sp_record_id AND a.entity_id = c.entity_id
INNER JOIN (SELECT sp_record_id,entity_id,MAX(SysStartTime)st, MAX(SysEndTime)et FROM history.pf_issue_maturities GROUP BY sp_record_id,entity_id)b
ON a.sp_record_id = b.sp_record_id AND a.entity_id = b.entity_id AND a.SysStartTime = b.st AND a.SysEndTime = b.et;

ALTER TABLE dbo.pf_issue_maturities ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);

ALTER TABLE dbo.pf_issue_maturities SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.pf_issue_maturities, DATA_CONSISTENCY_CHECK=ON));
--------------------

UPDATE dbo.setamper SET SysStartTime = das.dbo.ToUTC(SysStartTime);

DECLARE @t Datetime2;
SELECT @t = MAX(SysStartTime) FROM setamper;
UPDATE history.setamper SET SysEndTime = @t
FROM history.setamper a
WHERE a.SysEndTime = (SELECT MAX(b.SysEndTime) FROM history.setamper b);

ALTER TABLE dbo.setamper ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);

ALTER TABLE dbo.setamper SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE=history.[setamper]));

-------------------------------------------
/*
select a.*, (case when b.h_begin_date is null then getdate() else b.h_begin_date end) SysStartTime,'9999-12-31 23:59:59.999' SysEndTime 
from dbo.risk a left join h_das.dbo.risk b
on a.risk_no = b.risk_no and year(b.h_end_date) = 9999
*/
ALTER TABLE dbo.risk SET (SYSTEM_VERSIONING = OFF); 
go

ALTER TABLE dbo.risk DROP PERIOD FOR SYSTEM_TIME;
go

UPDATE dbo.risk SET SysStartTime = das.dbo.ToUTC(SysStartTime);
go

UPDATE history.risk SET SysEndTime = c.SysStartTime
FROM history.risk a INNER JOIN dbo.risk c
ON a.risk_no = c.risk_no
INNER JOIN (SELECT risk_no, MAX(SysStartTime)st, MAX(SysEndTime)se
FROM history.risk GROUP BY risk_no) b
ON a.risk_no = b.risk_no AND a.SysStartTime = b.st AND a.SysEndTime = b.se;
go

ALTER TABLE dbo.risk ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);
go

ALTER TABLE dbo.risk SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE=history.risk, DATA_CONSISTENCY_CHECK=ON));
go
-------------------------------------------------------------------------
/*
select a.*,(case when b.h_begin_date is null then getdate() else b.h_begin_date end) SysStartTime,'9999-12-31 23:59:59.999' SysEndTime
from dbo.stream_risk_free_rates a left join (select stream_no, max(h_begin_date) h_begin_date from h_das.dbo.stream_risk_free_rates where year(h_end_date) = 9999 group by stream_no) b
on a.stream_no = b.stream_no 
*/
ALTER TABLE dbo.stream_risk_free_rates SET (SYSTEM_VERSIONING = OFF); 
go

ALTER TABLE dbo.stream_risk_free_rates DROP PERIOD FOR SYSTEM_TIME;
go

UPDATE dbo.stream_risk_free_rates SET SysStartTime = das.dbo.ToUTC(SysStartTime);
go

ALTER TABLE dbo.stream_risk_free_rates ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);
go

ALTER TABLE dbo.stream_risk_free_rates SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE=history.stream_risk_free_rates, DATA_CONSISTENCY_CHECK=ON));
go
-------------------------------------------------------------------------------
ALTER TABLE dbo.risk_rtg_transfer SET (SYSTEM_VERSIONING = OFF); 
go

ALTER TABLE dbo.risk_rtg_transfer DROP PERIOD FOR SYSTEM_TIME;
go

UPDATE dbo.risk_rtg_transfer SET SysStartTime = das.dbo.ToUTC(SysStartTime);
go

/*
select a.*, (case when b.h_begin_date is null then getdate() else b.h_begin_date end) SysStartTime,'9999-12-31 23:59:59.999' SysEndTime
from dbo.risk_rtg_transfer a left join h_das.dbo.risk_rtg_transfer b
on a.risk_no = b.risk_no and a.log_dt = b.log_dt and year(b.h_end_date) = 9999
*/

ALTER TABLE dbo.risk_rtg_transfer ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);
go

ALTER TABLE dbo.risk_rtg_transfer SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.risk_rtg_transfer, DATA_CONSISTENCY_CHECK=ON));
go
----------------------------------------------------------------------------------------

ALTER TABLE dbo.mrds_entity_risk SET (SYSTEM_VERSIONING = OFF); 
go

ALTER TABLE dbo.mrds_entity_risk DROP PERIOD FOR SYSTEM_TIME;
go

/*
select a.*, (case when b.h_begin_date is null then getdate() else b.h_begin_date end) SysStartTime,'9999-12-31 23:59:59.999' SysEndTime
from dbo.mrds_entity_risk a left join h_das.dbo.mrds_entity_risk b
ON a.md_issuer_no = b.md_issuer_no AND a.debt_class_key = b.debt_class_key AND a.seniority_key = b.seniority_key AND a.risk_no = b.risk_no AND a.link_type = b.link_type
and year(b.h_end_date) = 9999
*/

UPDATE dbo.mrds_entity_risk SET SysStartTime = das.dbo.ToUTC(SysStartTime);
go

ALTER TABLE dbo.mrds_entity_risk ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);
go

ALTER TABLE dbo.mrds_entity_risk SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.mrds_entity_risk, DATA_CONSISTENCY_CHECK=ON));
go
-----------------------------------------------------------------
ALTER TABLE dbo.mrds SET (SYSTEM_VERSIONING = OFF); 
go

ALTER TABLE dbo.mrds DROP PERIOD FOR SYSTEM_TIME;
go

/*
select a.*,(case when b.h_begin_date is null then getdate() else b.h_begin_date end) SysStartTime,'9999-12-31 23:59:59.999' SysEndTime
from dbo.mrds a left join (select md_unique_no, batch_number, max(h_begin_date) h_begin_date from h_das.dbo.mrds where year(h_end_date) = 9999 group by md_unique_no, batch_number) b
on a.md_unique_no = b.md_unique_no AND a.batch_number = b.batch_number
*/

UPDATE dbo.mrds SET SysStartTime = das.dbo.ToUTC(SysStartTime);
go

ALTER TABLE dbo.mrds ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);
go

ALTER TABLE dbo.mrds SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.mrds, DATA_CONSISTENCY_CHECK=ON));
go
--------------------------------------------------------
ALTER TABLE dbo.pf_entity_risk SET (SYSTEM_VERSIONING = OFF); 
go

ALTER TABLE dbo.pf_entity_risk DROP PERIOD FOR SYSTEM_TIME;
go

/*
select a.*,(case when b.h_begin_date is null then getdate() else b.h_begin_date end) SysStartTime,'9999-12-31 23:59:59.999' SysEndTime
from dbo.pf_entity_risk a left join 
(select entity_id, municipal_category_code, municipal_security_code, risk_no,link_type, max(h_begin_date) h_begin_date from h_das.dbo.pf_entity_risk where year(h_end_date) = 9999 
group by entity_id, municipal_category_code, municipal_security_code, risk_no,link_type) b
ON a.entity_id = b.entity_id AND a.municipal_category_code = b.municipal_category_code AND a.municipal_security_code = b.municipal_security_code 
AND a.risk_no = b.risk_no AND a.link_type = b.link_type;
*/
UPDATE dbo.pf_entity_risk SET SysStartTime = das.dbo.ToUTC(SysStartTime);
go

ALTER TABLE dbo.pf_entity_risk ADD PERIOD FOR SYSTEM_TIME(sysstartTime, sysendtime);
go

ALTER TABLE dbo.pf_entity_risk SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.pf_entity_risk, DATA_CONSISTENCY_CHECK=ON));
go
*/
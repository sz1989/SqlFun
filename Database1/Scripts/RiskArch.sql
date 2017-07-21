/*
BEGIN TRAN;    
/*Create 5 montly partition function*/  
CREATE PARTITION FUNCTION fn_Partition_risk_By_SysEndTime (datetime2(3))   
AS RANGE LEFT FOR VALUES 
(N'2016-10-31T23:59:59.999',N'2016-11-30T23:59:59.999',N'2016-12-31T23:59:59.999',N'2017-1-31T23:59:59.999',N'2017-2-28T23:59:59.999');
  
/*Create partition scheme*/  
CREATE PARTITION SCHEME sch_Partition_risk_By_SysEndTime AS PARTITION fn_Partition_risk_By_SysEndTime   
TO ([HIST], [HIST], [HIST], [HIST], [HIST], [HIST]);  
                        
/*Re-create index to be partition-aligned with the partitioning schema*/  
CREATE CLUSTERED INDEX [ix_risk_history] ON history.risk
(  [SysEndTime] ASC,  [SysStartTime] ASC  )  
            WITH   
                        (PAD_INDEX = OFF  
                        , STATISTICS_NORECOMPUTE = OFF  
                        , SORT_IN_TEMPDB = OFF  
                        , DROP_EXISTING = ON  
                        , ONLINE = OFF  
                        , ALLOW_ROW_LOCKS = ON  
                        , ALLOW_PAGE_LOCKS = ON  
                        , DATA_COMPRESSION = PAGE)  
            ON [sch_Partition_risk_By_SysEndTime] ([SysEndTime]);
COMMIT;  
*/

/*
BEGIN TRANSACTION  
-- drop table staging.risk

/*(1)  Create staging table */  
CREATE TABLE staging.risk  
(  
    [risk_no]                  BIGINT           NOT NULL,
    [abbr]                     VARCHAR (35)     NULL,
    [name]                     VARCHAR (140)    NULL,
    [art_ccd]                  BIGINT           NULL,
    [sp_sect]                  CHAR (4)         NULL,
    [md_sect]                  CHAR (4)         NULL,
    [state]                    CHAR (2)         NULL,
    [risk_type]                CHAR (1)         NULL,
    [load_dt]                  DATETIME2 (3)    NULL,
    [fisc_mth]                 SMALLINT         NULL,
    [fisc_day]                 SMALLINT         NULL,
    [cap]                      MONEY            NULL,
    [sm_cap]                   MONEY            NULL,
    [sm_rate]                  FLOAT (53)       NULL,
    [sm_elig]                  CHAR (1)         NULL,
    [chg_dt]                   DATETIME2 (3)    NULL,
    [departm]                  CHAR (4)         NULL,
    [analyst]                  CHAR (3)         NULL,
    [supp_uw]                  CHAR (3)         NULL,
    [sp_cat]                   CHAR (1)         NULL,
    [cap_chrg]                 FLOAT (53)       NULL,
    [cap_chbas]                CHAR (1)         NULL,
    [cap_chstat]               CHAR (1)         NULL,
    [cap_cr_pct]               FLOAT (53)       NULL,
    [adj_capchg]               MONEY            NULL,
    [naic_ctg]                 CHAR (3)         NULL,
    [sngl_ctg]                 CHAR (1)         NULL,
    [aggr_ctg]                 CHAR (4)         NULL,
    [cres_ctg]                 CHAR (4)         NULL,
    [surv_ctg]                 CHAR (1)         NULL,
    [fsa_rtg]                  CHAR (2)         NULL,
    [sp_rtg]                   CHAR (2)         NULL,
    [md_rtg]                   CHAR (2)         NULL,
    [sp_shadow]                CHAR (1)         NULL,
    [md_shadow]                CHAR (1)         NULL,
    [adj_capac]                MONEY            NULL,
    [mis_chk]                  CHAR (1)         NULL,
    [ipm_chk]                  CHAR (1)         NULL,
    [cur_chk]                  CHAR (1)         NULL,
    [leg_chk]                  CHAR (1)         NULL,
    [class]                    CHAR (3)         NULL,
    [elig_dt]                  DATETIME2 (3)    NULL,
    [inelig_dt]                DATETIME2 (3)    NULL,
    [par_ins]                  MONEY            NULL,
    [par_grs]                  MONEY            NULL,
    [ds_ins]                   MONEY            NULL,
    [ds_grs]                   MONEY            NULL,
    [asm_par_ins]              MONEY            NULL,
    [asm_ds_ins]               MONEY            NULL,
    [final_maturity]           DATETIME2 (3)    NULL,
    [smkt_par_ins]             MONEY            NULL,
    [ipm_sect]                 CHAR (4)         NULL,
    [afgi_sect]                CHAR (4)         NULL,
    [fips_cd]                  CHAR (5)         NULL,
    [smkt_par_grs]             MONEY            NULL,
    [current_rempar_grs]       MONEY            NULL,
    [current_rempar_net]       MONEY            NULL,
    [lastq_net_par]            MONEY            NULL,
    [lastq_grs_par]            MONEY            NULL,
    [_max_matdt]               DATETIME2 (3)    NULL,
    [current_ds_grs]           MONEY            NULL,
    [coll_amount]              MONEY            NULL,
    [coll_as_of_date]          DATETIME2 (3)    NULL,
    [current_ds_net]           MONEY            NULL,
    [as_of_date]               DATETIME2 (3)    NULL,
    [calc_pv]                  CHAR (1)         NULL,
    [smcap_chg_dt]             DATETIME2 (3)    NULL,
    [net_cap_chrg]             NUMERIC (14, 11) NULL,
    [sp_aaa_bbb_minus_gap]     NUMERIC (14, 11) NULL,
    [sp_excess_loss_coverage]  NUMERIC (14, 11) NULL,
    [asset_backed_flg]         CHAR (1)         NULL,
    [lien]                     CHAR (2)         NULL,
    [sm_irr]                   FLOAT (53)       NULL,
    [sm_daily_capacity]        MONEY            NULL,
    [sm_munc_irr]              FLOAT (53)       NULL,
    [sm_munc_price]            REAL             NULL,
    [reinsurance_fg]           CHAR (1)         NULL,
    [othr_spcl_consid_flg]     CHAR (1)         NULL,
    [cap_constraint_flg]       CHAR (1)         NULL,
    [dac_flg]                  CHAR (1)         NULL,
    [sov_cap_chrg]             NUMERIC (14, 11) NULL,
    [strike_price]             REAL             NULL,
    [dexia_spcl_party_flg]     CHAR (1)         NULL,
    [business_line]            CHAR (4)         NULL,
    [sm_appr_cap]              MONEY            NULL,
    [sm_written_cap]           MONEY            NULL,
    [sm_adj_amt_cap]           MONEY            NULL,
    [manual_price_flg]         CHAR (1)         NULL,
    [fsa_cat]                  CHAR (1)         NULL,
    [fermat_id]                NUMERIC (12)     NULL,
    [fermat_name]              VARCHAR (32)     NULL,
    [create_dt]                DATETIME2 (3)    NULL,
    [servicer_id]              CHAR (3)         NULL,
    [md_rtg_model]             CHAR (2)         NULL,
    [edms_dt]                  DATETIME2 (3)    NULL,
    [created_dt]               DATETIME2 (3)    NULL,
    [reins_cap_constraint]     CHAR (1)         NULL,
    [expanded_limit_flg]       CHAR (1)         NULL,
    [underlying_risk_no]       INT              NULL,
    [revenue_stream]           BIGINT           NULL,
    [sp_rtg_effective_dt]      DATETIME2 (3)    NULL,
    [md_rtg_effective_dt]      DATETIME2 (3)    NULL,
    [sm_capac_appr_dt]         DATETIME2 (3)    NULL,
    [ee_appr_capac]            MONEY            NULL,
    [ee_written_cap]           MONEY            NULL,
    [ee_adj_amt_cap]           MONEY            NULL,
    [ee_capac_appr_dt]         DATETIME2 (3)    NULL,
    [shelf_avail_capac]        MONEY            NULL,
    [ee_avail_capac]           MONEY            NULL,
    [risk_ctg]                 CHAR (1)         NULL,
    [ambac_rtg]                CHAR (2)         NULL,
    [fgic_rtg]                 CHAR (2)         NULL,
    [mbia_rtg]                 CHAR (2)         NULL,
    [ambac_rtg_dt]             DATETIME2 (3)    NULL,
    [fgic_rtg_dt]              DATETIME2 (3)    NULL,
    [mbia_rtg_dt]              DATETIME2 (3)    NULL,
    [disclosure_name]          VARCHAR (140)    NULL,
    [aggr_ctg_md]              CHAR (4)         NULL,
    [mac_cap_constraint_flg]   CHAR (1)         NULL,
    [mac_manual_price_flg]     CHAR (1)         NULL,
    [mac_sm_irr]               FLOAT (53)       NULL,
    [mac_sm_rate]              FLOAT (53)       NULL,
    [sp_transfer_flg]          VARCHAR (1)      NOT NULL,
    [rtg_sp_etl_cd]            INT              NULL,
    [rtg_sp_etl_dt]            DATETIME2 (3)    NULL,
    [sp_transfer_flg_comments] VARCHAR (255)    NULL,
    [sp_transfer_flg_dt]       DATETIME2 (3)    NULL,
    [sp_transfer_flg_id]       CHAR (3)         NULL,
    [md_transfer_flg]          VARCHAR (1)      NOT NULL,
    [rtg_md_etl_cd]            INT              NULL,
    [rtg_md_etl_dt]            DATETIME2 (3)    NULL,
    [md_transfer_flg_comments] VARCHAR (255)    NULL,
    [md_transfer_flg_dt]       DATETIME2 (3)    NULL,
    [md_transfer_flg_id]       CHAR (3)         NULL,
    [current_login]            NVARCHAR (128)   NULL,
    [SysStartTime]             DATETIME2 (3)    NOT NULL,
    [SysEndTime]               DATETIME2 (3)    NOT NULL  
) ON [HIST] WITH ( DATA_COMPRESSION = PAGE )  
  
/*(2) Create index on the same filegroups as the partition that will be switched out*/  
CREATE CLUSTERED INDEX ix_staging_risk ON staging.risk  
([SysEndTime] ASC, [SysStartTime] ASC) WITH (PAD_INDEX = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON ) ON [HIST]  
  
 /*(3) Create constraints matching the partition that will be switched out*/  
ALTER TABLE staging.risk WITH CHECK ADD CONSTRAINT chk_staging_risk_partition_1 CHECK ([SysEndTime]<=N'2016-10-31T23:59:59.999')  
ALTER TABLE staging.risk CHECK CONSTRAINT [chk_risk_setamper_partition_1]  
  
/*(4) Switch partition to staging table*/  
ALTER TABLE history.risk SWITCH PARTITION 1 TO staging.risk   
WITH (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 0 MINUTES, ABORT_AFTER_WAIT = NONE))  
  
/*(5) [Commented out] Optionally archive the data and drop staging table  
INSERT INTO [ArchiveDB].[dbo].[DepartmentHistory]   
SELECT * FROM [dbo].[staging_DepartmentHistory_September_2015];  
DROP TABLE [dbo].[staging_DepartmentHIstory_September_2015];  
*/  
  
/*(6) merge range to move lower boundary one month ahead*/  
ALTER PARTITION FUNCTION [fn_Partition_setamper_By_SysEndTime]() MERGE RANGE(N'2016-10-31T23:59:59.999')  
  
/*(7) Create new empty partition for "April and after" by creating new boundary point and specifying NEXT USED file group*/  
ALTER PARTITION SCHEME [sch_Partition_setamper_By_SysEndTime] NEXT USED [HIST]  
ALTER PARTITION FUNCTION [fn_Partition_setamper_By_SysEndTime]() SPLIT RANGE(N'2017-01-31T23:59:59.999')    
COMMIT TRANSACTION  



/* analyize hist table
select year(SysEndTime),month(SysEndTime), count(1)
from history.risk
group by year(SysEndTime), month(SysEndTime)
order by 1, 2

select max(SysEndTime), min(SysEndTime) from history.risk
select * into _risk from history.risk
*/

/*
--- Sqls to Reset make sure filegroup: HIST exist
ALTER TABLE dbo.risk SET (SYSTEM_VERSIONING = OFF);
drop table history.risk;

CREATE TABLE history.risk (
    [risk_no]                  BIGINT           NOT NULL,
    [abbr]                     VARCHAR (35)     NULL,
    [name]                     VARCHAR (140)    NULL,
    [art_ccd]                  BIGINT           NULL,
    [sp_sect]                  CHAR (4)         NULL,
    [md_sect]                  CHAR (4)         NULL,
    [state]                    CHAR (2)         NULL,
    [risk_type]                CHAR (1)         NULL,
    [load_dt]                  DATETIME2 (3)    NULL,
    [fisc_mth]                 SMALLINT         NULL,
    [fisc_day]                 SMALLINT         NULL,
    [cap]                      MONEY            NULL,
    [sm_cap]                   MONEY            NULL,
    [sm_rate]                  FLOAT (53)       NULL,
    [sm_elig]                  CHAR (1)         NULL,
    [chg_dt]                   DATETIME2 (3)    NULL,
    [departm]                  CHAR (4)         NULL,
    [analyst]                  CHAR (3)         NULL,
    [supp_uw]                  CHAR (3)         NULL,
    [sp_cat]                   CHAR (1)         NULL,
    [cap_chrg]                 FLOAT (53)       NULL,
    [cap_chbas]                CHAR (1)         NULL,
    [cap_chstat]               CHAR (1)         NULL,
    [cap_cr_pct]               FLOAT (53)       NULL,
    [adj_capchg]               MONEY            NULL,
    [naic_ctg]                 CHAR (3)         NULL,
    [sngl_ctg]                 CHAR (1)         NULL,
    [aggr_ctg]                 CHAR (4)         NULL,
    [cres_ctg]                 CHAR (4)         NULL,
    [surv_ctg]                 CHAR (1)         NULL,
    [fsa_rtg]                  CHAR (2)         NULL,
    [sp_rtg]                   CHAR (2)         NULL,
    [md_rtg]                   CHAR (2)         NULL,
    [sp_shadow]                CHAR (1)         NULL,
    [md_shadow]                CHAR (1)         NULL,
    [adj_capac]                MONEY            NULL,
    [mis_chk]                  CHAR (1)         NULL,
    [ipm_chk]                  CHAR (1)         NULL,
    [cur_chk]                  CHAR (1)         NULL,
    [leg_chk]                  CHAR (1)         NULL,
    [class]                    CHAR (3)         NULL,
    [elig_dt]                  DATETIME2 (3)    NULL,
    [inelig_dt]                DATETIME2 (3)    NULL,
    [par_ins]                  MONEY            NULL,
    [par_grs]                  MONEY            NULL,
    [ds_ins]                   MONEY            NULL,
    [ds_grs]                   MONEY            NULL,
    [asm_par_ins]              MONEY            NULL,
    [asm_ds_ins]               MONEY            NULL,
    [final_maturity]           DATETIME2 (3)    NULL,
    [smkt_par_ins]             MONEY            NULL,
    [ipm_sect]                 CHAR (4)         NULL,
    [afgi_sect]                CHAR (4)         NULL,
    [fips_cd]                  CHAR (5)         NULL,
    [smkt_par_grs]             MONEY            NULL,
    [current_rempar_grs]       MONEY            NULL,
    [current_rempar_net]       MONEY            NULL,
    [lastq_net_par]            MONEY            NULL,
    [lastq_grs_par]            MONEY            NULL,
    [_max_matdt]               DATETIME2 (3)    NULL,
    [current_ds_grs]           MONEY            NULL,
    [coll_amount]              MONEY            NULL,
    [coll_as_of_date]          DATETIME2 (3)    NULL,
    [current_ds_net]           MONEY            NULL,
    [as_of_date]               DATETIME2 (3)    NULL,
    [calc_pv]                  CHAR (1)         NULL,
    [smcap_chg_dt]             DATETIME2 (3)    NULL,
    [net_cap_chrg]             NUMERIC (14, 11) NULL,
    [sp_aaa_bbb_minus_gap]     NUMERIC (14, 11) NULL,
    [sp_excess_loss_coverage]  NUMERIC (14, 11) NULL,
    [asset_backed_flg]         CHAR (1)         NULL,
    [lien]                     CHAR (2)         NULL,
    [sm_irr]                   FLOAT (53)       NULL,
    [sm_daily_capacity]        MONEY            NULL,
    [sm_munc_irr]              FLOAT (53)       NULL,
    [sm_munc_price]            REAL             NULL,
    [reinsurance_fg]           CHAR (1)         NULL,
    [othr_spcl_consid_flg]     CHAR (1)         NULL,
    [cap_constraint_flg]       CHAR (1)         NULL,
    [dac_flg]                  CHAR (1)         NULL,
    [sov_cap_chrg]             NUMERIC (14, 11) NULL,
    [strike_price]             REAL             NULL,
    [dexia_spcl_party_flg]     CHAR (1)         NULL,
    [business_line]            CHAR (4)         NULL,
    [sm_appr_cap]              MONEY            NULL,
    [sm_written_cap]           MONEY            NULL,
    [sm_adj_amt_cap]           MONEY            NULL,
    [manual_price_flg]         CHAR (1)         NULL,
    [fsa_cat]                  CHAR (1)         NULL,
    [fermat_id]                NUMERIC (12)     NULL,
    [fermat_name]              VARCHAR (32)     NULL,
    [create_dt]                DATETIME2 (3)    NULL,
    [servicer_id]              CHAR (3)         NULL,
    [md_rtg_model]             CHAR (2)         NULL,
    [edms_dt]                  DATETIME2 (3)    NULL,
    [created_dt]               DATETIME2 (3)    NULL,
    [reins_cap_constraint]     CHAR (1)         NULL,
    [expanded_limit_flg]       CHAR (1)         NULL,
    [underlying_risk_no]       INT              NULL,
    [revenue_stream]           BIGINT           NULL,
    [sp_rtg_effective_dt]      DATETIME2 (3)    NULL,
    [md_rtg_effective_dt]      DATETIME2 (3)    NULL,
    [sm_capac_appr_dt]         DATETIME2 (3)    NULL,
    [ee_appr_capac]            MONEY            NULL,
    [ee_written_cap]           MONEY            NULL,
    [ee_adj_amt_cap]           MONEY            NULL,
    [ee_capac_appr_dt]         DATETIME2 (3)    NULL,
    [shelf_avail_capac]        MONEY            NULL,
    [ee_avail_capac]           MONEY            NULL,
    [risk_ctg]                 CHAR (1)         NULL,
    [ambac_rtg]                CHAR (2)         NULL,
    [fgic_rtg]                 CHAR (2)         NULL,
    [mbia_rtg]                 CHAR (2)         NULL,
    [ambac_rtg_dt]             DATETIME2 (3)    NULL,
    [fgic_rtg_dt]              DATETIME2 (3)    NULL,
    [mbia_rtg_dt]              DATETIME2 (3)    NULL,
    [disclosure_name]          VARCHAR (140)    NULL,
    [aggr_ctg_md]              CHAR (4)         NULL,
    [mac_cap_constraint_flg]   CHAR (1)         NULL,
    [mac_manual_price_flg]     CHAR (1)         NULL,
    [mac_sm_irr]               FLOAT (53)       NULL,
    [mac_sm_rate]              FLOAT (53)       NULL,
    [sp_transfer_flg]          VARCHAR (1)      NOT NULL,
    [rtg_sp_etl_cd]            INT              NULL,
    [rtg_sp_etl_dt]            DATETIME2 (3)    NULL,
    [sp_transfer_flg_comments] VARCHAR (255)    NULL,
    [sp_transfer_flg_dt]       DATETIME2 (3)    NULL,
    [sp_transfer_flg_id]       CHAR (3)         NULL,
    [md_transfer_flg]          VARCHAR (1)      NOT NULL,
    [rtg_md_etl_cd]            INT              NULL,
    [rtg_md_etl_dt]            DATETIME2 (3)    NULL,
    [md_transfer_flg_comments] VARCHAR (255)    NULL,
    [md_transfer_flg_dt]       DATETIME2 (3)    NULL,
    [md_transfer_flg_id]       CHAR (3)         NULL,
    [current_login]            NVARCHAR (128)   NULL,
    [SysStartTime]             DATETIME2 (3)    NOT NULL,
    [SysEndTime]               DATETIME2 (3)    NOT NULL
);
CREATE CLUSTERED INDEX [ix_risk_history] ON [history].[risk] ([SysEndTime] ASC,	[SysStartTime] ASC);

INSERT INTO history.risk SELECT * FROM dbo._risk;
ALTER TABLE dbo.risk SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.risk, DATA_CONSISTENCY_CHECK=ON));

begin tran;
drop PARTITION SCHEME sch_Partition_risk_By_SysEndTime;
drop PARTITION FUNCTION fn_Partition_risk_By_SysEndTime;
commit;
*/


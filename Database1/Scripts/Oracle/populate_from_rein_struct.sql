procedure populate_from_rein_struct (anLoadBatchK IN abob_tbl_load_batch.load_batch_k%type) IS

-- insert into the upload table.  Gets reins pct from core.  
-- THIS USES THE GATEWAY.  YOU MUST COMMIT    
-- YY 8/27/2015 Add new columns from Contra project

BEGIN 


delete from abob_user.abob_tbl_load_losses_detail where load_batch_k = anLoadBatchK;


insert into ABOB_USER.abob_tbl_load_losses_detail(
    load_losses_detail_k,
    load_losses_k,
    load_batch_k,
    corp_gig_k,
    pct_reins,
    pct_reins_override,
    loss_pos,
    paid_stat,
    recovered_stat,
    lae_paid_stat,
    lae_recovered_stat,
    case_stat,
    salvage_stat,
    ibnr_stat,
    lae_case_stat,
    lae_salvage_stat,
    paid_gaap,
    recovered_gaap,
    lae_paid_gaap,
    lae_recovered_gaap,
    case_gaap,
    salvage_gaap,
    ibnr_gaap,
    lae_case_gaap,
    lae_salvage_gaap,
-- new columns from Contra project
--    WRAP_BOND_PURCHASE  ,
    loss_mit_purchase,
--    WRAP_BOND_INTEREST  ,
    loss_mit_interest,
    TSC_PAID  ,
    OR_OTHER_INCOME  ,
    OR_OTHER_INCOME_STAT  ,
    OR_CONTRA_BAL_PAID  ,
--    OR_CONTRA_BAL_WRAPPED  ,
    OR_CONTRA_BAL_LOSS_MIT  ,
    OR_CONTRA_PL_PAID  ,
--    OR_CONTRA_PL_WRAPPED  ,
    OR_CONTRA_PL_LOSS_MIT  ,
    OR_CASE  ,
    OR_SALVAGE_PAID  ,
--    OR_SALVAGE_WRAPPED  ,
    OR_SALVAGE_LOSS_MIT  ,
    OR_LAE  ,
    OR_LAE_SALVAGE  ,
    OR_CONTRA_RECLASS_SALV_PAID  ,
--    OR_CONTRA_RECLASS_SALV_WRAPPED
    OR_CONTRA_RECLASS_SAL_LOSS_MIT,
    stat_undiscounted_loss_res,
    stat_undiscounted_salv_res
    )
select 
    abob_user.abob_seq_load_losses_detail.nextval,
    ll.load_losses_k,
    ll.load_batch_k,
    rs."gig_k",
    rs."pct_reins",
    co.pct_reins,
    rtrim(rs."loss_pos"),
    ll.paid_stat * nvl(co.pct_reins, rs."pct_reins"),
    ll.recovered_stat  * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_paid_stat * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_recovered_stat  * nvl(co.pct_reins, rs."pct_reins"),
    ll.case_stat * nvl(co.pct_reins, rs."pct_reins"),
    ll.salvage_stat * nvl(co.pct_reins, rs."pct_reins"),
    ll.ibnr_stat * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_case_stat * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_salvage_stat * nvl(co.pct_reins, rs."pct_reins"),
    ll.paid_gaap * nvl(co.pct_reins, rs."pct_reins"),
    ll.recovered_gaap  * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_paid_gaap * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_recovered_gaap  * nvl(co.pct_reins, rs."pct_reins"),
    ll.case_gaap * nvl(co.pct_reins, rs."pct_reins"),
    ll.salvage_gaap * nvl(co.pct_reins, rs."pct_reins"),
    ll.ibnr_gaap * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_case_gaap * nvl(co.pct_reins, rs."pct_reins"),
    ll.lae_salvage_gaap * nvl(co.pct_reins, rs."pct_reins"),
-- new columns from Contra project
--    ll.WRAP_BOND_PURCHASE  * nvl(co.pct_wrapped, 0),
    ll.LOSS_MIT_PURCHASE  * 
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then 1
        else nvl(co.pct_LOSS_MIT, 0)
        END,        
--    ll.WRAP_BOND_INTEREST  * nvl(co.pct_wrapped, 0),
    ll.LOSS_MIT_INTEREST  * 
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then 1
        else nvl(co.pct_LOSS_MIT, 0)
        END,
    ll.TSC_PAID  * nvl(co.pct_reins, rs."pct_reins"),
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_OTHER_INCOME
        else null --nvl(co.pct_reins, rs."pct_reins")
        END,        
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_OTHER_INCOME_STAT
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_CONTRA_BAL_PAID
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
--    ll.OR_CONTRA_BAL_WRAPPED  * nvl(co.pct_wrapped, 0),
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_CONTRA_BAL_LOSS_MIT
        else null --nvl(co.pct_LOSS_MIT, 0)
        END,     
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_CONTRA_PL_PAID 
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
--    ll.OR_CONTRA_PL_WRAPPED  * nvl(co.pct_wrapped, 0), 
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_CONTRA_PL_LOSS_MIT 
        else null --nvl(co.pct_LOSS_MIT, 0)
        END,      
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_CASE 
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_SALVAGE_PAID 
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
--    ll.OR_SALVAGE_WRAPPED  * nvl(co.pct_wrapped, 0),
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_SALVAGE_LOSS_MIT  
        else null --nvl(co.pct_LOSS_MIT, 0)
        END,          
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_LAE  
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_LAE_SALVAGE  
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_CONTRA_RECLASS_SALV_PAID 
        else null --nvl(co.pct_reins, rs."pct_reins")
        END, 
--    ll.OR_CONTRA_RECLASS_SALV_WRAPPED * nvl(co.pct_wrapped, 0)
        CASE 
        WHEN (g.origin_co > 100 and owner_co < 100) then ll.OR_CONTRA_RECLASS_SAL_LOSS_MIT 
        else null --nvl(co.pct_LOSS_MIT, 0)
        END,
    ll.stat_undiscounted_loss_res * nvl(co.pct_reins, rs."pct_reins"),
    ll.stat_undiscounted_salv_res * nvl(co.pct_reins, rs."pct_reins")   
from
    ABOB_USER.abob_tbl_load_losses ll,
    ABOB_USER.ABOB_TBL_DAS_REINS_STRUC_S rs,
    abob_user.abob_tbl_core_override co,
    abob_user.abob_tbl_corp_gig g
where
    ll.load_batch_k = anLoadBatchK and
    rs."gig_k" = g.corp_gig_k and 
    --rtrim(ll.policy_num||ll.policy_sub) = rtrim(rs."policy_num"||rs."policy_sub") and  
    rtrim(ll.policy_num||ll.policy_sub) = rtrim(g.policy_num||g.policy_sub) and
    g.corp_gig_k = co.corp_gig_k(+) and
    (
        (origin_co > 100 and owner_co < 100)  -- for direct and external assumed, always populate
            or
        ((origin_co < 100 or owner_co < 100) and     
            NOT
            (abob_user.abob_fun_sql_date(rs."start_dt" )> dCurrentPeriodEnd or 
    --    (abob_user.abob_fun_sql_date(rs."stop_dt" ) is not null and abob_user.abob_fun_sql_date(rs."stop_dt" ) < dCurrentPeriodBeg) or 
            (nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_user.abob_fun_sql_date(rs."stop_dt" )) is not null and nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_fun_sql_date("stop_dt")) < dCurrentPeriodBeg))
        )   -- for cessions, limit to active only
        )
    ;    

COMMIT; -- FREE UP LOCKS IN GATEWAY.  DO NOT REMOVE

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20102, 'populate_from_reins_struc '|| SQLERRM);
End; --populate_from_rein_struct

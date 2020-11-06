procedure merge_batch_update is

begin

merge into abob_user.abob_tbl_losses l
using ABOB_USER.ABOB_TBL_LOSSES_BATCH_UPDATE b on (b.losses_k = l.losses_k)
when matched then update set
-- from spc_loss_calc USD
            l.losses_sap_balance   = b.losses_sap_balance,
            l.losses_sap_incurred  = b.losses_sap_incurred,
            l.lae_sap_incurred       = b.lae_sap_incurred,
            l.gross_reserve           = b.gross_reserve,
            l.salvage_reserve        = b.salvage_reserve,
            l.ibnr_sap_balance       = b.ibnr_sap_balance,
            l.lae_sap_balance         = b.lae_sap_balance,
            l.lae_salvage_sap_balance = b.lae_salvage_sap_balance,
            l.losses_gap_balance   = b.losses_gap_balance,
            l.losses_gap_incurred  = b.losses_gap_incurred,
            l.lae_gap_incurred       = b.lae_gap_incurred,
            l.gross_reserve_gaap   = b.gross_reserve_gaap,
            l.salvage_reserve_gaap = b.salvage_reserve_gaap,
            l.ibnr_gap_balance       = b.ibnr_gap_balance,
            l.lae_gap_balance       = b.lae_gap_balance, 
            l.lae_salvage_gap_balance = b.lae_salvage_gap_balance,
-- from spc_loss_calc FX            
            l.losses_sap_paid    = b.losses_sap_paid     ,
            l.losses_sap_recovered = b.losses_sap_recovered ,
            l.lae_sap_recovered = b.lae_sap_recovered ,
            l.lae_sap_paid = b.lae_sap_paid ,
            l.losses_gap_paid    = b.losses_gap_paid    ,
            l.losses_gap_recovered = b.losses_gap_recovered ,
            l.lae_gap_recovered = b.lae_gap_recovered ,
            l.lae_gap_paid = b.lae_gap_paid ,
            l.losses_sap_paid_adj= b.losses_sap_paid_adj    ,
            l.losses_sap_recovered_adj = b.losses_sap_recovered_adj ,
            l.lae_sap_paid_adj = b.lae_sap_paid_adj ,
            l.lae_sap_recovered_adj = b.lae_sap_recovered_adj,
-- from contra
-- update the beginning columns, 30 columns    
-- set the STAT beginning    
        l.beg_case_stat = b.beg_case_stat,
        l.beg_salvage_stat = b.beg_salvage_stat,
        l.beg_ibnr_stat = b.beg_ibnr_stat,
        l.beg_lae_case_stat = b.beg_lae_case_stat,
        l.beg_lae_salvage_stat = b.beg_lae_salvage_stat,
        l.beg_stat_undiscounted_loss_res = b.beg_stat_undiscounted_loss_res,
        l.beg_stat_undiscounted_salv_res = b.beg_stat_undiscounted_salv_res,        
-- set GAAP reserve beginning        
        l.beg_case_gaap = b.beg_case_gaap,
        l.beg_salvage_gaap = b.beg_salvage_gaap,
        l.beg_lae_case_gaap = b.beg_lae_case_gaap,
        l.beg_lae_salvage_gaap = b.beg_lae_salvage_gaap,
        l.beg_ibnr_gaap = b.beg_ibnr_gaap,
-- set contra beginning
        l.beg_contra_paid = b.beg_contra_paid,
--        l.beg_contra_wrapped = b.beg_contra_wrapped,
        l.beg_contra_loss_mit = b.beg_contra_loss_mit,
        l.beg_salv_gaap_paid = b.beg_salv_gaap_paid,
        l.beg_salv_gaap_loss_mit = b.beg_salv_gaap_loss_mit,        
--        l.beg_salv_gaap_wrapped = b.beg_salv_gaap_wrapped,
        l.beg_other_income = b.beg_other_income,
        l.beg_other_income_stat = b.beg_other_income_stat,
        l.beg_salv_res_incurred_benefit = b.beg_salv_res_incurred_benefit,
-- set ITD payments beginning
        l.beg_itd_paid_gaap = b.beg_itd_paid_gaap,
        l.beg_itd_recovered_gaap = b.beg_itd_recovered_gaap,
        l.beg_itd_lae_paid_gaap = b.beg_itd_lae_paid_gaap,
        l.beg_itd_lae_recovered_gaap = b.beg_itd_lae_recovered_gaap,
        l.beg_itd_tsc_paid_gaap = b.beg_itd_tsc_paid_gaap,
--        l.beg_itd_wrapped = b.beg_itd_wrapped,
        l.beg_itd_loss_mit = b.beg_itd_loss_mit,
--        l.beg_itd_wrapped_int = b.beg_itd_wrapped_int,
        l.beg_itd_loss_mit_int = b.beg_itd_loss_mit_int,
        l.beg_gaap_upr = b.beg_gaap_upr,
-- GAAP expected beginning        
        l.BEG_EXP_CASE_GAAP = b.BEG_EXP_CASE_GAAP,
        l.BEG_EXP_SALVAGE_GAAP = b.BEG_EXP_SALVAGE_GAAP,
        l.BEG_EXP_LAE_CASE_GAAP = b.BEG_EXP_LAE_CASE_GAAP,
        l.BEG_EXP_LAE_SALVAGE_GAAP = b.BEG_EXP_LAE_SALVAGE_GAAP,           
 
-- update the ending columns for GAAP and Contra, 29 columns
-- set GAAP reserve ending        
        l.case_res_gaap = b.case_res_gaap,
        l.salvage_res_gaap = b.salvage_res_gaap,
        l.lae_res_gaap = b.lae_res_gaap,
        l.lae_salvage_res_gaap = b.lae_salvage_res_gaap,
        l.ibnr_res_gaap = b.ibnr_res_gaap,
-- set contra ending
        l.contra_bal_paid = b.contra_bal_paid,
--        contra_bal_wrapped = b.contra_bal_wrapped,
        l.contra_bal_loss_mit = b.contra_bal_loss_mit,
        l.salvage_res_gaap_paid = b.salvage_res_gaap_paid,
--        salvage_res_gaap_wrapped = b.salvage_res_gaap_wrapped,
        l.salvage_res_gaap_loss_mit = b.salvage_res_gaap_loss_mit,
        l.other_income = b.other_income,
        l.other_income_stat = b.other_income_stat,
-- set ITD payments beginning
        l.end_itd_paid_gaap = b.end_itd_paid_gaap,
        l.end_itd_recovered_gaap = b.end_itd_recovered_gaap,
        l.end_itd_lae_paid_gaap = b.end_itd_lae_paid_gaap,
        l.end_itd_lae_recovered_gaap = b.end_itd_lae_recovered_gaap,
        l.end_itd_tsc_paid_gaap = b.end_itd_tsc_paid_gaap,
--        end_itd_wrapped = b.end_itd_wrapped,
        l.end_itd_loss_mit = b.end_itd_loss_mit,
--        end_itd_wrapped_int = b.end_itd_wrapped_int,
        l.end_itd_loss_mit_int = b.end_itd_loss_mit_int,
-- contra through PL, and reclass
        l.contra_pl_paid = b.contra_pl_paid,
--        contra_pl_wrapped = b.contra_pl_wrapped,
        l.contra_pl_loss_mit = b.contra_pl_loss_mit,
        l.contra_reclass_salv_paid = b.contra_reclass_salv_paid,
--        contra_reclass_salv_wrapped = b.contra_reclass_salv_wrapped
        l.contra_reclass_salv_loss_mit = b.contra_reclass_salv_loss_mit,
        l.calc_method = b.calc_method,
        l.prev_qtr_contra_paid = b.prev_qtr_contra_paid,
        l.prev_qtr_contra_loss_mit = b.prev_qtr_contra_loss_mit,  
        l.gaap_pl_paid = b.gaap_pl_paid,
        l.gaap_pl_loss_mit = b.gaap_pl_loss_mit,
        l.stat_undiscounted_loss_res = b.stat_undiscounted_loss_res,
        l.stat_undiscounted_salv_res = b.stat_undiscounted_salv_res,
        l.salv_res_incurred_benefit = b.salv_res_incurred_benefit,
        l.stat_recovered_pl = b.stat_recovered_pl            
;

end;  --merge_batch_update
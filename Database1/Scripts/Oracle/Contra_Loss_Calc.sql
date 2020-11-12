create or replace PACKAGE BODY           ABOB_PKG_LOSS_CONTRA AS
/******************************************************************************
   NAME:       ABOB_PKG_LOSS_CONTRA
   PURPOSE:     Contain procedues to calculate the GAAP Reserve and Contra values

   REVISIONS:
   Ver        Date        Author           Description
   ---------  ----------  ---------------  ------------------------------------
   1.0        8/21/2015      yyang       1. Created this package body.
   1.1       10/14/2015     YYANG       2. Changes due to QA and UAT feedbacks
   1.2      10/29/2015      yyang       3. Add the incurred benefit concept 
   1.3      3/29/2016       yyang       3. Rewrite the other income calculation 
   1.4      3/28/2017       yyang       Add handling of newly created loss record properly in ABOB_SPC_LOSSES_CALC
******************************************************************************/

  PROCEDURE Contra_Loss_Calc(p_losses_k IN abob_tbl_losses.losses_k%type,p_prev_losses_k IN abob_tbl_losses.losses_k%type,
                             p_mtm boolean, p_refi boolean, p_terminated boolean
                             ,p_rev_gig_k abob_user.abob_tbl_lossgig.rev_gig_k%type
                            , p_acct_year IN abob_tbl_loss_years.acct_yr%type
                            , p_acct_month      IN abob_tbl_losses.month%type                             
                             , p_batch_mode boolean default false) IS

/* 
This is the wrapped procedure, it is responsible for determining whether to run the monthly process or the quarterly;
To by-pass this, and run the quarterly process on an off-quarter month, just call Contra_Loss_Calc_Quarterly
*/
    v_month NUMBER;
    v_year number;
    
  BEGIN      
    
    if p_terminated = true then
        terminated_cession(p_losses_k, p_prev_losses_k, p_rev_gig_k, p_acct_year, p_acct_month, p_batch_mode);
    else  
        select
         month , LY.ACCT_YR
        into v_month, v_year
        from ABOB_USER.abob_tbl_losses l, abob_user.abob_tbl_loss_years ly
        where losses_k = p_losses_k
        and L.LACCTYR_K = LY.LACCTYR_K
        ;    
        
        case
            when v_year > p_acct_year or (v_year = p_acct_year and v_month > p_acct_month) then
            -- future row, just do monthly routine
                  Contra_Loss_Calc_Monthly(p_losses_k, p_prev_losses_k,p_mtm, p_refi, p_batch_mode);
            when v_year = p_acct_year and v_month < p_acct_month then
            -- historical row, should never be in this place, log an error
                abob_user.Spc_Debug('Contra Loss Calc - attempt to recalc a prior month row'); 
            when v_year = p_acct_year and mod(v_month,3) <> 0 then
                Contra_Loss_Calc_Monthly(p_losses_k, p_prev_losses_k,p_mtm, p_refi, p_batch_mode);
            when v_year = p_acct_year and mod(v_month,3) = 0 then
                Contra_Loss_Calc_Quarterly(p_losses_k, p_prev_losses_k,p_mtm, p_refi, p_batch_mode);
            else
            -- I think the only remaining possibility is v_year < p_acct_year, i.e. previous year
                abob_user.Spc_Debug('Contra Loss Calc - attempt to recalc a prior year row');            
        end case;
        
    end if;
  
  END;

  PROCEDURE Contra_Loss_Calc_Monthly(p_losses_k IN abob_tbl_losses.losses_k%type, p_prev_losses_k IN abob_tbl_losses.losses_k%type,
                                        p_mtm boolean, p_refi boolean,p_batch_mode boolean default false) IS
     
    cursor curr_losses_row is
    select * from ABOB_USER.abob_tbl_losses
    where losses_k = p_losses_k
    for update of
     beg_case_stat, beg_salvage_stat, beg_ibnr_stat, beg_lae_case_stat, beg_lae_salvage_stat
    ,beg_case_gaap, beg_salvage_gaap
    ,beg_salv_gaap_paid
    ,beg_salv_gaap_loss_mit --beg_salv_gaap_wrapped
    ,beg_ibnr_gaap, beg_lae_case_gaap, beg_lae_salvage_gaap
    ,beg_contra_paid
    ,beg_contra_loss_mit -- beg_contra_wrapped
    ,beg_itd_paid_gaap, beg_itd_recovered_gaap, beg_itd_lae_paid_gaap, beg_itd_lae_recovered_gaap, beg_itd_tsc_paid_gaap
    ,beg_itd_loss_mit, beg_itd_loss_mit_int --beg_itd_wrapped, beg_itd_wrapped_int
    ,beg_other_income
    ,beg_other_income_stat
    ,end_itd_paid_gaap, end_itd_recovered_gaap, end_itd_lae_paid_gaap, end_itd_lae_recovered_gaap, end_itd_tsc_paid_gaap
    ,end_itd_loss_mit, end_itd_loss_mit_int --end_itd_wrapped, end_itd_wrapped_int     
    ,other_income
    ,other_income_stat
    ,contra_bal_paid
    ,contra_bal_loss_mit --contra_bal_wrapped
    ,contra_pl_paid
    ,contra_pl_loss_mit --contra_pl_wrapped
    ,contra_reclass_salv_paid
    ,contra_reclass_salv_loss_mit --contra_reclass_salv_wrapped
    ,case_res_gaap, salvage_res_gaap
    ,salvage_res_gaap_paid
    ,salvage_res_gaap_loss_mit --salvage_res_gaap_wrapped
    ,lae_res_gaap, lae_salvage_res_gaap
    , ibnr_res_gaap, calc_method, prev_qtr_contra_paid, prev_qtr_contra_loss_mit
    , beg_gaap_upr, gaap_pl_paid, gaap_pl_loss_mit
    , beg_stat_undiscounted_loss_res, beg_stat_undiscounted_salv_res 
    , stat_undiscounted_loss_res, stat_undiscounted_salv_res
    ,salv_res_incurred_benefit, beg_salv_res_incurred_benefit 
    ,BEG_EXP_CASE_GAAP ,BEG_EXP_SALVAGE_GAAP  ,BEG_EXP_LAE_CASE_GAAP   ,BEG_EXP_LAE_SALVAGE_GAAP 
    ,STAT_RECOVERED_PL
    ; -- 59 updates
    c_rec curr_losses_row%rowtype
    ;
    cursor prev_losses_row is
    select * from ABOB_USER.abob_tbl_losses
    where losses_k = p_prev_losses_k
    ;    
    prev_rec  prev_losses_row%rowtype
    ;
    
  BEGIN

    if p_batch_mode = true then
    
        c_rec := batch_list_losses_rec(p_losses_k);

        -- the previous row may or may not be in the array, if the current row is the current accounting month,
        -- the previous row won't be in the array, as the previous row is a past month that cannot be updated
        if batch_list_losses_rec.exists(p_prev_losses_k) then
            prev_rec := batch_list_losses_rec(p_prev_losses_k);
        else
            open prev_losses_row;
            fetch prev_losses_row into prev_rec;
            close prev_losses_row;            
        end if;
    
    else    
        open curr_losses_row;
        open prev_losses_row;
        
        fetch curr_losses_row into c_rec;
        fetch prev_losses_row into prev_rec;
    
        close prev_losses_row;    
    end if;
    
-- update the beginning columns, 30 columns    
-- set the STAT beginning
        c_rec.beg_case_stat := nvl(prev_rec.gross_reserve,0) + nvl(c_rec.gross_reserve_ta,0);
        c_rec.beg_salvage_stat := nvl(prev_rec.salvage_reserve,0) + nvl(c_rec.salvage_reserve_ta,0);
        c_rec.beg_ibnr_stat := nvl(prev_rec.ibnr_sap_balance,0) + nvl(c_rec.ibnr_sap_balance_ta,0);
        c_rec.beg_lae_case_stat := nvl(prev_rec.lae_sap_balance,0) + nvl(c_rec.lae_sap_balance_ta,0);
        c_rec.beg_lae_salvage_stat := nvl(prev_rec.lae_salvage_sap_balance,0) + nvl(c_rec.lae_salvage_sap_balance_ta,0);
        c_rec.beg_stat_undiscounted_loss_res := nvl(prev_rec.stat_undiscounted_loss_res,0);
        c_rec.beg_stat_undiscounted_salv_res := nvl(prev_rec.stat_undiscounted_salv_res,0);
-- set GAAP reserve beginning        
        c_rec.beg_case_gaap := nvl(prev_rec.case_res_gaap,0) + nvl(c_rec.case_res_gaap_ta,0);
        c_rec.beg_salvage_gaap := nvl(prev_rec.salvage_res_gaap,0) + nvl(c_rec.salvage_res_gaap_ta,0);
        c_rec.beg_lae_case_gaap := nvl(prev_rec.lae_res_gaap,0) + nvl(c_rec.lae_res_gaap_ta,0);
        c_rec.beg_lae_salvage_gaap := nvl(prev_rec.lae_salvage_res_gaap,0) + nvl(c_rec.lae_salvage_res_gaap_ta,0);
        c_rec.beg_ibnr_gaap := nvl(prev_rec.ibnr_gap_balance,0) + nvl(c_rec.ibnr_gaap_ta,0);
-- set contra beginning
        c_rec.beg_contra_paid := nvl(prev_rec.contra_bal_paid,0) + nvl(c_rec.contra_paid_ta,0);
--        c_rec.beg_contra_wrapped := nvl(prev_rec.contra_bal_wrapped,0) + nvl(c_rec.contra_wrapped_ta,0);
        c_rec.beg_contra_loss_mit := nvl(prev_rec.contra_bal_loss_mit,0) + nvl(c_rec.contra_loss_mit_ta,0);
        c_rec.beg_salv_gaap_paid := nvl(prev_rec.salvage_res_gaap_paid,0) + nvl(c_rec.salv_gaap_paid_ta,0);
--        c_rec.beg_salv_gaap_wrapped := nvl(prev_rec.salvage_res_gaap_wrapped,0) + nvl(c_rec.salv_gaap_wrapped_ta,0);
        c_rec.beg_salv_gaap_loss_mit := nvl(prev_rec.salvage_res_gaap_loss_mit,0) + nvl(c_rec.salv_gaap_loss_mit_ta,0);
        c_rec.beg_other_income := nvl(prev_rec.other_income,0) + nvl(c_rec.other_income_ta,0);
        c_rec.beg_other_income_stat := nvl(prev_rec.other_income_stat,0) + nvl(c_rec.other_income_stat_ta,0);
        c_rec.beg_salv_res_incurred_benefit := nvl(prev_rec.salv_res_incurred_benefit,0) + nvl(c_rec.SALV_RES_INCURRED_BENEFIT_TA,0);
-- set ITD payments beginning
        c_rec.beg_itd_paid_gaap := nvl(prev_rec.end_itd_paid_gaap,0) + nvl(c_rec.itd_paid_gaap_ta,0);
        c_rec.beg_itd_recovered_gaap := nvl(prev_rec.end_itd_recovered_gaap,0) + nvl(c_rec.itd_recovered_gaap_ta,0);
        c_rec.beg_itd_lae_paid_gaap := nvl(prev_rec.end_itd_lae_paid_gaap,0) + nvl(c_rec.itd_lae_paid_gaap_ta,0);
        c_rec.beg_itd_lae_recovered_gaap := nvl(prev_rec.end_itd_lae_recovered_gaap,0) + nvl(c_rec.itd_lae_recovered_gaap_ta,0);
        c_rec.beg_itd_tsc_paid_gaap := nvl(prev_rec.end_itd_tsc_paid_gaap,0) + nvl(c_rec.itd_tsc_paid_gaap_ta,0);
--        c_rec.beg_itd_wrapped := nvl(prev_rec.end_itd_wrapped,0) + nvl(c_rec.itd_wrapped_ta,0);
        c_rec.beg_itd_loss_mit := nvl(prev_rec.end_itd_loss_mit,0) + nvl(c_rec.itd_loss_mit_ta,0);
--        c_rec.beg_itd_wrapped_int := nvl(prev_rec.end_itd_wrapped_int,0) + nvl(c_rec.itd_wrapped_int_ta,0);
        c_rec.beg_itd_loss_mit_int := nvl(prev_rec.end_itd_loss_mit_int,0) + nvl(c_rec.itd_loss_mit_int_ta,0);
        c_rec.beg_gaap_upr := nvl(prev_rec.f_gaap_upr,0) + nvl(c_rec.f_gaap_upr_ta,0);
-- GAAP expected beginning        
        c_rec.BEG_EXP_CASE_GAAP := nvl(prev_rec.gross_reserve_gaap,0) + nvl(c_rec.case_reserve_gaap_ta,0);
        c_rec.BEG_EXP_SALVAGE_GAAP := nvl(prev_rec.salvage_reserve_gaap,0) + nvl(c_rec.salvage_reserve_gaap_ta,0); 
        c_rec.BEG_EXP_LAE_CASE_GAAP := nvl(prev_rec.lae_gap_balance,0) + nvl(c_rec.lae_gap_balance_ta,0);  
        c_rec.BEG_EXP_LAE_SALVAGE_GAAP := nvl(prev_rec.lae_salvage_gap_balance,0)  + nvl(c_rec.lae_salvage_gap_balance_ta,0);

-- update the ending columns for GAAP and Contra, 29 columns
-- during off-quarter monthly run,Accounting wants to add all payments to Contra, and not change the GAAP reserves, exception for MTM and ReFi
-- though we still allow override (hmm... unsure about this one though...) 

-- set GAAP reserve ending        
        c_rec.case_res_gaap := 
            case
            when p_refi then 0
            else nvl(c_rec.or_case, c_rec.beg_case_gaap)
            end;
        c_rec.salvage_res_gaap := 
            case
            when p_refi then 0
            when c_rec.or_salvage_paid is null and c_rec.or_salvage_loss_mit is null then c_rec.beg_salvage_gaap
            else nvl(c_rec.or_salvage_paid, c_rec.beg_salv_gaap_paid)
                      + nvl(c_rec.or_salvage_loss_mit, c_rec.beg_salv_gaap_loss_mit)
--                    + nvl(c_rec.or_salvage_wrapped, c_rec.beg_salv_gaap_wrapped);  -- salvage is done by components
            end;
        c_rec.lae_res_gaap := 
            case
            when p_refi then 0
            else nvl(c_rec.or_lae, c_rec.beg_lae_case_gaap)
            end;
        c_rec.lae_salvage_res_gaap := 
            case
            when p_refi then 0
            else nvl(c_rec.or_lae_salvage, c_rec.beg_lae_salvage_gaap)
            end;
        c_rec.ibnr_res_gaap := 
            case
            when p_refi then 0
            else nvl(c_rec.ibnr_gap_balance,0)
            end;
-- set contra ending
        c_rec.contra_bal_paid := 
            case
            when p_mtm or p_refi then c_rec.beg_contra_paid
            else 
                c_rec.beg_contra_paid + nvl(c_rec.losses_gap_paid,0) - nvl(c_rec.losses_gap_recovered,0)
                              - nvl(c_rec.loss_mit_interest,0) --nvl(c_rec.wrap_bond_interest,0)
                              + nvl(c_rec.lae_gap_paid,0)
                              - nvl(c_rec.lae_gap_recovered,0) + nvl(c_rec.tsc_paid,0)
            end;
        c_rec.contra_bal_loss_mit := 
            case
            when p_mtm or p_refi then c_rec.beg_contra_loss_mit
            else 
                --c_rec.beg_contra_wrapped + nvl(c_rec.wrap_bond_purchase,0)
                c_rec.beg_contra_loss_mit + nvl(c_rec.loss_mit_purchase,0)
            end;
        c_rec.salvage_res_gaap_paid := 
            case
            when p_refi then 0
            else nvl(c_rec.or_salvage_paid, c_rec.beg_salv_gaap_paid)
            end;
--        c_rec.salvage_res_gaap_wrapped := nvl(c_rec.or_salvage_wrapped, c_rec.beg_salv_gaap_wrapped);
        c_rec.salvage_res_gaap_loss_mit := 
            case
            when p_refi then 0
            else nvl(c_rec.or_salvage_loss_mit, c_rec.beg_salv_gaap_loss_mit)
            end;
        c_rec.other_income := 
            case
            when p_refi then 0            
            else nvl(c_rec.or_other_income, 0) + c_rec.beg_other_income
            end;
        c_rec.other_income_stat := 
            case
            when p_refi then 0
            else nvl(c_rec.or_other_income_stat, c_rec.beg_other_income_stat)
            end;            
-- set ITD payments beginning
        c_rec.end_itd_paid_gaap := c_rec.beg_itd_paid_gaap + nvl(c_rec.losses_gap_paid,0);
        c_rec.end_itd_recovered_gaap := c_rec.beg_itd_recovered_gaap + nvl(c_rec.losses_gap_recovered,0);
        c_rec.end_itd_lae_paid_gaap := c_rec.beg_itd_lae_paid_gaap + nvl(c_rec.lae_gap_paid,0);
        c_rec.end_itd_lae_recovered_gaap := c_rec.beg_itd_lae_recovered_gaap + nvl(c_rec.lae_gap_recovered,0);
        c_rec.end_itd_tsc_paid_gaap := c_rec.beg_itd_tsc_paid_gaap + nvl(c_rec.tsc_paid,0);
--        c_rec.end_itd_wrapped := c_rec.beg_itd_wrapped + nvl(c_rec.wrap_bond_purchase,0);
        c_rec.end_itd_loss_mit := c_rec.beg_itd_loss_mit + nvl(c_rec.loss_mit_purchase,0);
--        c_rec.end_itd_wrapped_int := c_rec.beg_itd_wrapped_int + nvl(c_rec.wrap_bond_interest,0);
        c_rec.end_itd_loss_mit_int := c_rec.beg_itd_loss_mit_int + nvl(c_rec.loss_mit_interest,0);
-- no contra through PL, nor reclass
        c_rec.contra_pl_paid := 0;
--        c_rec.contra_pl_wrapped := 0;
        c_rec.contra_pl_loss_mit := 0;
        c_rec.contra_reclass_salv_paid := 0;
--        c_rec.contra_reclass_salv_wrapped := 0;  
        c_rec.contra_reclass_salv_loss_mit := 0;
        c_rec.calc_method := case
                                when p_refi then 'R'
                                when p_mtm then 'M'
                                when prev_rec.calc_method is null then 'F' -- default to FG if the flag does not exist before
                                else prev_rec.calc_method
                             end;
                                  
        c_rec.prev_qtr_contra_paid := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_paid
                else prev_rec.prev_qtr_contra_paid
            end;
        c_rec.prev_qtr_contra_loss_mit := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_loss_mit
                else prev_rec.prev_qtr_contra_loss_mit
            end;
-- set gaap incur/PL, for MTM and ReFi, all the cash are incur/PL, for FG, 0 are incur at monthly (held up in Contra instead)
        c_rec.gaap_pl_paid := 
            case
            when p_mtm or p_refi then 
                nvl(c_rec.losses_gap_paid,0) - nvl(c_rec.losses_gap_recovered,0)
                  - nvl(c_rec.loss_mit_interest,0) --nvl(c_rec.wrap_bond_interest,0)
                  + nvl(c_rec.lae_gap_paid,0)
                  - nvl(c_rec.lae_gap_recovered,0) + nvl(c_rec.tsc_paid,0)
            else 
                0
            end;
        c_rec.gaap_pl_loss_mit := 
            case
            when p_mtm or p_refi then
                nvl(c_rec.loss_mit_purchase,0)
            else 
                0
            end;            
        c_rec.stat_undiscounted_loss_res := nvl(c_rec.beg_stat_undiscounted_loss_res,0);
        c_rec.stat_undiscounted_salv_res := nvl(c_rec.beg_stat_undiscounted_salv_res,0);
        c_rec.salv_res_incurred_benefit := nvl(c_rec.beg_salv_res_incurred_benefit,0); 
        c_rec.STAT_RECOVERED_PL := nvl(c_rec.losses_sap_recovered,0);            
             

    if p_batch_mode = true then
        batch_list_losses_rec(p_losses_k) := c_rec;
    else
       
    update ABOB_USER.abob_tbl_losses set
-- update the beginning columns, 26 columns    
-- set the STAT beginning    
        beg_case_stat = c_rec.beg_case_stat,
        beg_salvage_stat = c_rec.beg_salvage_stat,
        beg_ibnr_stat = c_rec.beg_ibnr_stat,
        beg_lae_case_stat = c_rec.beg_lae_case_stat,
        beg_lae_salvage_stat = c_rec.beg_lae_salvage_stat,
        beg_stat_undiscounted_loss_res = c_rec.beg_stat_undiscounted_loss_res,
        beg_stat_undiscounted_salv_res = c_rec.beg_stat_undiscounted_salv_res,        
-- set GAAP reserve beginning        
        beg_case_gaap = c_rec.beg_case_gaap,
        beg_salvage_gaap = c_rec.beg_salvage_gaap,
        beg_lae_case_gaap = c_rec.beg_lae_case_gaap,
        beg_lae_salvage_gaap = c_rec.beg_lae_salvage_gaap,
        beg_ibnr_gaap = c_rec.beg_ibnr_gaap,
-- set contra beginning
        beg_contra_paid = c_rec.beg_contra_paid,
--        beg_contra_wrapped = c_rec.beg_contra_wrapped,
        beg_contra_loss_mit = c_rec.beg_contra_loss_mit,
        beg_salv_gaap_paid = c_rec.beg_salv_gaap_paid,
        beg_salv_gaap_loss_mit = c_rec.beg_salv_gaap_loss_mit,        
--        beg_salv_gaap_wrapped = c_rec.beg_salv_gaap_wrapped,
        beg_other_income = c_rec.beg_other_income,
        beg_other_income_stat = c_rec.beg_other_income_stat,
        beg_salv_res_incurred_benefit = c_rec.beg_salv_res_incurred_benefit,
-- set ITD payments beginning
        beg_itd_paid_gaap = c_rec.beg_itd_paid_gaap,
        beg_itd_recovered_gaap = c_rec.beg_itd_recovered_gaap,
        beg_itd_lae_paid_gaap = c_rec.beg_itd_lae_paid_gaap,
        beg_itd_lae_recovered_gaap = c_rec.beg_itd_lae_recovered_gaap,
        beg_itd_tsc_paid_gaap = c_rec.beg_itd_tsc_paid_gaap,
--        beg_itd_wrapped = c_rec.beg_itd_wrapped,
        beg_itd_loss_mit = c_rec.beg_itd_loss_mit,
--        beg_itd_wrapped_int = c_rec.beg_itd_wrapped_int,
        beg_itd_loss_mit_int = c_rec.beg_itd_loss_mit_int,
        beg_gaap_upr = c_rec.beg_gaap_upr,
-- GAAP expected beginning        
        BEG_EXP_CASE_GAAP = c_rec.BEG_EXP_CASE_GAAP,
        BEG_EXP_SALVAGE_GAAP = c_rec.BEG_EXP_SALVAGE_GAAP,
        BEG_EXP_LAE_CASE_GAAP = c_rec.BEG_EXP_LAE_CASE_GAAP,
        BEG_EXP_LAE_SALVAGE_GAAP = c_rec.BEG_EXP_LAE_SALVAGE_GAAP,     
 
-- update the ending columns for GAAP and Contra, 29 columns
-- set GAAP reserve ending        
        case_res_gaap = c_rec.case_res_gaap,
        salvage_res_gaap = c_rec.salvage_res_gaap,
        lae_res_gaap = c_rec.lae_res_gaap,
        lae_salvage_res_gaap = c_rec.lae_salvage_res_gaap,
        ibnr_res_gaap = c_rec.ibnr_res_gaap,
-- set contra ending
        contra_bal_paid = c_rec.contra_bal_paid,
--        contra_bal_wrapped = c_rec.contra_bal_wrapped,
        contra_bal_loss_mit = c_rec.contra_bal_loss_mit,
        salvage_res_gaap_paid = c_rec.salvage_res_gaap_paid,
--        salvage_res_gaap_wrapped = c_rec.salvage_res_gaap_wrapped,
        salvage_res_gaap_loss_mit = c_rec.salvage_res_gaap_loss_mit,
        other_income = c_rec.other_income,
        other_income_stat = c_rec.other_income_stat,
-- set ITD payments beginning
        end_itd_paid_gaap = c_rec.end_itd_paid_gaap,
        end_itd_recovered_gaap = c_rec.end_itd_recovered_gaap,
        end_itd_lae_paid_gaap = c_rec.end_itd_lae_paid_gaap,
        end_itd_lae_recovered_gaap = c_rec.end_itd_lae_recovered_gaap,
        end_itd_tsc_paid_gaap = c_rec.end_itd_tsc_paid_gaap,
--        end_itd_wrapped = c_rec.end_itd_wrapped,
        end_itd_loss_mit = c_rec.end_itd_loss_mit,
--        end_itd_wrapped_int = c_rec.end_itd_wrapped_int,
        end_itd_loss_mit_int = c_rec.end_itd_loss_mit_int,
-- contra through PL, and reclass
        contra_pl_paid = c_rec.contra_pl_paid,
--        contra_pl_wrapped = c_rec.contra_pl_wrapped,
        contra_pl_loss_mit = c_rec.contra_pl_loss_mit,
        contra_reclass_salv_paid = c_rec.contra_reclass_salv_paid,
--        contra_reclass_salv_wrapped = c_rec.contra_reclass_salv_wrapped
        contra_reclass_salv_loss_mit = c_rec.contra_reclass_salv_loss_mit,
        calc_method = c_rec.calc_method,
        prev_qtr_contra_paid = c_rec.prev_qtr_contra_paid,
        prev_qtr_contra_loss_mit = c_rec.prev_qtr_contra_loss_mit,  
        gaap_pl_paid = c_rec.gaap_pl_paid,
        gaap_pl_loss_mit = c_rec.gaap_pl_loss_mit,
        stat_undiscounted_loss_res = c_rec.stat_undiscounted_loss_res,
        stat_undiscounted_salv_res = c_rec.stat_undiscounted_salv_res,
        salv_res_incurred_benefit = c_rec.salv_res_incurred_benefit,
        STAT_RECOVERED_PL = c_rec.STAT_RECOVERED_PL
    where current of curr_losses_row; 
    
    close curr_losses_row;

    end if;

EXCEPTION
    WHEN OTHERS THEN

        IF curr_losses_row%isopen THEN
            close curr_losses_row;
        END IF;

        raise_application_error(-20003,'contra_loss_calc_monthly - losses_k '||p_losses_k||sqlerrm);
  END; -- contra_loss_calc_monthly
  
  PROCEDURE Contra_Loss_Calc_Quarterly(p_losses_k IN abob_tbl_losses.losses_k%type, p_prev_losses_k IN abob_tbl_losses.losses_k%type,
                                        p_mtm boolean, p_refi boolean,p_batch_mode boolean default false) IS
    
    cursor curr_losses_row is
    select * from ABOB_USER.abob_tbl_losses
    where losses_k = p_losses_k
    for update of
     beg_case_stat, beg_salvage_stat, beg_ibnr_stat, beg_lae_case_stat, beg_lae_salvage_stat
    ,beg_case_gaap, beg_salvage_gaap
    ,beg_salv_gaap_paid
    ,beg_salv_gaap_loss_mit --beg_salv_gaap_wrapped
    ,beg_ibnr_gaap, beg_lae_case_gaap, beg_lae_salvage_gaap
    ,beg_contra_paid
    ,beg_contra_loss_mit -- beg_contra_wrapped
    ,beg_itd_paid_gaap, beg_itd_recovered_gaap, beg_itd_lae_paid_gaap, beg_itd_lae_recovered_gaap, beg_itd_tsc_paid_gaap
    ,beg_itd_loss_mit, beg_itd_loss_mit_int --beg_itd_wrapped, beg_itd_wrapped_int
    ,beg_other_income
    ,beg_other_income_stat
    ,end_itd_paid_gaap, end_itd_recovered_gaap, end_itd_lae_paid_gaap, end_itd_lae_recovered_gaap, end_itd_tsc_paid_gaap
    ,end_itd_loss_mit, end_itd_loss_mit_int --end_itd_wrapped, end_itd_wrapped_int     
    ,other_income
    ,other_income_stat
    ,contra_bal_paid
    ,contra_bal_loss_mit --contra_bal_wrapped
    ,contra_pl_paid
    ,contra_pl_loss_mit --contra_pl_wrapped
    ,contra_reclass_salv_paid
    ,contra_reclass_salv_loss_mit --contra_reclass_salv_wrapped
    ,case_res_gaap, salvage_res_gaap
    ,salvage_res_gaap_paid
    ,salvage_res_gaap_loss_mit --salvage_res_gaap_wrapped
    ,lae_res_gaap, lae_salvage_res_gaap
    , ibnr_res_gaap, calc_method, prev_qtr_contra_paid, prev_qtr_contra_loss_mit
    , beg_gaap_upr, gaap_pl_paid, gaap_pl_loss_mit
    , beg_stat_undiscounted_loss_res, beg_stat_undiscounted_salv_res 
    , stat_undiscounted_loss_res, stat_undiscounted_salv_res
    ,salv_res_incurred_benefit, beg_salv_res_incurred_benefit 
    ,BEG_EXP_CASE_GAAP ,BEG_EXP_SALVAGE_GAAP  ,BEG_EXP_LAE_CASE_GAAP   ,BEG_EXP_LAE_SALVAGE_GAAP 
    ,STAT_RECOVERED_PL
    ; -- 59 updates
    c_rec curr_losses_row%rowtype
    ;
    cursor prev_losses_row is
    select * from ABOB_USER.abob_tbl_losses
    where losses_k = p_prev_losses_k
    ;    
    prev_rec  prev_losses_row%rowtype
    ; 

-- interim variables    
    v_bypass_other_income boolean;
    v_beg_itd_total_paids   number;
    v_modify_upr    number;
    v_total_expected_loss number;
        
    v_beg_total_contra  number;
    v_beg_contra_paid_and_cash number;
    v_beg_contra_wrapped_and_cash number;
    v_interim_contra_paid number;
    v_interim_contra_wrapped number;
    v_interim_total_contra number;
    v_qtd_total_contra_pl number;
    v_end_total_contra number;
    v_prev_qtr_total_contra number;

    v_interim_total_SnS number;
    v_qtd_SnS_delta number;
    v_qtd_total_reclass number;
    v_interim_SnS_paid number;
    v_interim_SnS_wrapped number;
    v_anticipated_SnS_paid number;
    v_anticipated_SnS_wrapped number;
    v_anticipated_SnS_total number;
    
    v_interim_itd_total_paids number;
    v_interim_itd_recovered number;
    v_interim_itd_lae_recovered number;

    v_beg_total_other_income number;
    v_end_total_other_income number;
    v_total_other_income_change number;
    v_qtd_other_income_change_rec number;
--    v_qtd_other_income_change_lae number;
    
    v_breach_amount number;
    v_breach_check  number;
    
    v_unbalance number;
    
-- output variables
    v_case_res_gaap number;
    v_lae_res_gaap number;
    v_contra_bal_paid number;
    v_contra_bal_wrapped number;
    v_salvage_res_gaap_paid number;
    v_salvage_res_gaap_wrapped number;
    v_salv_res number;
    v_lae_salv_res number;
    v_other_income number;
    v_other_income_stat number;

    v_end_itd_paid_gaap number;
    v_end_itd_recovered_gaap number;
    v_end_itd_lae_paid_gaap number;
    v_end_itd_lae_recovered_gaap number;
    v_end_itd_tsc_paid_gaap number;
    v_end_itd_wrapped number;
    v_end_itd_wrapped_int number;

    v_contra_pl_paid number;
    v_contra_pl_wrapped number;
    v_contra_reclass_salv_paid number;
    v_contra_reclass_salv_wrapped number;      
    v_calc_method char(1);
    v_gaap_pl_paid number;
    v_gaap_pl_loss_mit number;
    
    v_ss_incurred_benefit number;
    v_ibnr_res_gaap number;
    v_reclass_direction number;
    
    v_stat_recovered_pl number; 
    v_total_expected_loss_stat number;         
    
  BEGIN
  
    if p_batch_mode = true then
    
        c_rec := batch_list_losses_rec(p_losses_k);

        -- the previous row may or may not be in the array, if the current row is the current accounting month,
        -- the previous row won't be in the array, as the previous row is a past month that cannot be updated
        if batch_list_losses_rec.exists(p_prev_losses_k) then
            prev_rec := batch_list_losses_rec(p_prev_losses_k);
        else
            open prev_losses_row;
            fetch prev_losses_row into prev_rec;
            close prev_losses_row;            
        end if;
    
    else    
        open curr_losses_row;
        open prev_losses_row;
        
        fetch curr_losses_row into c_rec;
        fetch prev_losses_row into prev_rec;
    
        close prev_losses_row;    
    end if;

-- update the beginning columns, 26 columns    
-- set the STAT beginning
        c_rec.beg_case_stat := nvl(prev_rec.gross_reserve,0) + nvl(c_rec.gross_reserve_ta,0);
        c_rec.beg_salvage_stat := nvl(prev_rec.salvage_reserve,0) + nvl(c_rec.salvage_reserve_ta,0);
        c_rec.beg_ibnr_stat := nvl(prev_rec.ibnr_sap_balance,0) + nvl(c_rec.ibnr_sap_balance_ta,0);
        c_rec.beg_lae_case_stat := nvl(prev_rec.lae_sap_balance,0) + nvl(c_rec.lae_sap_balance_ta,0);
        c_rec.beg_lae_salvage_stat := nvl(prev_rec.lae_salvage_sap_balance,0) + nvl(c_rec.lae_salvage_sap_balance_ta,0);
        c_rec.beg_stat_undiscounted_loss_res := nvl(prev_rec.stat_undiscounted_loss_res,0);
        c_rec.beg_stat_undiscounted_salv_res := nvl(prev_rec.stat_undiscounted_salv_res,0);
-- set GAAP reserve beginning        
        c_rec.beg_case_gaap := nvl(prev_rec.case_res_gaap,0) + nvl(c_rec.case_res_gaap_ta,0);
        c_rec.beg_salvage_gaap := nvl(prev_rec.salvage_res_gaap,0) + nvl(c_rec.salvage_res_gaap_ta,0);
        c_rec.beg_lae_case_gaap := nvl(prev_rec.lae_res_gaap,0) + nvl(c_rec.lae_res_gaap_ta,0);
        c_rec.beg_lae_salvage_gaap := nvl(prev_rec.lae_salvage_res_gaap,0) + nvl(c_rec.lae_salvage_res_gaap_ta,0);
        c_rec.beg_ibnr_gaap := nvl(prev_rec.ibnr_gap_balance,0) + nvl(c_rec.ibnr_gaap_ta,0);
-- set contra beginning
        c_rec.beg_contra_paid := nvl(prev_rec.contra_bal_paid,0) + nvl(c_rec.contra_paid_ta,0);
--        c_rec.beg_contra_wrapped := nvl(prev_rec.contra_bal_wrapped,0) + nvl(c_rec.contra_wrapped_ta,0);
        c_rec.beg_contra_loss_mit := nvl(prev_rec.contra_bal_loss_mit,0) + nvl(c_rec.contra_loss_mit_ta,0);
        c_rec.beg_salv_gaap_paid := nvl(prev_rec.salvage_res_gaap_paid,0) + nvl(c_rec.salv_gaap_paid_ta,0);
--        c_rec.beg_salv_gaap_wrapped := nvl(prev_rec.salvage_res_gaap_wrapped,0) + nvl(c_rec.salv_gaap_wrapped_ta,0);
        c_rec.beg_salv_gaap_loss_mit := nvl(prev_rec.salvage_res_gaap_loss_mit,0) + nvl(c_rec.salv_gaap_loss_mit_ta,0);
        c_rec.beg_other_income := nvl(prev_rec.other_income,0) + nvl(c_rec.other_income_ta,0);
        c_rec.beg_other_income_stat := nvl(prev_rec.other_income_stat,0) + nvl(c_rec.other_income_stat_ta,0);
        c_rec.beg_salv_res_incurred_benefit := nvl(prev_rec.salv_res_incurred_benefit,0) + nvl(c_rec.SALV_RES_INCURRED_BENEFIT_TA,0);
-- set ITD payments beginning
        c_rec.beg_itd_paid_gaap := nvl(prev_rec.end_itd_paid_gaap,0) + nvl(c_rec.itd_paid_gaap_ta,0);
        c_rec.beg_itd_recovered_gaap := nvl(prev_rec.end_itd_recovered_gaap,0) + nvl(c_rec.itd_recovered_gaap_ta,0);
        c_rec.beg_itd_lae_paid_gaap := nvl(prev_rec.end_itd_lae_paid_gaap,0) + nvl(c_rec.itd_lae_paid_gaap_ta,0);
        c_rec.beg_itd_lae_recovered_gaap := nvl(prev_rec.end_itd_lae_recovered_gaap,0) + nvl(c_rec.itd_lae_recovered_gaap_ta,0);
        c_rec.beg_itd_tsc_paid_gaap := nvl(prev_rec.end_itd_tsc_paid_gaap,0) + nvl(c_rec.itd_tsc_paid_gaap_ta,0);
--        c_rec.beg_itd_wrapped := nvl(prev_rec.end_itd_wrapped,0) + nvl(c_rec.itd_wrapped_ta,0);
        c_rec.beg_itd_loss_mit := nvl(prev_rec.end_itd_loss_mit,0) + nvl(c_rec.itd_loss_mit_ta,0);
--        c_rec.beg_itd_wrapped_int := nvl(prev_rec.end_itd_wrapped_int,0) + nvl(c_rec.itd_wrapped_int_ta,0);
        c_rec.beg_itd_loss_mit_int := nvl(prev_rec.end_itd_loss_mit_int,0) + nvl(c_rec.itd_loss_mit_int_ta,0);
        c_rec.beg_gaap_upr := nvl(prev_rec.f_gaap_upr,0) + nvl(c_rec.f_gaap_upr_ta,0);
-- GAAP expected beginning        
        c_rec.BEG_EXP_CASE_GAAP := nvl(prev_rec.gross_reserve_gaap,0) + nvl(c_rec.case_reserve_gaap_ta,0);
        c_rec.BEG_EXP_SALVAGE_GAAP := nvl(prev_rec.salvage_reserve_gaap,0) + nvl(c_rec.salvage_reserve_gaap_ta,0); 
        c_rec.BEG_EXP_LAE_CASE_GAAP := nvl(prev_rec.lae_gap_balance,0) + nvl(c_rec.lae_gap_balance_ta,0);  
        c_rec.BEG_EXP_LAE_SALVAGE_GAAP := nvl(prev_rec.lae_salvage_gap_balance,0)  + nvl(c_rec.lae_salvage_gap_balance_ta,0);        

-- starting the quarterly logic in earnest
   
    if p_refi = true then
-- refi handling    
    v_case_res_gaap := 0;
    v_lae_res_gaap := 0;
    v_contra_bal_paid := 0;
    v_contra_bal_wrapped := 0;
    v_salvage_res_gaap_paid := 0;
    v_salvage_res_gaap_wrapped := 0;
    v_ibnr_res_gaap := 0;
    v_other_income := c_rec.beg_other_income;
    v_other_income_stat := c_rec.beg_other_income_stat;

    v_end_itd_paid_gaap := c_rec.beg_itd_paid_gaap + nvl(c_rec.losses_gap_paid,0);
    v_end_itd_recovered_gaap := c_rec.beg_itd_recovered_gaap + nvl(c_rec.losses_gap_recovered,0);
    v_end_itd_lae_paid_gaap := c_rec.beg_itd_lae_paid_gaap + nvl(c_rec.lae_gap_paid,0);
    v_end_itd_lae_recovered_gaap := c_rec.beg_itd_lae_recovered_gaap + nvl(c_rec.lae_gap_recovered,0);
    v_end_itd_tsc_paid_gaap := c_rec.beg_itd_tsc_paid_gaap + nvl(c_rec.tsc_paid,0);
    v_end_itd_wrapped := c_rec.beg_itd_loss_mit + nvl(c_rec.loss_mit_purchase,0);
    v_end_itd_wrapped_int := c_rec.beg_itd_loss_mit_int + nvl(c_rec.loss_mit_interest,0);

    v_contra_pl_paid := 0;
    v_contra_pl_wrapped := 0;
    v_contra_reclass_salv_paid := 0;
    v_contra_reclass_salv_wrapped := 0;
    v_calc_method := 'R';
    v_gaap_pl_paid := c_rec.beg_contra_paid + nvl(c_rec.losses_gap_paid,0) - nvl(c_rec.losses_gap_recovered,0)
                        + nvl(c_rec.lae_gap_paid,0) - nvl(c_rec.lae_gap_recovered,0) + nvl(c_rec.tsc_paid,0)
                        - nvl(c_rec.loss_mit_interest,0) --nvl(c_rec.wrap_bond_interest,0)
                        ;
    v_gaap_pl_loss_mit:= c_rec.beg_contra_loss_mit + nvl(c_rec.loss_mit_purchase,0); --c_rec.beg_contra_wrapped + nvl(c_rec.wrap_bond_purchase,0);
    v_ss_incurred_benefit := 0;
    v_salv_res := v_salvage_res_gaap_paid + v_salvage_res_gaap_wrapped;
    v_stat_recovered_pl := nvl(c_rec.losses_sap_recovered,0);
                                
    elsif p_mtm = true then
-- mtm handling    
    v_case_res_gaap := c_rec.gross_reserve_gaap;
    v_lae_res_gaap := c_rec.lae_gap_balance;
    v_contra_bal_paid := 0;
    v_contra_bal_wrapped := 0;
    v_salvage_res_gaap_paid := c_rec.salvage_reserve_gaap;
    v_salvage_res_gaap_wrapped := 0;
    v_ibnr_res_gaap := c_rec.IBNR_GAP_BALANCE;
    v_other_income := c_rec.beg_other_income;
    v_other_income_stat := c_rec.beg_other_income_stat;

    v_end_itd_paid_gaap := c_rec.beg_itd_paid_gaap + nvl(c_rec.losses_gap_paid,0);
    v_end_itd_recovered_gaap := c_rec.beg_itd_recovered_gaap + nvl(c_rec.losses_gap_recovered,0);
    v_end_itd_lae_paid_gaap := c_rec.beg_itd_lae_paid_gaap + nvl(c_rec.lae_gap_paid,0);
    v_end_itd_lae_recovered_gaap := c_rec.beg_itd_lae_recovered_gaap + nvl(c_rec.lae_gap_recovered,0);
    v_end_itd_tsc_paid_gaap := c_rec.beg_itd_tsc_paid_gaap + nvl(c_rec.tsc_paid,0);
    v_end_itd_wrapped := c_rec.beg_itd_loss_mit + nvl(c_rec.loss_mit_purchase,0);
    v_end_itd_wrapped_int := c_rec.beg_itd_loss_mit_int + nvl(c_rec.loss_mit_interest,0);

    v_contra_pl_paid := 0;
    v_contra_pl_wrapped := 0;
    v_contra_reclass_salv_paid := 0;
    v_contra_reclass_salv_wrapped := 0;   
    v_calc_method := 'M';
    v_gaap_pl_paid := c_rec.beg_contra_paid + nvl(c_rec.losses_gap_paid,0) - nvl(c_rec.losses_gap_recovered,0)
                        + nvl(c_rec.lae_gap_paid,0) - nvl(c_rec.lae_gap_recovered,0) + nvl(c_rec.tsc_paid,0)
                        - nvl(c_rec.loss_mit_interest,0) --nvl(c_rec.wrap_bond_interest,0)
                        ;
    v_gaap_pl_loss_mit:= c_rec.beg_contra_loss_mit + nvl(c_rec.loss_mit_purchase,0); --c_rec.beg_contra_wrapped + nvl(c_rec.wrap_bond_purchase,0);
    v_ss_incurred_benefit := 0;
    v_salv_res := v_salvage_res_gaap_paid + v_salvage_res_gaap_wrapped;
    v_stat_recovered_pl := nvl(c_rec.losses_sap_recovered,0);
                                     
    else
-- FG handling
    v_calc_method := 'F';

    if nvl(c_rec.f_gaap_upr,0) <= 1 then
        v_modify_upr := 0;
    else
        v_modify_upr := c_rec.f_gaap_upr;
    end if;
    
    v_bypass_other_income := FALSE
    ;
    v_beg_itd_total_paids := c_rec.beg_itd_paid_gaap - c_rec.beg_itd_recovered_gaap + c_rec.beg_itd_lae_paid_gaap
                            - c_rec.beg_itd_lae_recovered_gaap + c_rec.beg_itd_tsc_paid_gaap 
                            + c_rec.beg_itd_loss_mit - c_rec.beg_itd_loss_mit_int --c_rec.beg_itd_wrapped - c_rec.beg_itd_wrapped_int
                            ;
    v_beg_total_contra := c_rec.beg_contra_paid + c_rec.beg_contra_loss_mit --c_rec.beg_contra_wrapped
    ;
    v_prev_qtr_total_contra := c_rec.prev_qtr_contra_paid + c_rec.prev_qtr_contra_loss_mit
    ;
    v_beg_contra_paid_and_cash  := c_rec.beg_contra_paid + nvl(c_rec.losses_gap_paid,0) - nvl(c_rec.losses_gap_recovered,0)
                        + nvl(c_rec.lae_gap_paid,0) - nvl(c_rec.lae_gap_recovered,0) + nvl(c_rec.tsc_paid,0)
                        - nvl(c_rec.loss_mit_interest,0) --nvl(c_rec.wrap_bond_interest,0)
                        ;
    v_interim_contra_paid := v_beg_contra_paid_and_cash
    ;                    
    v_beg_contra_wrapped_and_cash := c_rec.beg_contra_loss_mit + nvl(c_rec.loss_mit_purchase,0) --c_rec.beg_contra_wrapped + nvl(c_rec.wrap_bond_purchase,0)
    ;
    v_interim_contra_wrapped := v_beg_contra_wrapped_and_cash
    ;
    v_interim_total_contra := v_interim_contra_paid + v_interim_contra_wrapped
    ;
    v_total_expected_loss := nvl(c_rec.gross_reserve_gaap,0) + nvl(c_rec.lae_gap_balance,0)
                             - nvl(c_rec.salvage_reserve_gaap,0) - nvl(c_rec.lae_salvage_gap_balance,0)
    ;
    v_interim_itd_total_paids := v_beg_itd_total_paids + nvl(c_rec.losses_gap_paid,0) - nvl(c_rec.losses_gap_recovered,0)
                        + nvl(c_rec.lae_gap_paid,0) - nvl(c_rec.lae_gap_recovered,0) + nvl(c_rec.tsc_paid,0)
                        + nvl(c_rec.loss_mit_purchase,0)
                        - nvl(c_rec.loss_mit_interest,0) --nvl(c_rec.wrap_bond_interest,0)
    ;
    v_interim_itd_recovered := c_rec.beg_itd_recovered_gaap + nvl(c_rec.losses_gap_recovered,0)
    ;
    v_interim_itd_lae_recovered := c_rec.beg_itd_lae_recovered_gaap + nvl(c_rec.lae_gap_recovered,0)
    ;
    v_interim_total_SnS := c_rec.beg_salvage_gaap
    ;
    v_beg_total_other_income := c_rec.beg_other_income --+ c_rec.beg_other_income_lae 
    ;
    v_ss_incurred_benefit := c_rec.beg_salv_res_incurred_benefit
    ;
    v_salv_res := c_rec.beg_salvage_gaap
    ;
    v_lae_salv_res := c_rec.beg_lae_salvage_gaap
    ;   
    v_total_expected_loss_stat := nvl(c_rec.gross_reserve,0) + nvl(c_rec.lae_sap_balance,0)
                             - nvl(c_rec.salvage_reserve,0) - nvl(c_rec.lae_salvage_sap_balance,0)
    ;    
              
-- determine SnS
    if v_total_expected_loss >= 0 then    
        v_interim_total_SnS := 0;
    else
        v_interim_total_SnS := -1 * v_total_expected_loss;
    end if; -- check expected loss

    v_qtd_SnS_delta := v_interim_total_SnS - (c_rec.beg_salvage_gaap + c_rec.beg_lae_salvage_gaap);
    

    v_reclass_direction := 0;
    -- new reclass logic base on incurred benefit concept
    case
        when (v_interim_total_contra >= 0 and v_qtd_SnS_delta <= 0) and  (v_ss_incurred_benefit + v_qtd_SnS_delta) >= 0
            then v_qtd_total_reclass := 0;
             -- SnS delta is < 0 (releasing paids), but we have enough incurred benefit to cover it, reclass is 0
        when (v_interim_total_contra >= 0 and v_qtd_SnS_delta <= 0) and  (v_ss_incurred_benefit + v_qtd_SnS_delta) < 0     
            then v_qtd_total_reclass := (v_ss_incurred_benefit + v_qtd_SnS_delta);
             -- otherwise, if we don't have enough incurred benefit, then reclass the remaining net paid as negative number (From SnS to Contra)
             v_reclass_direction := 1;
             -- this is the only case where we are reclassing From SnS to Contra
        when v_interim_total_contra >= 0 and v_qtd_SnS_delta > 0
            then v_qtd_total_reclass := least(v_qtd_SnS_delta, v_interim_total_contra); 
            -- if SnS delta is in recovery direction, and contra is in paid direction,
            -- then reclass contra paid into SnS, up until the reclass contra net the SnS delta to 0
            -- this corresponds to the idea of "prepayment for future recovery"

            -- we have covered all the case when contra is in paid direction,
        when v_interim_total_contra < 0 and (v_interim_total_SnS > 0 or c_rec.beg_salvage_gaap > 0)
            -- if contra is in recovery direction, as long as we are in SnS, all contra recovery is reclass to SnS
            then v_qtd_total_reclass := v_interim_total_contra;
            -- reclassing recovery need to be handle specially too
            v_reclass_direction := 2;
        else
            -- only remaining case is contra in recovery, and not in SnS, then reclass 0
            v_qtd_total_reclass := 0;
    end case; -- determine re-class 
    
    v_anticipated_SnS_total := -1 * (v_qtd_SnS_delta - v_qtd_total_reclass);    

    -- apportion re-class between paid and wrapped, part 1, from SnS to Contra
    case
    when v_reclass_direction = 1 then
    -- if we are moving paids from SnS to Contra, not moving Recovery, nor paids, from Contra to SnS
        v_contra_reclass_salv_paid := greatest(v_qtd_total_reclass, -1 * c_rec.beg_salv_gaap_paid);
        v_contra_reclass_salv_wrapped := v_qtd_total_reclass - v_contra_reclass_salv_paid;
    when v_reclass_direction = 2 then
    -- if we are moving recovery from contra to SnS, then the reclass CANNOT be from Loss MIT, so all from Paid
        v_contra_reclass_salv_paid := v_qtd_total_reclass;
        v_contra_reclass_salv_wrapped := 0;        
    else
    -- the remaining case is moving paids from Contra to SnS, but cannot apportion into Paid vs Loss MIT yet
    -- because Contra through PL has to be determined first 
    -- set to 0 for now, will get apportion later
        v_contra_reclass_salv_paid := 0;
        v_contra_reclass_salv_wrapped := 0;
    end case; -- apportion re-class part 1     

    -- add the reclass to the interim contra
    v_interim_total_contra := v_interim_total_contra - v_qtd_total_reclass;
    v_interim_contra_paid := v_interim_contra_paid - v_contra_reclass_salv_paid;
    v_interim_contra_wrapped := v_interim_contra_wrapped - v_contra_reclass_salv_wrapped;
    
    -- update the incurred benefit base on anticipated SnS, note the sign on Anticipated SnS
    -- plus is a paid/bad guy, minus is a benefit/good guy
    v_ss_incurred_benefit := greatest(v_ss_incurred_benefit - v_anticipated_SnS_total, 0);
    
    -- first check if we are in SnS, and if so, can we incur paids against incurred benefit
    if v_interim_total_SnS > 0 and v_interim_total_contra >= 0 and v_ss_incurred_benefit > 0 then
    -- we are in SnS, we have paids in contra, and we have incurred benefits,
    -- incur the paids in contra until incurred benefits becomes 0
        v_qtd_total_contra_pl := least(v_interim_total_contra, v_ss_incurred_benefit);
    -- and reduce the contra by what is incurred via this route, the remaining contra will go through UPR check
        v_interim_total_contra := v_interim_total_contra - v_qtd_total_contra_pl;

    end if;  -- check against incurred benefit

    -- deterimine contra through PnL via UPR check
    if v_interim_total_contra >= 0 then
    -- first when Contra is in paids direction 
        if v_total_expected_loss >= 0 then
            v_breach_check := v_interim_total_contra + v_total_expected_loss - v_modify_upr;
        else
            v_breach_check := v_interim_total_contra - v_modify_upr;
        end if;
        
        case
            when v_breach_check > 0
                then v_breach_amount := least(v_breach_check, v_interim_total_contra);  -- breaching
--            when v_breach_check <= 0 and (v_interim_total_SnS > 0 and v_beg_total_contra <= 0)
--                then v_breach_amount := v_interim_total_contra; -- not breaching, but in SnS, and no Contra paid before, ignore UPR check
-- replaced the above with Incurred Benefit concept
            else
                v_breach_amount := 0;
        end case;  -- when in contra paid direction
    else
    -- else when Contra is in recovery direction, v_interim_total_contra < 0
        case
            when v_interim_total_SnS > 0 or c_rec.beg_salvage_gaap > 0
                then v_breach_amount := 0;  -- in SnS situation, contra recovery gets reclass to SnS
            when v_total_expected_loss > 0 and (v_interim_total_contra + v_total_expected_loss > v_modify_upr)
                then v_breach_amount := v_interim_total_contra;
                 -- the total expected loss is breaching UPR, case reserve/LAE reserve > 0,do not set up contra, entire contra is breach amount
            when v_total_expected_loss >= 0 and (v_interim_total_contra + v_total_expected_loss < 0)
                then v_breach_amount := v_interim_total_contra + v_total_expected_loss;
                -- we have more recoveries than total expected loss, the excess recovery is the breach amount
            else
                v_breach_amount := 0;  -- otherwise contra through pnl is 0
        end case; -- when in contra recovery direction
            
    end if; -- determine contra through PnL  
    
    v_qtd_total_contra_pl := nvl(v_qtd_total_contra_pl,0) + v_breach_amount;
    v_end_total_contra := v_interim_total_contra - v_breach_amount;
    -- update the incurred benefit base on Contra Paid/Benefit through PL
    -- only contra paid through PL can reduce incurred benefit
    -- contra recovery through PL does NOT increase incurred benefit
    v_ss_incurred_benefit := greatest(v_ss_incurred_benefit - greatest(v_qtd_total_contra_pl,0), 0);    
    
    -- apportion contra through PnL between paids and wrapped bonds
    case
        when v_qtd_total_contra_pl > 0 and v_interim_contra_paid > 0
            then v_contra_pl_paid := least(v_qtd_total_contra_pl, v_interim_contra_paid);
    -- if we are taking paids through pnl, then priority is to exhaust regular contra paids first            
        when v_qtd_total_contra_pl > 0 and v_interim_contra_paid <= 0
            then v_contra_pl_paid := 0;
    -- but if we have no contra paids, then take it only from wrapped bond, and not add to contra recovery
        else
    -- if we are taking recovery through pnl, then only take it from regular contra, and not wrapped bond
            v_contra_pl_paid := v_qtd_total_contra_pl;
    end case;  -- apportion contra paids
    
    v_contra_pl_wrapped := v_qtd_total_contra_pl - v_contra_pl_paid;
    
    v_interim_contra_paid := v_interim_contra_paid - v_contra_pl_paid;
    v_interim_contra_wrapped := v_interim_contra_wrapped - v_contra_pl_wrapped;
   
    -- apportion re-class between paid and wrapped, part 2, from Contra to SnS
    if v_reclass_direction = 0 then
    -- anything not covered in part 1
    case
        when v_qtd_total_reclass > 0 and v_interim_contra_paid > 0
            then v_contra_reclass_salv_paid := least(v_qtd_total_reclass, v_interim_contra_paid);
    -- if we are reclassing paids from contra to SnS, then priority is to exhaust regular contra paids first
        when v_qtd_total_reclass > 0 and v_interim_contra_paid <= 0
            then v_contra_reclass_salv_paid := 0;
    -- but if we have no contra paids, then take it only from wrapped bond, and not add to contra recovery
        else
    -- if we are reclassing recovery from contra to SnS, then only take it from regular contra, and not wrapped bond
            v_contra_reclass_salv_paid := v_qtd_total_reclass;                
    end case; -- determine the paid portion
    
        v_contra_reclass_salv_wrapped := v_qtd_total_reclass - v_contra_reclass_salv_paid;

-- update the interim contra balance
    v_interim_contra_paid := v_interim_contra_paid - v_contra_reclass_salv_paid;
    v_interim_contra_wrapped := v_interim_contra_wrapped - v_contra_reclass_salv_wrapped;

    end if; -- apportion re-class part 2     
        
    v_interim_SnS_paid := c_rec.beg_salv_gaap_paid + v_contra_reclass_salv_paid;
    v_interim_SnS_wrapped := c_rec.beg_salv_gaap_loss_mit + v_contra_reclass_salv_wrapped;
    
    -- apportion the anticipated SnS
    case
        when v_anticipated_SnS_total < 0 then
-- if we are taking recovery to PnL, then only take it from paids, and not wrapped bonds
            v_anticipated_SnS_paid := v_anticipated_SnS_total;        
        when v_interim_SnS_paid < 0 then
-- if we have negative in SnS paid, as a result of large recovery received, then move the recovery to PnL    
            v_anticipated_SnS_paid := v_interim_SnS_paid;                
        when v_anticipated_SnS_total >= 0 then
-- if we are taking paids to PnL, then priority is to exhaust SnS of regular paids first    
        v_anticipated_SnS_paid := least(v_interim_SnS_paid, v_anticipated_SnS_total);                
        else
    -- there should be not else, since case 1 and 3 are compliment of each other, but leaving this just in case
            v_anticipated_SnS_paid := v_anticipated_SnS_total;
    end case; -- apportion anticipaed SnS
    
    v_anticipated_SnS_wrapped := v_anticipated_SnS_total - v_anticipated_SnS_paid;
    
    -- update the ending balance
    v_contra_bal_paid := v_interim_contra_paid;
    v_contra_bal_wrapped := v_interim_contra_wrapped;
    v_salvage_res_gaap_paid := v_interim_SnS_paid - v_anticipated_SnS_paid;
    v_salvage_res_gaap_wrapped := v_interim_SnS_wrapped - v_anticipated_SnS_wrapped;  
    
    v_salv_res := v_salvage_res_gaap_paid + v_salvage_res_gaap_wrapped;
     
    -- determine if LAE Salvage Reserve is needed
    if (nvl(c_rec.lae_salvage_gap_balance,0) - nvl(c_rec.lae_gap_balance,0)) > 0 and v_salv_res > 0 then
        v_salv_res := least(greatest(nvl(c_rec.salvage_reserve_gaap,0) - nvl(c_rec.gross_reserve_gaap,0), 0), v_salv_res);
          -- set up salvage reserve first
        v_lae_salv_res := (v_salvage_res_gaap_paid + v_salvage_res_gaap_wrapped) - v_salv_res; -- remaining is lae salvage
        -- LAE Salvage cannot come from Loss Mit, can it?  CAN IT?
--        v_salvage_res_gaap_paid := v_salvage_res_gaap_paid - v_lae_salv_res;
    else        
        v_lae_salv_res := 0;  -- if not expecting LAE salvage, set LAE Salv Reserve to 0, all salvage reserve goes to regular salvage
    end if;
    
    -- calculate the gaap case and LAE reserve
    v_breach_check := (v_total_expected_loss + v_contra_bal_paid + v_contra_bal_wrapped + v_salvage_res_gaap_paid + v_salvage_res_gaap_wrapped)
                        - v_modify_upr;
    case
        when v_breach_check <= 0 then
             v_case_res_gaap := 0;
             v_lae_res_gaap := 0;
        when (nvl(c_rec.gross_reserve_gaap,0) - nvl(c_rec.salvage_reserve_gaap,0)) <= 0 then
             v_case_res_gaap := 0;
             v_lae_res_gaap := v_breach_check;
        else  
             v_case_res_gaap := least(v_breach_check, nvl(c_rec.gross_reserve_gaap,0) - nvl(c_rec.salvage_reserve_gaap,0));
             v_lae_res_gaap := v_breach_check - v_case_res_gaap;
    end case; -- case and lae reserve  

-- GAAP other income logic is now at the end of everything
    case
    when v_bypass_other_income = true then
        v_other_income := c_rec.beg_other_income;
--        v_other_income_lae := c_rec.beg_other_income_lae;
        v_end_total_other_income := v_other_income; -- + v_other_income_lae;        
-- not bypass, check if we are incurring anything in Contra PL or Anticipated SnS
    else
--    when abs(v_qtd_total_contra_pl) + abs(v_anticipated_SnS_total) > 0 then
-- if we are, then check if some of the incur should be Other Income instead
-- rule is to see if we have more recoveries and/or expected recoveries than paids
        if (v_interim_itd_total_paids + v_total_expected_loss) < 0 then
            v_end_total_other_income := -1 * (v_interim_itd_total_paids + v_total_expected_loss);
        else
            v_end_total_other_income := 0;
        end if;        
--    else
-- if we did not incur anything, keeping the Other Income as it is    
--        v_other_income := c_rec.beg_other_income;
--        v_other_income_lae := c_rec.beg_other_income_lae;
--        v_end_total_other_income := v_other_income; -- + v_other_income_lae;    
    end case; -- bypass other income
    
-- check for override of other income
    if c_rec.or_other_income is not null then --or c_rec.or_other_income_lae is not null then
    -- if the user only override one other income category, but leave the other category override NULL, assume this NULL means 0
    -- the philosophy is, any override means rejecting the system calculation in whole; 
    -- we do not want a situation with one category is override, while the other is system calculated        
        v_other_income := nvl(c_rec.or_other_income,0) + c_rec.beg_other_income;
--        v_other_income_lae := nvl(c_rec.or_other_income_lae,0);
        v_end_total_other_income := v_other_income; -- + v_other_income_lae;
        v_qtd_other_income_change_rec := v_other_income - c_rec.beg_other_income;
--        v_qtd_other_income_change_lae := v_other_income_lae - c_rec.beg_other_income_lae;
        v_total_other_income_change := v_qtd_other_income_change_rec; -- + v_qtd_other_income_change_rec; 
    else
    -- no override, system calculates everything    
        v_total_other_income_change := v_end_total_other_income - v_beg_total_other_income;
/*    -- apportion other income between recovery and lae recovery    
        if v_total_other_income_change >= 0 then
    -- grearter than 0 means moving recovery into other income    
            v_qtd_other_income_change_rec := least(v_total_other_income_change, v_interim_itd_recovered);         
        else
    -- less than 0 means moving other income back into recovery
            v_qtd_other_income_change_rec := greatest(v_total_other_income_change, -1 * c_rec.beg_other_income);               
        end if;  -- check whether we are reclassing recoveries to other income, or vice versa 
    -- whatever left over after regular recoveries is lae recoveries  
        v_qtd_other_income_change_lae := v_total_other_income_change - v_qtd_other_income_change_rec;
*/
        v_qtd_other_income_change_rec := v_total_other_income_change;
        
        v_other_income := c_rec.beg_other_income + v_qtd_other_income_change_rec;
--        v_other_income_lae := c_rec.beg_other_income_lae + v_qtd_other_income_change_lae;
    
    end if; -- check other income override
    
-- update the Contra Paid PL if there is change to Other Income
-- Per accounting, all change to Other Income should flow through Contra Paid PL
    if v_total_other_income_change <> 0 then
        v_contra_pl_paid := v_contra_pl_paid + v_total_other_income_change;    
        v_qtd_total_contra_pl := v_contra_pl_paid + v_contra_pl_wrapped;    
    end if;    

-- new STAT other income logic
    case
    when v_bypass_other_income = true then
        v_other_income_stat := nvl(c_rec.beg_other_income_stat,0);        
-- not bypass, check ITD
    else
-- if we are, then check if some of the incur should be Other Income instead
-- rule is to see if we have more recoveries and/or expected recoveries than paids
-- note for stat, everything is incurred
        if (v_interim_itd_total_paids + v_total_expected_loss_stat) < 0 then
            v_other_income_stat := -1 * (v_interim_itd_total_paids + v_total_expected_loss_stat);
        else
            v_other_income_stat := 0;
        end if;         
    end case; -- bypass other income stat  
    
-- check for override of other income stat
    if c_rec.or_other_income_stat is not null then 
        v_other_income_stat := nvl(c_rec.or_other_income_stat,0) + nvl(c_rec.beg_other_income_stat,0);    
    end if; -- check other income override    
    
-- update STAT Recovered PL if there is change to Other Income
-- per accounting, all change to STAT other income should flow through STAT Recovered PL
    if v_other_income_stat - nvl(c_rec.beg_other_income_stat,0) <> 0 then
        v_stat_recovered_pl := nvl(c_rec.losses_sap_recovered,0) - (v_other_income_stat - nvl(c_rec.beg_other_income_stat,0));
    else        
        v_stat_recovered_pl := nvl(c_rec.losses_sap_recovered,0);
    end if;    

    -- update the end ITD paids
    v_end_itd_paid_gaap := c_rec.beg_itd_paid_gaap + nvl(c_rec.losses_gap_paid,0);
    v_end_itd_recovered_gaap := v_interim_itd_recovered;
    v_end_itd_lae_paid_gaap := c_rec.beg_itd_lae_paid_gaap + nvl(c_rec.lae_gap_paid,0);
    v_end_itd_lae_recovered_gaap := v_interim_itd_lae_recovered;
    v_end_itd_tsc_paid_gaap := c_rec.beg_itd_tsc_paid_gaap + nvl(c_rec.tsc_paid,0);
    v_end_itd_wrapped := c_rec.beg_itd_loss_mit + nvl(c_rec.loss_mit_purchase,0);
    v_end_itd_wrapped_int := c_rec.beg_itd_loss_mit_int + nvl(c_rec.loss_mit_interest,0);
    
    v_ibnr_res_gaap := c_rec.IBNR_GAP_BALANCE;
    v_gaap_pl_paid := v_contra_pl_paid;
    v_gaap_pl_loss_mit:= v_contra_pl_wrapped;                
                    
    end if; -- mtm, refi and FG logic branch

    -- checking override to see if they are in balance
    v_unbalance := (nvl(c_rec.or_contra_bal_paid, v_contra_bal_paid) - v_beg_contra_paid_and_cash)
                     + (nvl(c_rec.or_contra_pl_paid, v_contra_pl_paid) + nvl(c_rec.or_contra_reclass_salv_paid, v_contra_reclass_salv_paid))
                     - v_total_other_income_change; 
    if round(v_unbalance,2) <> 0 then
        abob_user.Spc_Debug(c_rec.losses_k||' losses_k Contra paid override out of balance');
    end if;

    v_unbalance := (nvl(c_rec.or_contra_bal_loss_mit, v_contra_bal_wrapped) - v_beg_contra_wrapped_and_cash)
                     + (nvl(c_rec.or_contra_pl_loss_mit, v_contra_pl_wrapped)
                         + nvl(c_rec.or_contra_reclass_sal_loss_mit, v_contra_reclass_salv_wrapped)); 
    if round(v_unbalance,2) <> 0 then
        abob_user.Spc_Debug(c_rec.losses_k||' losses_k Contra loss mit override out of balance');
    end if;

    v_unbalance := (nvl(c_rec.or_salvage_paid, v_salvage_res_gaap_paid) - c_rec.beg_salv_gaap_paid)
                     + (v_anticipated_SnS_paid - nvl(c_rec.or_contra_reclass_salv_paid, v_contra_reclass_salv_paid)); 
    if round(v_unbalance,2) <> 0 then
        abob_user.Spc_Debug(c_rec.losses_k||' losses_k SnS paid override out of balance');
    end if;

    v_unbalance := (nvl(c_rec.or_salvage_loss_mit, v_salvage_res_gaap_wrapped) - c_rec.beg_salv_gaap_loss_mit)
                     + (v_anticipated_SnS_wrapped - nvl(c_rec.or_contra_reclass_sal_loss_mit, v_contra_reclass_salv_wrapped)); 
    if round(v_unbalance,2) <> 0 then
        abob_user.Spc_Debug(c_rec.losses_k||' losses_k SnS loss mit override out of balance');
    end if;
    
    if not (c_rec.OR_OTHER_INCOME is null and
        c_rec.OR_CONTRA_BAL_PAID is null and
        c_rec.OR_CONTRA_BAL_LOSS_MIT is null and
        c_rec.OR_CONTRA_PL_PAID is null and
        c_rec.OR_CONTRA_PL_LOSS_MIT is null and
        c_rec.OR_CASE is null and
        c_rec.OR_SALVAGE_PAID is null and
        c_rec.OR_SALVAGE_LOSS_MIT is null and
        c_rec.OR_LAE is null and
        c_rec.OR_LAE_SALVAGE is null and
        c_rec.OR_CONTRA_RECLASS_SALV_PAID is null and
        c_rec.OR_CONTRA_RECLASS_SAL_LOSS_MIT is null and
        c_rec.OR_OTHER_INCOME_STAT is null)
         then
        
    v_calc_method := 
        case
        when p_refi or p_mtm then v_calc_method
        else 'O'
        end;
            
    end if;    

-- update the ending columns for GAAP and Contra, 29 columns
-- set GAAP reserve ending        
        c_rec.case_res_gaap := 
                case
                    when p_refi or p_mtm then v_case_res_gaap
                    else nvl(c_rec.or_case, v_case_res_gaap)
                end;
        c_rec.salvage_res_gaap := 
                case
                when p_refi or p_mtm then v_salv_res
                when c_rec.or_salvage_paid is not null or c_rec.or_salvage_loss_mit is not null then
                    nvl(c_rec.or_salvage_paid, 0) + nvl(c_rec.or_salvage_loss_mit, 0)
                      -- salvage is done by components, if the user override one, and left null in the other, interpret the null as 0
                else
                    v_salv_res                      
                end;
        c_rec.lae_res_gaap := 
            case
                when p_refi or p_mtm then v_lae_res_gaap
                else nvl(c_rec.or_lae, v_lae_res_gaap)
            end;
        c_rec.lae_salvage_res_gaap := 
            case
                when p_refi or p_mtm then v_lae_salv_res
                else nvl(c_rec.or_lae_salvage, v_lae_salv_res)
            end;
        c_rec.ibnr_res_gaap := v_ibnr_res_gaap;
-- set contra ending
        c_rec.contra_bal_paid := 
            case
                when p_refi or p_mtm then v_contra_bal_paid
                else nvl(c_rec.or_contra_bal_paid, v_contra_bal_paid)
            end;
--        c_rec.contra_bal_wrapped := nvl(c_rec.or_contra_bal_wrapped, v_contra_bal_wrapped);
        c_rec.contra_bal_loss_mit := 
            case
                when p_refi or p_mtm then v_contra_bal_wrapped
                else nvl(c_rec.or_contra_bal_loss_mit, v_contra_bal_wrapped)
            end;
        c_rec.salvage_res_gaap_paid := 
            case
                when p_refi or p_mtm then v_salvage_res_gaap_paid
                else nvl(c_rec.or_salvage_paid, v_salvage_res_gaap_paid)
            end;
--        c_rec.salvage_res_gaap_wrapped := nvl(c_rec.or_salvage_wrapped, v_salvage_res_gaap_wrapped);
        c_rec.salvage_res_gaap_loss_mit := 
            case
                when p_refi or p_mtm then v_salvage_res_gaap_wrapped
                else nvl(c_rec.or_salvage_loss_mit, v_salvage_res_gaap_wrapped)
            end;
        c_rec.other_income := v_other_income;
        c_rec.other_income_stat := v_other_income_stat;

-- set ITD payments ending
        c_rec.end_itd_paid_gaap := v_end_itd_paid_gaap;
        c_rec.end_itd_recovered_gaap := v_end_itd_recovered_gaap;
        c_rec.end_itd_lae_paid_gaap := v_end_itd_lae_paid_gaap;
        c_rec.end_itd_lae_recovered_gaap := v_end_itd_lae_recovered_gaap;
        c_rec.end_itd_tsc_paid_gaap := v_end_itd_tsc_paid_gaap;
--        c_rec.end_itd_wrapped := v_end_itd_wrapped;
        c_rec.end_itd_loss_mit := v_end_itd_wrapped;
--        c_rec.end_itd_wrapped_int := v_end_itd_wrapped_int;
        c_rec.end_itd_loss_mit_int := v_end_itd_wrapped_int;
-- set contra through PL, and reclass
        c_rec.contra_pl_paid := 
            case
                when p_refi or p_mtm then v_contra_pl_paid
                else nvl(c_rec.or_contra_pl_paid, v_contra_pl_paid)
            end;
--        c_rec.contra_pl_wrapped := nvl(c_rec.or_contra_pl_wrapped, v_contra_pl_wrapped);
        c_rec.contra_pl_loss_mit := 
            case
                when p_refi or p_mtm then v_contra_pl_wrapped
                else nvl(c_rec.or_contra_pl_loss_mit, v_contra_pl_wrapped)
            end;
        c_rec.contra_reclass_salv_paid := 
            case
                when p_refi or p_mtm then v_contra_reclass_salv_paid
                else nvl(c_rec.or_contra_reclass_salv_paid, v_contra_reclass_salv_paid)
            end;
--        c_rec.contra_reclass_salv_wrapped := nvl(c_rec.or_contra_reclass_salv_wrapped, v_contra_reclass_salv_wrapped);
        c_rec.contra_reclass_salv_loss_mit := 
            case
                when p_refi or p_mtm then v_contra_reclass_salv_wrapped
                else nvl(c_rec.or_contra_reclass_sal_loss_mit, v_contra_reclass_salv_wrapped)
            end;
        c_rec.calc_method := v_calc_method;
        c_rec.prev_qtr_contra_paid := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_paid
                else prev_rec.prev_qtr_contra_paid
            end;
        c_rec.prev_qtr_contra_loss_mit := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_loss_mit
                else prev_rec.prev_qtr_contra_loss_mit
            end;
        c_rec.gaap_pl_paid := 
            case
                when p_refi or p_mtm then v_gaap_pl_paid
                else nvl(c_rec.or_contra_pl_paid, v_contra_pl_paid)
            end;
        c_rec.gaap_pl_loss_mit := 
            case
                when p_refi or p_mtm then v_gaap_pl_loss_mit
                else nvl(c_rec.or_contra_pl_loss_mit, v_contra_pl_wrapped)
            end;         
        c_rec.stat_undiscounted_loss_res := nvl(c_rec.stat_undiscounted_loss_res,c_rec.beg_stat_undiscounted_loss_res);
        c_rec.stat_undiscounted_salv_res := nvl(c_rec.stat_undiscounted_salv_res,c_rec.beg_stat_undiscounted_salv_res);
        c_rec.salv_res_incurred_benefit := v_ss_incurred_benefit;              
        c_rec.stat_recovered_pl := v_stat_recovered_pl;            

    if p_batch_mode = true then
        batch_list_losses_rec(p_losses_k) := c_rec;    
    else

    update ABOB_USER.abob_tbl_losses set
-- update the beginning columns, 26 columns    
-- set the STAT beginning    
        beg_case_stat = c_rec.beg_case_stat,
        beg_salvage_stat = c_rec.beg_salvage_stat,
        beg_ibnr_stat = c_rec.beg_ibnr_stat,
        beg_lae_case_stat = c_rec.beg_lae_case_stat,
        beg_lae_salvage_stat = c_rec.beg_lae_salvage_stat,
        beg_stat_undiscounted_loss_res = c_rec.beg_stat_undiscounted_loss_res,
        beg_stat_undiscounted_salv_res = c_rec.beg_stat_undiscounted_salv_res,        
-- set GAAP reserve beginning        
        beg_case_gaap = c_rec.beg_case_gaap,
        beg_salvage_gaap = c_rec.beg_salvage_gaap,
        beg_lae_case_gaap = c_rec.beg_lae_case_gaap,
        beg_lae_salvage_gaap = c_rec.beg_lae_salvage_gaap,
        beg_ibnr_gaap = c_rec.beg_ibnr_gaap,
-- set contra beginning
        beg_contra_paid = c_rec.beg_contra_paid,
--        beg_contra_wrapped = c_rec.beg_contra_wrapped,
        beg_contra_loss_mit = c_rec.beg_contra_loss_mit,
        beg_salv_gaap_paid = c_rec.beg_salv_gaap_paid,
        beg_salv_gaap_loss_mit = c_rec.beg_salv_gaap_loss_mit,        
--        beg_salv_gaap_wrapped = c_rec.beg_salv_gaap_wrapped,
        beg_other_income = c_rec.beg_other_income,
        beg_other_income_stat = c_rec.beg_other_income_stat,
        beg_salv_res_incurred_benefit = c_rec.beg_salv_res_incurred_benefit,
-- set ITD payments beginning
        beg_itd_paid_gaap = c_rec.beg_itd_paid_gaap,
        beg_itd_recovered_gaap = c_rec.beg_itd_recovered_gaap,
        beg_itd_lae_paid_gaap = c_rec.beg_itd_lae_paid_gaap,
        beg_itd_lae_recovered_gaap = c_rec.beg_itd_lae_recovered_gaap,
        beg_itd_tsc_paid_gaap = c_rec.beg_itd_tsc_paid_gaap,
--        beg_itd_wrapped = c_rec.beg_itd_wrapped,
        beg_itd_loss_mit = c_rec.beg_itd_loss_mit,
--        beg_itd_wrapped_int = c_rec.beg_itd_wrapped_int,
        beg_itd_loss_mit_int = c_rec.beg_itd_loss_mit_int,
        beg_gaap_upr = c_rec.beg_gaap_upr,
-- GAAP expected beginning        
        BEG_EXP_CASE_GAAP = c_rec.BEG_EXP_CASE_GAAP,
        BEG_EXP_SALVAGE_GAAP = c_rec.BEG_EXP_SALVAGE_GAAP,
        BEG_EXP_LAE_CASE_GAAP = c_rec.BEG_EXP_LAE_CASE_GAAP,
        BEG_EXP_LAE_SALVAGE_GAAP = c_rec.BEG_EXP_LAE_SALVAGE_GAAP,           
 
-- update the ending columns for GAAP and Contra, 29 columns
-- set GAAP reserve ending        
        case_res_gaap = c_rec.case_res_gaap,
        salvage_res_gaap = c_rec.salvage_res_gaap,
        lae_res_gaap = c_rec.lae_res_gaap,
        lae_salvage_res_gaap = c_rec.lae_salvage_res_gaap,
        ibnr_res_gaap = c_rec.ibnr_res_gaap,
-- set contra ending
        contra_bal_paid = c_rec.contra_bal_paid,
--        contra_bal_wrapped = c_rec.contra_bal_wrapped,
        contra_bal_loss_mit = c_rec.contra_bal_loss_mit,
        salvage_res_gaap_paid = c_rec.salvage_res_gaap_paid,
--        salvage_res_gaap_wrapped = c_rec.salvage_res_gaap_wrapped,
        salvage_res_gaap_loss_mit = c_rec.salvage_res_gaap_loss_mit,
        other_income = c_rec.other_income,
        other_income_stat = c_rec.other_income_stat,
-- set ITD payments beginning
        end_itd_paid_gaap = c_rec.end_itd_paid_gaap,
        end_itd_recovered_gaap = c_rec.end_itd_recovered_gaap,
        end_itd_lae_paid_gaap = c_rec.end_itd_lae_paid_gaap,
        end_itd_lae_recovered_gaap = c_rec.end_itd_lae_recovered_gaap,
        end_itd_tsc_paid_gaap = c_rec.end_itd_tsc_paid_gaap,
--        end_itd_wrapped = c_rec.end_itd_wrapped,
        end_itd_loss_mit = c_rec.end_itd_loss_mit,
--        end_itd_wrapped_int = c_rec.end_itd_wrapped_int,
        end_itd_loss_mit_int = c_rec.end_itd_loss_mit_int,
-- contra through PL, and reclass
        contra_pl_paid = c_rec.contra_pl_paid,
--        contra_pl_wrapped = c_rec.contra_pl_wrapped,
        contra_pl_loss_mit = c_rec.contra_pl_loss_mit,
        contra_reclass_salv_paid = c_rec.contra_reclass_salv_paid,
--        contra_reclass_salv_wrapped = c_rec.contra_reclass_salv_wrapped
        contra_reclass_salv_loss_mit = c_rec.contra_reclass_salv_loss_mit,
        calc_method = c_rec.calc_method,
        prev_qtr_contra_paid = c_rec.prev_qtr_contra_paid,
        prev_qtr_contra_loss_mit = c_rec.prev_qtr_contra_loss_mit,  
        gaap_pl_paid = c_rec.gaap_pl_paid,
        gaap_pl_loss_mit = c_rec.gaap_pl_loss_mit,
        stat_undiscounted_loss_res = c_rec.stat_undiscounted_loss_res,
        stat_undiscounted_salv_res = c_rec.stat_undiscounted_salv_res,
        salv_res_incurred_benefit = c_rec.salv_res_incurred_benefit,
        stat_recovered_pl = c_rec.stat_recovered_pl   
    where current of curr_losses_row;         

    close curr_losses_row;
    
    end if; -- batch mode switch

EXCEPTION
    WHEN OTHERS THEN

        IF curr_losses_row%isopen THEN
            close curr_losses_row;
        END IF;

        raise_application_error(-20002,'contra_loss_calc_quarterly - losses_k '||p_losses_k||sqlerrm);
    
  END; -- contra_loss_calc_quarterly
  
PROCEDURE ABOB_SPC_LOSSES_CALC (
    a_rev_gig_k IN abob_tbl_lossgig.rev_gig_k%type,
    a_year IN abob_tbl_loss_years.acct_yr%type,
    a_month      IN abob_tbl_losses.month%type,
    a_currency  IN abob_tbl_losses.currency_desc_k%type
    ,p_batch_mode in boolean default false) IS
/*
FILE u:\pb\beta\abob32\sql\sp_loss.sql
This procedure will recalculate all calculated columns from abob_tbl_losses for given record
and all subsequent records.

Call after changing a user entered column (reserves,paid,incurred) pass in rev_gig_k, year,
month of changed record

This procedure is called by  ABOB_USER.ABOB_PKG_FXRATE_PROP

Created by Tony Heavey on 04/21/97
Moved into PKG_Loss_Contra by Yushi Yang on 9/16/2015

CHANGES:
    11/21/97 - updated for fx
    03/03/98 - doesnt process if the losses are uploaded from and exposure system
    03/24/98 - was causing error if premium records didnt exits for year, month, gig that
               was changed this is ok.
    05/15/98 - FX ibnr to usd error
    xx/xx/98 - AJH - dont calc if losses have been uploaded for gig/year/month
    08/03/98 - AJH inserted abob_fun_losses_aggregate to keep aggregate table in sync
               table is for cash offsets
    08/28/98 - AJH parameters for abob_fun_losses_aggregate changed to include currency
    11/25/98 - AJH updated for year 2000

    08/23/99 - CJC modified to accomodate loss adjustments
    02/01/00 - AJH ok to have usd but no local premium  
    06/22/09 - VCP added Transition Adjustment to calculations  
    08/12/09 - JLH  added IBNR Transition Adjustment to calculations
    03/26/13 - AJH  top10-2 modified for new fields       
    03/13/15 - VCP added transition adjustments for Radian integration 
    08/21/15 - YY   added call to contra loss package, additional complexity of Inter_side on losses table
            - also not update f_gaap_upr anymore
            - also move the standalone procedure into pkg_loss_contra for better organization, and batch processing  
   3/28/2017       yyang       Add handling of newly created loss record properly in ABOB_SPC_LOSSES_CALC
*/

lb_process boolean := false;  -- indicates when cursor should start processing.
                                      -- First record processed MAY be record prior to first
                              -- processed.
l_cnt      number := 0;
l_count      number;
l_fx_rate number; -- fx rate as of a given month

l_return char(20); --return code from function;

l_month abob_user.abob_tbl_losses.month%type;        -- prior to argument month. used to get previous reserves
l_year  abob_user.abob_tbl_loss_years.acct_yr%type; -- year of month prior to argument year/month. used to get previous reserves

l_gig_k abob_user.abob_tbl_corp_gig.corp_gig_k%type;
l_system abob_user.abob_tbl_corp_gig.system%type;               -- the system of the gig

l_etd_wp_usd abob_user.abob_tbl_boba_premium.wp_act_stat%type;   -- etd US wp as of the month in the loop
l_etd_wp_local abob_user.abob_tbl_boba_premium.wp_act_stat%type; -- etd local wp as of the month in the loop

l_tot_res_gap abob_user.abob_tbl_losses.gross_reserve%type;
l_tot_res_sap abob_user.abob_tbl_losses.gross_reserve%type;

v_mtm   boolean;
v_ReFi  boolean;
v_temp  varchar(10);
v_prev_losses_k ABOB_USER.ABOB_TBL_LOSSES.LOSSES_K%type;
v_terminated boolean;

-- records from abob_tbl_losses.
-- starting with month prior to changed month and including all subsequent months
-- In local currency

cursor cur_records is
    select
        losses_k,
        ly.acct_yr,
        l.month,
        l.lacctyr_k,
        gross_reserve,
        salvage_reserve,
        ibnr_sap_balance,
        losses_sap_balance,
        losses_sap_incurred,
        losses_sap_paid,
        losses_sap_recovered,
        lae_sap_balance,
        lae_sap_paid,
        lae_sap_incurred,
        lae_sap_recovered,
        gross_reserve_gaap,
        salvage_reserve_gaap,
        ibnr_gap_balance,
        losses_gap_balance,
        losses_gap_incurred,
        losses_gap_paid,
        losses_gap_recovered,
        lae_gap_balance,
        lae_gap_paid,
        lae_gap_incurred,
        lae_gap_recovered, 
        f_gaap_upr,     -- Radian 
        r_sap_gross,
        r_sap_salvage,
        r_sap_ibnr,
        r_sap_lae_gross,
        r_gap_gross,
        r_gap_salvage,
        r_gap_ibnr,
        r_gap_lae_gross,
        rate_override,
        losses_sap_paid_adj,
        losses_sap_recovered_adj,
        lae_sap_paid_adj,
        lae_sap_recovered_adj,
        case_reserve_gaap_ta,
        salvage_reserve_gaap_ta,
        ibnr_gaap_ta,
        lae_salvage_sap_balance, --top10-2 
        lae_salvage_gap_balance, -- top10-2
        r_sap_lae_salvage_gross,  -- top10-2
        r_gap_lae_salvage_gross,  -- top10-2
        gross_reserve_ta, 
        ibnr_sap_balance_ta, 
        salvage_reserve_ta, 
        lae_sap_balance_ta, 
        lae_gap_balance_ta, 
        lae_salvage_sap_balance_ta, 
        lae_salvage_gap_balance_ta, 
        f_gaap_upr_ta,
        l.inter_side 
    FROM
        abob_user.abob_tbl_losses l,
        abob_user.abob_tbl_loss_years ly
    WHERE
        ly.lacctyr_k = l.lacctyr_k AND
        ly.rev_gig_k = a_rev_gig_k  AND
        l.currency_desc_k = a_currency  AND
        l.deal_currency    = 'T'  and
        (ly.acct_yr    > l_year OR  (ly.acct_yr    = l_year and l.month >= l_month))
    ORDER BY
        l.inter_side asc,
        ly.acct_yr,
        l.month;

prev_rec cur_records%rowtype; -- stores previous month cur_records record
--c_rec cur_records%rowtype;

-- ibnr for month prior to changed month and all subsequent months
-- in USD.  users enter IBNR in us dollars and local currency (abob does no translation)

cursor cur_records_usd is
    select
        r_sap_ibnr,
        r_gap_ibnr,
        ibnr_sap_balance,
        ibnr_gap_balance,
        ibnr_gaap_ta, 
        ibnr_sap_balance_ta 
    FROM
        abob_user.abob_tbl_losses     l,
        abob_user.abob_tbl_loss_years ly
    WHERE
        ly.lacctyr_k        = l.lacctyr_k  AND
        ly.rev_gig_k          = a_rev_gig_k AND
        l.currency_desc_k = a_currency  AND
        l.usd                = 'T'  and
        (ly.acct_yr        > l_year OR (ly.acct_yr = l_year and l.month >= l_month))
    ORDER BY
        l.inter_side,
        ly.acct_yr,
        l.month;

prev_rec_usd cur_records_usd%rowtype; -- stores previous month cur_records record
c_rec_usd cur_records_usd%rowtype;

-- wp in usd and fx for each month for a particular gig and currency

CURSOR CUR_WP IS
    select
        record_date,
        sum(nvl(nvl(bp.wp_act_stat,bp.wp_acc_stat)           ,0) + nvl(bp.wp_adj_stat      ,0)) wp_local,
        sum(nvl(nvl(bp_usd.wp_act_stat,bp_usd.wp_acc_stat),0) + nvl(bp_usd.wp_adj_stat,0)) wp_usd
    from
        abob_user.abob_tbl_boba           b ,
        abob_user.abob_tbl_segment       s ,
        abob_user.abob_tbl_boba_premium bp,
        abob_user.abob_tbl_boba_premium bp_usd
    where
        bp.boba_k         = b.boba_k and
        b.boba_k               = bp_usd.boba_k and
        b.segment_k           = s.segment_k and
        s.corp_gig_k           = l_gig_k and
        b.currency_desc_k = a_currency and
        bp.usd             = 'F'and
        bp_usd.usd         = 'T'
    group by record_date
    order by record_date;

rec_wp cur_wp%rowtype;

BEGIN


/* dont recalc if losses are uploaded*/

select gig_k
  into l_gig_k
  from abob_user.abob_tbl_lossgig
 where rev_gig_k = a_rev_gig_k;
 
-- determine if this gig has been terminated
    if lst_gig_term_date.exists(l_gig_k) then
-- we have this gig
        case
            when lst_gig_term_date(l_gig_k).origin_co > 100 and lst_gig_term_date(l_gig_k).owner_co < 100 then
                v_terminated := false;  -- direct/external assumed policy, never terminated for loss purpose
            when nvl(lst_gig_term_date(l_gig_k).terminate_dt,lst_gig_term_date(l_gig_k).stop_dt) is not null
                 and nvl(lst_gig_term_date(l_gig_k).terminate_dt,lst_gig_term_date(l_gig_k).stop_dt) 
                    < to_date(a_month||'/1/'||a_year,'mm/dd/yyyy') then                    
                v_terminated := true;  -- non direct/external assumed, terminate/stop date before accounting month
            else
                v_terminated := false; 
        end case;
    else    
        v_terminated := false;        
    end if;
    
-- determine whether the policy is MTM or ReFi 
    v_temp := null
    ;
    begin    
    select distinct
     cg.mtm_flg
    into v_temp
    from ABOB_USER.abob_tbl_lossgig lg, ABOB_USER.abob_tbl_corp_gig cg
    where lg.rev_gig_k = a_rev_gig_k
    and LG.GIG_K = CG.CORP_GIG_K
    and CG.LINE_OF_BUSINESS in (1,8)
    ;
    -- only policy in FG (1) or Derivative (8) line of business, and MTM = N are candidate for Contra     
    exception when no_data_found then
        v_temp := null;
    end
    ;
    if nvl(v_temp,'Y') = 'N' then
        v_mtm := false;
    else
        v_mtm := true;  -- all other follows MTM logic (basically GAAP = STAT)
    end if
    ;    
    v_temp := null
    ;
    begin    
    select distinct
     gg.group_d
    into v_temp
    from ABOB_USER.abob_tbl_lossgig lg, ABOB_USER.abob_tbl_gig_group gg
    where lg.rev_gig_k = a_rev_gig_k
    and LG.GIG_K = GG.GIG_K
    and upper(GG.GROUP_D) = 'REFI'
    ;
    exception when no_data_found then
        v_temp := null;
    end
    ;     
    if upper(v_temp) = 'REFI' then
        v_ReFi := true;
    else
        v_ReFi := false;
    end if
    ;      

select count(*) into l_count
  from gbl_user.gbl_tbl_prem_pipe
 where gig_k = l_gig_k and pending_status >= 99;

select upper(g.system)
  into l_system
  from abob_user.abob_tbl_corp_gig g
 where g.corp_gig_k = l_gig_k;

l_etd_wp_local :=0;
l_etd_wp_usd   :=0;

-- month prior to changed month

IF a_month = 1 THEN
    l_month :=12;
    l_year  := a_year -1;
ELSE
    l_month := a_month - 1;
    l_year  := a_year;
END IF;

IF a_currency <> 10000038 THEN  -- FX
    open cur_wp; -- ALL wp records for gig and currency. in usd and local
END IF;


-- implicitly open cursor.  Flip through records and do calculations

open cur_records_usd; -- ibnr in usd for month prior to changed record and all subsequent records

FOR c_rec IN cur_records LOOP -- losses records for for month prior to changed record and all subsequent records

    fetch cur_records_usd into c_rec_usd;
    
--    abob_user.Spc_Debug('abob_spc_loss_calc - processing Losses_k: '|| c_rec.losses_k);    
    -- YY, with addition of inter_side, we cursor through both assumed and ceded in one go, so need a reset when switching from A to C
    -- YY, 3/28/2017, also need to reset the prev_rec to NULL
    -- if either one is NULL, also should reset too (the valide letters are only A and C), default to Q and P will always cause NULL to mismatch
    if nvl(c_rec.inter_side,'Q') <> nvl(prev_rec.inter_side, 'P') then
        lb_process := false;
        l_cnt := 0;
        prev_rec     := NULL;
        prev_rec_usd := NULL;        
    end if;
    
    -- if no prior month existed procedure should begin calculating on first record in cursor.
    -- if prior month exists it is being used just to get previous reserve numbers

    IF lb_process = FALSE THEN
        IF ((c_rec.acct_yr*100) + c_rec.month) >= ((a_year*100)+a_month) THEN
            lb_process :=TRUE;
        END IF;
    END IF;
    IF lb_process THEN
        /*  IF USER HAS ENTERED A RESERVE USE IT AS THIS MONTHS RESERVE.
            IF NOT USE LAST MONTHS RESERVE */

        -- STAT CASE

        IF c_rec.r_sap_gross IS NULL THEN
           c_rec.gross_reserve := nvl(prev_rec.gross_reserve,0) + nvl(c_rec.gross_reserve_ta,0);  
        ELSE
           c_rec.gross_reserve := c_rec.r_sap_gross;
        END IF;

        -- STAT SALVAGE

        IF c_rec.r_sap_salvage IS NULL THEN
           c_rec.salvage_reserve := nvl(prev_rec.salvage_reserve,0) + nvl(c_rec.salvage_reserve_ta,0); 
        ELSE
           c_rec.salvage_reserve := c_rec.r_sap_salvage;
        END IF;

        -- STAT IBNR

        IF c_rec.r_sap_ibnr IS NULL THEN
           c_rec.ibnr_sap_balance := nvl(prev_rec.ibnr_sap_balance,0) + nvl(c_rec.ibnr_sap_balance_ta,0); 
        ELSE
           c_rec.ibnr_sap_balance := c_rec.r_sap_ibnr;
        END IF;

        -- STAT LAE
        IF c_rec.r_sap_lae_gross IS NULL THEN
           c_rec.lae_sap_balance := nvl(prev_rec.lae_sap_balance,0) + nvl(c_rec.lae_sap_balance_ta,0); 
        ELSE
           c_rec.lae_sap_balance := c_rec.r_sap_lae_gross;
        END IF;

        -- STAT LAE SALVAGE
        -- top10-2
        IF c_rec.r_sap_lae_salvage_gross IS NULL THEN
           c_rec.lae_salvage_sap_balance := nvl(prev_rec.lae_salvage_sap_balance,0) + nvl(c_rec.lae_salvage_sap_balance_ta,0); 
        ELSE
           c_rec.lae_salvage_sap_balance := c_rec.r_sap_lae_salvage_gross;
        END IF;


        /**********************************************GAAP SECTION********************************************/

        -- GAAP CASE

        IF c_rec.r_gap_gross IS NULL THEN
           c_rec.gross_reserve_gaap := nvl(prev_rec.gross_reserve_gaap,0) + nvl(c_rec.case_reserve_gaap_ta,0);  
        ELSE
           c_rec.gross_reserve_gaap := c_rec.r_gap_gross;
        END IF;

        -- GAAP SALVAGE

        IF c_rec.r_gap_salvage IS NULL THEN
           c_rec.salvage_reserve_gaap := nvl(prev_rec.salvage_reserve_gaap,0) + nvl(c_rec.salvage_reserve_gaap_ta,0);       
        ELSE
           c_rec.salvage_reserve_gaap := c_rec.r_gap_salvage;
        END IF;

        -- GAAP IBNR

        IF c_rec.r_gap_ibnr IS NULL THEN
           c_rec.ibnr_gap_balance := nvl(prev_rec.ibnr_gap_balance,0) + nvl(c_rec.ibnr_gaap_ta,0);
        ELSE
           c_rec.ibnr_gap_balance := c_rec.r_gap_ibnr;
        END IF;

        -- GAAP LAE

        IF c_rec.r_gap_lae_gross IS NULL THEN
           c_rec.lae_gap_balance := nvl(prev_rec.lae_gap_balance,0) + nvl(c_rec.lae_gap_balance_ta,0); 
        ELSE
           c_rec.lae_gap_balance := c_rec.r_gap_lae_gross;
        END IF;

        -- GAAP LAE
        -- top10-2
        IF c_rec.r_gap_lae_salvage_gross IS NULL THEN
           c_rec.lae_salvage_gap_balance := nvl(prev_rec.lae_salvage_gap_balance,0)  + nvl(c_rec.lae_salvage_gap_balance_ta,0); 
        ELSE
           c_rec.lae_salvage_gap_balance := c_rec.r_gap_lae_salvage_gross;
        END IF;

        -- GAAP UPR  -- YY no longer update UPR here
--        c_rec.f_gaap_upr := nvl(prev_rec.f_gaap_upr,0) + nvl(c_rec.f_gaap_upr_ta,0);       



        /* CALCULATE TOTAL RESERVES AND INCURRED */
        
        -- add transition adjustment to previous gaap balances  
        
        prev_rec.losses_gap_balance := nvl(prev_rec.losses_gap_balance,0) + nvl(c_rec.case_reserve_gaap_ta,0) - nvl(c_rec.salvage_reserve_gaap_ta,0) + nvl(c_rec.ibnr_gaap_ta,0);  
        prev_rec.ibnr_gap_balance := nvl(prev_rec.ibnr_gap_balance,0) + nvl(c_rec.ibnr_gaap_ta,0); 
        prev_rec.f_gaap_upr := nvl(prev_rec.f_gaap_upr,0) + nvl(c_rec.f_gaap_upr_ta,0); 

        -- 03/13/15 VCP  Radian integration 
        -- also add transition adjustment to previous stat balances  
        prev_rec.losses_sap_balance := nvl(prev_rec.losses_sap_balance,0) + nvl(c_rec.gross_reserve_ta,0) - nvl(c_rec.salvage_reserve_ta,0) + nvl(c_rec.ibnr_sap_balance_ta,0);  
        prev_rec.ibnr_sap_balance := nvl(prev_rec.ibnr_sap_balance,0) + nvl(c_rec.ibnr_sap_balance_ta,0); 

        -- 03/13/15 VCP 
        -- add the same calculations here for prev_rec balances for 
        -- LAE Stat and LAE GAAP and SALVAGE Stat and SALVAGE GAAP reserves 
        prev_rec.lae_gap_balance            := nvl(prev_rec.lae_gap_balance,0) + nvl(c_rec.lae_gap_balance_ta,0); 
        prev_rec.lae_salvage_gap_balance    := nvl(prev_rec.lae_salvage_gap_balance,0) + nvl(c_rec.lae_salvage_gap_balance_ta,0); 
        
        prev_rec.lae_sap_balance            := nvl(prev_rec.lae_sap_balance,0) + nvl(c_rec.lae_sap_balance_ta,0); 
        prev_rec.lae_salvage_sap_balance    := nvl(prev_rec.lae_salvage_sap_balance,0) + nvl(c_rec.lae_salvage_sap_balance_ta,0); 

       
        -- total reserves = gross - salvage + ibnr

        c_rec.losses_sap_balance := c_rec.gross_reserve         - c_rec.salvage_reserve      + c_rec.ibnr_sap_balance;
        c_rec.losses_gap_balance := c_rec.gross_reserve_gaap - c_rec.salvage_reserve_gaap + c_rec.ibnr_gap_balance;

        -- incurred = change in reserves + paid - recovered

        c_rec.losses_sap_incurred := (c_rec.losses_sap_balance      - nvl(prev_rec.losses_sap_balance     ,0))
                                   + (c_rec.losses_sap_paid         + nvl(c_rec.losses_sap_paid_adj     ,0))
                                   - (c_rec.losses_sap_recovered + nvl(c_rec.losses_sap_recovered_adj,0));

        c_rec.losses_gap_incurred := (c_rec.losses_gap_balance   - nvl(prev_rec.losses_gap_balance     ,0))
                                   + (c_rec.losses_gap_paid         + nvl(c_rec.losses_sap_paid_adj     ,0))
                                   - (c_rec.losses_gap_recovered + nvl(c_rec.losses_sap_recovered_adj,0));

        -- LAE incurred = change in reserves + paid - recovered  

        c_rec.lae_sap_incurred := (c_rec.lae_sap_balance   - nvl(prev_rec.lae_sap_balance,0))
                                - (c_rec.lae_salvage_sap_balance  - nvl(prev_rec.lae_salvage_sap_balance,0)) --top10-2
                                + (c_rec.lae_sap_paid       + nvl(c_rec.lae_sap_paid_adj        ,0))
                                - (c_rec.lae_sap_recovered + nvl(c_rec.lae_sap_recovered_adj,0));

        c_rec.lae_gap_incurred := (c_rec.lae_gap_balance   - nvl(prev_rec.lae_gap_balance    ,0))
                                - (c_rec.lae_salvage_gap_balance   - nvl(prev_rec.lae_salvage_gap_balance,0)) --top10-2
                                + (c_rec.lae_gap_paid       + nvl(c_rec.lae_sap_paid_adj        ,0))
                                - (c_rec.lae_gap_recovered + nvl(c_rec.lae_sap_recovered_adj,0));

       -- update local currency record
    if p_batch_mode = true then
    -- batch mode, store the current loss row in an associative array, make all
    -- the updates to the array (here and in the contra sub-routine, then make one update for all loss rows

    -- check if the element is in the array yet        
        if not batch_list_losses_rec.exists(c_rec.losses_k) then
            select * 
            into losses_row
            from abob_user.abob_tbl_losses
            where losses_k = c_rec.losses_k
            ;
            batch_list_losses_rec(c_rec.losses_k) := losses_row
            ;        
            batch_list_losses_key(batch_list_losses_key.count + 1) := c_rec.losses_k
            ;
        end if;
    
    -- update the element in the array
         batch_list_losses_rec(c_rec.losses_k).losses_sap_balance := c_rec.losses_sap_balance;
         batch_list_losses_rec(c_rec.losses_k).losses_sap_incurred := c_rec.losses_sap_incurred;
         batch_list_losses_rec(c_rec.losses_k).lae_sap_incurred := c_rec.lae_sap_incurred;
         batch_list_losses_rec(c_rec.losses_k).gross_reserve := c_rec.gross_reserve;
         batch_list_losses_rec(c_rec.losses_k).salvage_reserve := c_rec.salvage_reserve;
         batch_list_losses_rec(c_rec.losses_k).ibnr_sap_balance := c_rec.ibnr_sap_balance;
         batch_list_losses_rec(c_rec.losses_k).lae_sap_balance := c_rec.lae_sap_balance;
         batch_list_losses_rec(c_rec.losses_k).lae_salvage_sap_balance := c_rec.lae_salvage_sap_balance;
         batch_list_losses_rec(c_rec.losses_k).losses_gap_balance := c_rec.losses_gap_balance;
         batch_list_losses_rec(c_rec.losses_k).losses_gap_incurred := c_rec.losses_gap_incurred;
         batch_list_losses_rec(c_rec.losses_k).lae_gap_incurred := c_rec.lae_gap_incurred;
         batch_list_losses_rec(c_rec.losses_k).gross_reserve_gaap := c_rec.gross_reserve_gaap;
         batch_list_losses_rec(c_rec.losses_k).salvage_reserve_gaap := c_rec.salvage_reserve_gaap;
         batch_list_losses_rec(c_rec.losses_k).ibnr_gap_balance := c_rec.ibnr_gap_balance;
         batch_list_losses_rec(c_rec.losses_k).lae_gap_balance := c_rec.lae_gap_balance; 
         batch_list_losses_rec(c_rec.losses_k).lae_salvage_gap_balance := c_rec.lae_salvage_gap_balance;
    
    else
        UPDATE abob_user.abob_tbl_losses
        SET
            losses_sap_balance   = c_rec.losses_sap_balance,
            losses_sap_incurred  = c_rec.losses_sap_incurred,
            lae_sap_incurred       = c_rec.lae_sap_incurred,
            gross_reserve           = c_rec.gross_reserve,
            salvage_reserve        = c_rec.salvage_reserve,
            ibnr_sap_balance       = c_rec.ibnr_sap_balance,
            lae_sap_balance         = c_rec.lae_sap_balance,
            lae_salvage_sap_balance = c_rec.lae_salvage_sap_balance, -- top10-2
            losses_gap_balance   = c_rec.losses_gap_balance,
            losses_gap_incurred  = c_rec.losses_gap_incurred,
            lae_gap_incurred       = c_rec.lae_gap_incurred,
            gross_reserve_gaap   = c_rec.gross_reserve_gaap,
            salvage_reserve_gaap = c_rec.salvage_reserve_gaap,
            ibnr_gap_balance       = c_rec.ibnr_gap_balance,
            lae_gap_balance       = c_rec.lae_gap_balance, 
            lae_salvage_gap_balance = c_rec.lae_salvage_gap_balance  --top10-2
--            f_gaap_upr           = c_rec.f_gaap_upr  -- Radian    -- YY no longer update UPR per Contra project
        WHERE losses_k = c_rec.losses_k;
        IF sql%rowcount <> 1 THEN
            raise_application_error(-20005,'Unable to update losses in abob_spc_losses_calc for ' || l_month || '/' || l_year);
        END IF;
    end if; -- batch mode switch
    
        -- IF FX.
        IF a_currency <> 10000038 THEN
           -- calc etd wp through current month
            WHILE nvl(rec_wp.record_date,to_date('01/01/1987','MM/DD/YYYY')) < to_date('01/' || c_rec.month || '/' ||c_rec.acct_yr, 'dd/mm/yyyy') LOOP

                rec_wp.wp_usd := 0;
                rec_wp.wp_local := 0;
                fetch cur_wp into rec_wp;

             IF cur_wp%notfound THEN
                exit;
                -- removed 03/24/98 AJH
                --raise_application_error(-20005,'Ran out of WP records in abob_spc_losses_calc. CONTACT MIS.'|| a_rev_gig_k ||'x'||a_year||'x'|| a_month ||'x'||a_currency||'x'||l_gig);
             END IF;

              l_etd_wp_usd    := l_etd_wp_usd      + rec_wp.wp_usd;
             l_etd_wp_local := l_etd_wp_local + rec_wp.wp_local;

          END LOOP;

            -- calc etd exchange rate based on written premium
            IF c_rec.rate_override is not null THEN
                l_fx_rate := c_rec.rate_override;
            ELSIF l_etd_wp_usd <> 0 and l_etd_wp_local <> 0 THEN
                l_fx_rate := round(l_etd_wp_usd / l_etd_wp_local,6);
            ELSE -- get the rate from the currency table

                select euro_currency_rate_usd
                into l_fx_rate
                from gbl_user.gbl_tbl_currency_month
                where
                    currency_desc_k = a_currency and
                    to_char(currency_year) || to_char(currency_month,'00') =
                        (select max(to_char(currency_year) || to_char(currency_month,'00'))
                        from gbl_user.gbl_tbl_currency_month
                        where
                            currency_desc_k = a_currency and
                            to_char(currency_year) || to_char(currency_month,'00') <= to_char((c_rec.acct_yr * 100) + c_rec.month));


              if l_fx_rate is null or l_fx_rate = 0 then
                   raise_application_error(-20001,'The currency conversion rate could not be determined for currency_k = ' || a_currency ||' year = ' || c_rec.acct_yr || ' month = ' ||c_rec.month || ' in abob_spc_losses_calc.');
              end if;
          END IF;
          
          -- update prev balance with IBNR transition adjustment  
          prev_rec_usd.ibnr_gap_balance := nvl(prev_rec_usd.ibnr_gap_balance,0) + nvl(c_rec_usd.ibnr_gaap_ta,0); 
          -- 03/13/15 VCP also update the prev stat balance with the IBNR transition adjustment 
          prev_rec_usd.ibnr_sap_balance := nvl(prev_rec_usd.ibnr_sap_balance,0) + nvl(c_rec_usd.ibnr_sap_balance_ta,0); 

          -- UPDATE USD TRANSLATION RECORDS
          -- IBNR is done in pb user interface since it is entered by the user
          c_rec_usd.ibnr_sap_balance := nvl(c_rec_usd.r_sap_ibnr,nvl(prev_rec_usd.ibnr_sap_balance,0));
          c_rec_usd.ibnr_gap_balance := nvl(c_rec_usd.r_gap_ibnr,nvl(prev_rec_usd.ibnr_gap_balance,0));

          l_tot_res_sap := ((c_rec.gross_reserve      - c_rec.salvage_reserve)         * l_fx_rate) + c_rec_usd.ibnr_sap_balance;
          l_tot_res_gap := ((c_rec.gross_reserve_gaap - c_rec.salvage_reserve_gaap) * l_fx_rate) + c_rec_usd.ibnr_gap_balance;

        select * 
        into losses_row
        from abob_user.abob_tbl_losses
        where lacctyr_k = c_rec.lacctyr_k  and
            month = c_rec.month and
            currency_desc_k     = a_currency   and
            usd = 'T'
            and inter_side = c_rec.inter_side
        ;

        if p_batch_mode = true then
        -- batch mode, store the current loss row in an associative array, make all
        -- the updates to the array (here and in the contra sub-routine, then make one update for all loss rows

        -- check if the element is in the array yet        
        if not batch_list_losses_rec.exists(losses_row.losses_k) then

            batch_list_losses_rec(losses_row.losses_k) := losses_row
            ;        
            batch_list_losses_key(batch_list_losses_key.count + 1) := losses_row.losses_k
            ;
        end if;
        
        -- update the array
         batch_list_losses_rec(losses_row.losses_k).gross_reserve := c_rec.gross_reserve * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).salvage_reserve := c_rec.salvage_reserve * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).ibnr_sap_balance := c_rec_usd.ibnr_sap_balance;
         batch_list_losses_rec(losses_row.losses_k).losses_sap_balance := l_tot_res_sap;
         batch_list_losses_rec(losses_row.losses_k).losses_sap_paid := c_rec.losses_sap_paid * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).losses_sap_recovered := c_rec.losses_sap_recovered * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).losses_sap_incurred := (l_tot_res_sap - nvl(prev_rec.losses_sap_balance,0)) + ((c_rec.losses_sap_paid - c_rec.losses_sap_recovered) * l_fx_rate);
         batch_list_losses_rec(losses_row.losses_k).lae_sap_balance := c_rec.lae_sap_balance * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_sap_recovered := c_rec.lae_sap_recovered * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_sap_paid := c_rec.lae_sap_paid * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_sap_incurred := (c_rec.lae_sap_balance - c_rec.lae_sap_recovered + c_rec.lae_sap_paid) * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).gross_reserve_gaap := c_rec.gross_reserve_gaap * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).salvage_reserve_gaap := c_rec.salvage_reserve_gaap * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).ibnr_gap_balance := c_rec_usd.ibnr_gap_balance;
         batch_list_losses_rec(losses_row.losses_k).losses_gap_balance := l_tot_res_gap;
         batch_list_losses_rec(losses_row.losses_k).losses_gap_paid := c_rec.losses_gap_paid * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).losses_gap_recovered := c_rec.losses_gap_recovered * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).losses_gap_incurred := (l_tot_res_gap - nvl(prev_rec.losses_gap_balance,0)) + ((c_rec.losses_gap_paid - c_rec.losses_gap_recovered) * l_fx_rate);
         batch_list_losses_rec(losses_row.losses_k).lae_gap_balance := c_rec.lae_gap_balance * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_gap_recovered := c_rec.lae_gap_recovered * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_gap_paid := c_rec.lae_gap_paid * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_gap_incurred := (c_rec.lae_gap_balance - c_rec.lae_gap_recovered + c_rec.lae_gap_paid) * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).losses_sap_paid_adj:= c_rec.losses_sap_paid_adj * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).losses_sap_recovered_adj := c_rec.losses_sap_recovered_adj * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_sap_paid_adj := c_rec.lae_sap_paid_adj * l_fx_rate;
         batch_list_losses_rec(losses_row.losses_k).lae_sap_recovered_adj := c_rec.lae_sap_recovered_adj * l_fx_rate;
        
        else
    
          UPDATE abob_user.abob_tbl_losses
             SET gross_reserve = c_rec.gross_reserve * l_fx_rate,
                   salvage_reserve = c_rec.salvage_reserve    * l_fx_rate,
                ibnr_sap_balance = c_rec_usd.ibnr_sap_balance,
                losses_sap_balance = l_tot_res_sap,
                losses_sap_paid    = c_rec.losses_sap_paid     * l_fx_rate,
                losses_sap_recovered = c_rec.losses_sap_recovered * l_fx_rate,
                losses_sap_incurred = (l_tot_res_sap - nvl(prev_rec.losses_sap_balance,0)) + ((c_rec.losses_sap_paid - c_rec.losses_sap_recovered) * l_fx_rate),
                lae_sap_balance     = c_rec.lae_sap_balance * l_fx_rate,
                lae_sap_recovered = c_rec.lae_sap_recovered * l_fx_rate,
                lae_sap_paid = c_rec.lae_sap_paid * l_fx_rate,
                lae_sap_incurred = (c_rec.lae_sap_balance - c_rec.lae_sap_recovered + c_rec.lae_sap_paid) * l_fx_rate,
                gross_reserve_gaap = c_rec.gross_reserve_gaap * l_fx_rate,
                salvage_reserve_gaap = c_rec.salvage_reserve_gaap * l_fx_rate,
                ibnr_gap_balance = c_rec_usd.ibnr_gap_balance,
                losses_gap_balance = l_tot_res_gap,
                losses_gap_paid    = c_rec.losses_gap_paid    * l_fx_rate,
                losses_gap_recovered = c_rec.losses_gap_recovered * l_fx_rate,
                losses_gap_incurred = (l_tot_res_gap - nvl(prev_rec.losses_gap_balance,0)) + ((c_rec.losses_gap_paid - c_rec.losses_gap_recovered) * l_fx_rate),
                lae_gap_balance    = c_rec.lae_gap_balance    * l_fx_rate,
                lae_gap_recovered = c_rec.lae_gap_recovered * l_fx_rate,
                lae_gap_paid = c_rec.lae_gap_paid * l_fx_rate,
                lae_gap_incurred = (c_rec.lae_gap_balance - c_rec.lae_gap_recovered + c_rec.lae_gap_paid) * l_fx_rate,
                losses_sap_paid_adj= c_rec.losses_sap_paid_adj    * l_fx_rate,
                losses_sap_recovered_adj = c_rec.losses_sap_recovered_adj * l_fx_rate,
                lae_sap_paid_adj = c_rec.lae_sap_paid_adj * l_fx_rate,
                lae_sap_recovered_adj = c_rec.lae_sap_recovered_adj    * l_fx_rate
           WHERE
                lacctyr_k = c_rec.lacctyr_k  and
                month = c_rec.month and
                currency_desc_k     = a_currency   and
                usd = 'T'
                and inter_side = c_rec.inter_side
                ;
        end if; -- batch mode switch
        
        END IF; -- fx

        -- KEEP AGGREGATE LOSSES TABLE IN SYNC
        l_return := abob_user.abob_fun_aggregate_losses(l_gig_k,a_currency,c_rec.acct_yr,c_rec.month);

--abob_user.Spc_Debug('Calling contra sub-routine');    
-- YY 08/21/15  add call to contra loss logic
        IF a_currency <> 10000038 THEN  -- non_usd, call contra on the related USD row
--abob_user.Spc_Debug('FX row - USD row losses_k is '|| losses_row.losses_k);        
            begin
                select
                    l.losses_k
                into
                    v_prev_losses_k
                FROM
                abob_user.abob_tbl_losses     l,
                abob_user.abob_tbl_loss_years ly
                WHERE
                ly.lacctyr_k        = l.lacctyr_k  AND
                ly.rev_gig_k          = a_rev_gig_k AND
                l.currency_desc_k = a_currency  AND
                l.usd                = 'T'  and
                (ly.lacctyr_k = prev_rec.lacctyr_k and l.month = prev_rec.month)
                and L.INTER_SIDE = c_rec.inter_side
                ; 
            exception when no_data_found then
                v_prev_losses_k := null;
            end;      
        
--        abob_user.Spc_Debug('Current Losses_k is '||losses_row.losses_k||' - previous losses_k is '||v_prev_losses_k);
        
            ABOB_USER.abob_pkg_loss_contra.Contra_Loss_Calc(losses_row.losses_k,v_prev_losses_k,v_mtm,v_ReFi,v_terminated
                                                            ,a_rev_gig_k, a_year, a_month,p_batch_mode);        
        
        else  -- USD        
        
        ABOB_USER.abob_pkg_loss_contra.Contra_Loss_Calc(c_rec.losses_k,prev_rec.losses_k,v_mtm,v_ReFi,v_terminated
                                                            ,a_rev_gig_k, a_year, a_month,p_batch_mode);        
        
        end if;  -- Contra call USD switch
        
        END IF; -- lb_process

        prev_rec     := c_rec;
        prev_rec_usd := c_rec_usd;
        l_cnt         := l_cnt + 1;

END LOOP;

close cur_records_usd;

<<bottom>>

null;

EXCEPTION
    WHEN OTHERS THEN
    
        IF cur_records%isopen THEN
            close cur_records;
        END IF;

        IF cur_records_usd%isopen THEN
            close cur_records_usd;
        END IF;

        IF cur_wp%isopen THEN
            close cur_wp;
        END IF;

        raise_application_error(-20001,'Abob_spc_losses_calc - rev_gig_k '||a_rev_gig_k||sqlerrm);

END; -- abob_SPC_Losses_Calc  


procedure Loss_recalc_policy(
        p_policy_num IN abob_user.abob_tbl_corp_gig.policy_num%TYPE,
        p_policy_sub IN abob_user.abob_tbl_corp_gig.policy_sub%TYPE,
        p_batch_mode boolean default false,
        p_acct_year IN abob_tbl_loss_years.acct_yr%type,
        p_acct_month      IN abob_tbl_losses.month%type
        ) is
   
cursor cur_gig is

select distinct lg.gig_k, lg.rev_gig_k, ly.acct_yr, l.month, l.currency_desc_k, accident_year -- ajh added accident year
    ,CG.LINE_OF_BUSINESS
from 
   abob_user.abob_tbl_lossgig lg,
   abob_user.abob_tbl_loss_years ly,
   abob_user.abob_tbl_losses l,
   abob_user.abob_tbl_corp_gig cg
where
    LG.REV_GIG_K = ly.rev_gig_k and
    ly.lacctyr_k = l.lacctyr_k and
    LG.GIG_K = CG.CORP_GIG_K and
    nvl(cg.policy_num,'-1') = nvl(p_policy_num, '-1')  
    AND nvl(rtrim(cg.policy_sub),' ') = nvl(rtrim(p_policy_sub),' ')  
    and ly.acct_yr = p_acct_year
    and l.month = p_acct_month
order by lg.gig_k, accident_year ;

-- 12/09/15 AJH copied from upr_for_losses
CURSOR cur_max_accd_yr(
    a_gig_k abob_user.ABOB_TBL_LOSSGIG.gig_k%TYPE,
    a_acct_yr abob_user.ABOB_TBL_LOSS_YEARS.acct_yr%TYPE,
    a_currency_k abob_user.ABOB_TBL_LOSSES.currency_desc_k%TYPE)
IS
    SELECT MAX(lg.accident_year)  max_accd_yr
FROM
     abob_user.ABOB_TBL_LOSSGIG lg, 
     abob_user.ABOB_TBL_LOSS_YEARS ly,
    abob_user.ABOB_TBL_LOSSES l
WHERE 
    lg.gig_k = a_gig_k
    AND ly.REV_GIG_K = lg.REV_GIG_K
    AND ly.ACCT_YR = a_acct_yr
    AND l.LACCTYR_K = ly.LACCTYR_K  
    AND l.CURRENCY_DESC_K = a_currency_k;       

CURSOR cur_max_accd_yr_withamts(
    a_gig_k abob_user.ABOB_TBL_LOSSGIG.gig_k%TYPE,
    a_acct_yr abob_user.ABOB_TBL_LOSS_YEARS.acct_yr%TYPE,
    a_currency_k abob_user.ABOB_TBL_LOSSES.currency_desc_k%TYPE)
IS
SELECT 
    MAX(lg.accident_year)  max_accd_yr
FROM 
    abob_user.ABOB_TBL_LOSSGIG lg, 
    abob_user.ABOB_TBL_LOSS_YEARS ly,
    abob_user.ABOB_TBL_LOSSES l
WHERE 
    lg.gig_k = a_gig_k
    AND ly.REV_GIG_K = lg.REV_GIG_K
    AND ly.ACCT_YR = a_acct_yr AND l.LACCTYR_K = ly.LACCTYR_K  
    AND l.CURRENCY_DESC_K = a_currency_k       
    AND (nvl(    gross_reserve    ,0) <>  0 or
        nvl(    salvage_reserve    ,0) <>  0 or
        nvl(    ibnr_sap_balance    ,0) <>  0 or
        nvl(    losses_sap_paid    ,0) <>  0 or
        nvl(    losses_sap_recovered    ,0) <>  0 or
        nvl(    gross_reserve_gaap    ,0) <>  0 or
        nvl(    salvage_reserve_gaap    ,0) <>  0 or
        nvl(    ibnr_gap_balance    ,0) <>  0 or
        nvl(    losses_gap_paid    ,0) <>  0 or
        nvl(    losses_gap_recovered    ,0) <>  0 or
        nvl(    lae_sap_balance    ,0) <>  0 or
        nvl(    lae_sap_paid    ,0) <>  0 or
        nvl(    lae_sap_recovered    ,0) <>  0 or
        nvl(    lae_gap_balance    ,0) <>  0 or
        nvl(    lae_gap_paid    ,0) <>  0 or
        nvl(    lae_gap_recovered    ,0) <>  0
        or nvl( loss_mit_purchase,0) <> 0
        or nvl( loss_mit_interest,0) <> 0
        or nvl( tsc_paid,0) <> 0
        or nvl( stat_undiscounted_loss_res,0) <> 0
        or nvl( stat_undiscounted_salv_res,0) <> 0
        or nvl( OR_OTHER_INCOME,0) <> 0
        or nvl( OR_CONTRA_BAL_PAID,0) <> 0
        or nvl( OR_CONTRA_BAL_LOSS_MIT,0) <> 0
        or nvl( OR_CONTRA_PL_PAID,0) <> 0
        or nvl( OR_CONTRA_PL_LOSS_MIT,0) <> 0
        or nvl( OR_CASE,0) <> 0        
        or nvl( OR_SALVAGE_PAID,0) <> 0
        or nvl( OR_SALVAGE_LOSS_MIT,0) <> 0
        or nvl( OR_LAE,0) <> 0
        or nvl( OR_LAE_SALVAGE,0) <> 0
        or nvl( OR_CONTRA_RECLASS_SALV_PAID,0) <> 0
        or nvl( OR_CONTRA_RECLASS_SAL_LOSS_MIT,0) <> 0
        or nvl( OR_OTHER_INCOME_STAT,0) <> 0        
/* itd are not indicative of whether the user are still uploading to a certain accident year, removing from the max accident year logic     
    or
        nvl(    end_itd_paid_gaap    ,0) <>  0 or
        nvl(    end_itd_recovered_gaap    ,0) <>  0 or
        nvl(    end_itd_lae_paid_gaap    ,0) <>  0 or
        nvl(    end_itd_lae_recovered_gaap    ,0) <>  0 or
        nvl(    end_itd_tsc_paid_gaap    ,0) <>  0 or
        nvl(    end_itd_loss_mit    ,0) <>  0 or
        nvl(    end_itd_loss_mit_int    ,0) <>  0 or
        nvl(    other_income    ,0) <>  0
 */
        );

CURSOR cur_max_policy_accident_year(
    a_policy_num_sub varchar,
    a_currency_k abob_user.abob_tbl_losses.currency_desc_k%type)
IS
SELECT 
    MAX(lg.accident_year)  max_accd_yr
FROM 
    abob_user.abob_tbl_corp_gig g,
    abob_user.abob_tbl_lossgig lg, 
    abob_user.abob_tbl_loss_years ly,
    abob_user.abob_tbl_losses l
WHERE 
    g.policy_num||rtrim(policy_sub) = a_policy_num_sub and 
    lg.gig_k = g.corp_gig_k and 
    ly.rev_gig_k = lg.rev_gig_k and 
    ly.acct_yr = p_acct_year and 
    l.month >= p_acct_month and    
    l.lacctyr_k = ly.lacctyr_k and   
    l.currency_desc_k = a_currency_k and        
     (nvl(    gross_reserve    ,0) <>  0 or
        nvl(    salvage_reserve    ,0) <>  0 or
        nvl(    ibnr_sap_balance    ,0) <>  0 or
        nvl(    losses_sap_paid    ,0) <>  0 or
        nvl(    losses_sap_recovered    ,0) <>  0 or
        nvl(    gross_reserve_gaap    ,0) <>  0 or
        nvl(    salvage_reserve_gaap    ,0) <>  0 or
        nvl(    ibnr_gap_balance    ,0) <>  0 or
        nvl(    losses_gap_paid    ,0) <>  0 or
        nvl(    losses_gap_recovered    ,0) <>  0 or
        nvl(    lae_sap_balance    ,0) <>  0 or
        nvl(    lae_sap_paid    ,0) <>  0 or
        nvl(    lae_sap_recovered    ,0) <>  0 or
        nvl(    lae_gap_balance    ,0) <>  0 or
        nvl(    lae_gap_paid    ,0) <>  0 or
        nvl(    lae_gap_recovered    ,0) <>  0
        or nvl( loss_mit_purchase,0) <> 0
        or nvl( loss_mit_interest,0) <> 0
        or nvl( tsc_paid,0) <> 0
        or nvl( stat_undiscounted_loss_res,0) <> 0
        or nvl( stat_undiscounted_salv_res,0) <> 0
        or nvl( OR_OTHER_INCOME,0) <> 0
        or nvl( OR_CONTRA_BAL_PAID,0) <> 0
        or nvl( OR_CONTRA_BAL_LOSS_MIT,0) <> 0
        or nvl( OR_CONTRA_PL_PAID,0) <> 0
        or nvl( OR_CONTRA_PL_LOSS_MIT,0) <> 0
        or nvl( OR_CASE,0) <> 0        
        or nvl( OR_SALVAGE_PAID,0) <> 0
        or nvl( OR_SALVAGE_LOSS_MIT,0) <> 0
        or nvl( OR_LAE,0) <> 0
        or nvl( OR_LAE_SALVAGE,0) <> 0
        or nvl( OR_CONTRA_RECLASS_SALV_PAID,0) <> 0
        or nvl( OR_CONTRA_RECLASS_SAL_LOSS_MIT,0) <> 0
        or nvl( OR_OTHER_INCOME_STAT,0) <> 0                
/* itd are not indicative of whether the user are still uploading to a certain accident year, removing from the max accident year logic        
         or
        nvl(    end_itd_paid_gaap    ,0) <>  0 or
        nvl(    end_itd_recovered_gaap    ,0) <>  0 or
        nvl(    end_itd_lae_paid_gaap    ,0) <>  0 or
        nvl(    end_itd_lae_recovered_gaap    ,0) <>  0 or
        nvl(    end_itd_tsc_paid_gaap    ,0) <>  0 or
        nvl(    end_itd_loss_mit    ,0) <>  0 or
        nvl(    end_itd_loss_mit_int    ,0) <>  0 or
        nvl(    other_income    ,0) <>  0
*/        
         );


l_max_accd_yr_withamts number;
l_max_accd_yr number;
nPolicyAccidentYear number;

begin

if p_batch_mode = false then
    lst_gig_term_date.delete;
    init_gig_termination(lst_gig_term_date,p_policy_num,p_policy_sub);
end if;

nPolicyAccidentYear := null;
--spc_debug('acct_year = '||g_acct_year || 'and acct_month =  '||g_acct_month);

open cur_max_policy_accident_year(rtrim(p_policy_num||p_policy_sub), 10000038);
fetch cur_max_policy_accident_year into nPolicyAccidentYear;
--spc_debug('nPolicyAccidentYear = '||nPolicyAccidentYear || 'for policy '||rtrim(p_policy_num||p_policy_sub));
close cur_max_policy_accident_year;

for rec in cur_gig loop
--    spc_debug('nPolicyAccidentYear = '||nPolicyAccidentYear || 'for gig '||rec.gig_k);
    IF nPolicyAccidentYear is null or nPolicyAccidentYear = 0 THEN
        OPEN cur_max_accd_yr_withamts(rec.gig_k,rec.acct_yr,rec.currency_desc_k);
        FETCH cur_max_accd_yr_withamts INTO l_max_accd_yr_withamts;
        CLOSE cur_max_accd_yr_withamts;

        --spc_debug('max_accd_yr = '||l_max_accd_yr_withamts || 'for gig '||rec.gig_k);
    
        IF NVL(l_max_accd_yr_withamts,0) = 0 THEN
            OPEN cur_max_accd_yr(rec.gig_k,rec.acct_yr,rec.currency_desc_k);
            FETCH cur_max_accd_yr INTO l_max_accd_yr;
            CLOSE cur_max_accd_yr;
        ELSE
            l_max_accd_yr := l_max_accd_yr_withamts;
        END IF;
    ELSE 
        l_max_accd_yr := nPolicyAccidentYear;
    END IF;

    spc_debug('contra for  gig '||rec.gig_k||' max year '||l_max_accd_yr||' rec accident yr '||rec.accident_year);

    IF l_max_accd_yr = rec.accident_year THEN -- ajh 12/09/15 don't want to call for the old accident years
        abob_user.abob_pkg_loss_contra.abob_spc_losses_calc (rec.rev_gig_k, rec.acct_yr, rec.month, rec.currency_desc_k, p_batch_mode);
    elsif rec.LINE_OF_BUSINESS = 4 or rec.LINE_OF_BUSINESS = 3 then
    -- but if the line of business is 3 or 4, by-pass the accident year limit, and contra calc all the rows
        abob_user.abob_pkg_loss_contra.abob_spc_losses_calc (rec.rev_gig_k, rec.acct_yr, rec.month, rec.currency_desc_k, p_batch_mode);
    END IF;        
end loop;


EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20106, 'losses_recalc_policy '||p_policy_num||p_policy_sub|| SQLERRM);

end; -- losses_recalc_policy

procedure Loss_recalc_all(p_acct_year number default null, p_acct_month number default null) is

CURSOR cur_fg_policy(c_g_acct_year number, c_g_acct_month number) IS
SELECT distinct 
    g.policy_num, 
    g.policy_sub
FROM 
    abob_user.ABOB_TBL_CORP_GIG g,
    abob_user.ABOB_TBL_LOSSGIG lg, 
    abob_user.ABOB_TBL_LOSS_YEARS ly, 
    abob_user.ABOB_TBL_LOSSES l
WHERE 
    l.lacctyr_k = ly.lacctyr_k
    AND ly.rev_gig_k = lg.rev_gig_k
    AND g.corp_gig_k = lg.gig_k
--    AND g.line_of_business = 1
--    and G.MTM_FLG <> 'Y'    
--    AND l.currency_desc_k = 10000038
/* YY not limiting to FG, MTM = N, nor USD; run for everything, the 
    sub procedures will branch out for the various cases */
 AND ly.acct_yr = c_g_acct_year  
 and L.MONTH = c_g_acct_month
 ORDER BY g.policy_num, g.policy_sub;

p_count number;

forall_error exception;
forall_error_2 exception;
pragma exception_init(forall_error, -01722);
pragma exception_init(forall_error_2, -24381);
error_count number;
  
begin

abob_user.Spc_Debug('LOSS_RECALC_ALL - START');

if p_acct_year is null or p_acct_month is null then
    g_acct_year := abob_user.abob_pkg_Archive.get_closed_year('LOSS') + 1;
    g_acct_month := to_number(substr(to_char(abob_user.abob_pkg_archive.get_current_period('LOSS')),5,2));
else
    g_acct_year := p_acct_year;
    g_acct_month := p_acct_month;
end if;

-- reset the batch collections
if batch_list_losses_rec.count > 1 then
    batch_list_losses_rec.delete;
end if;

if batch_list_losses_key.count > 1 then
    batch_list_losses_key.delete;
end if;

p_count := 0;

-- init the temp table to hold the termination information
   init_gig_termination(lst_gig_term_date);

-- it is assumed that all the necessary structures have been created already (either from UPR update or loss upload)
for v_cur in cur_fg_policy(g_acct_year,g_acct_month) loop
    loss_recalc_policy(v_cur.policy_num, v_cur.policy_sub, true,g_acct_year,g_acct_month);
    p_count := p_count + 1;
    if mod(p_count,200) = 0 then
        abob_user.Spc_Debug('LOSS_RECALC_ALL - Processed '||p_count||' policies');
    end if;
    
end loop;

abob_user.Spc_Debug('LOSS_RECALC_ALL - Done recalc for '||p_count||' policies and '||batch_list_losses_key.count||' loss rows');

abob_user.Spc_Debug('LOSS_RECALC_ALL - Start populated temp table');

    begin
        
--        execute immediate 'truncate table abob_user.abob_tbl_losses_batch_update;';
        
        forall indx in indices of batch_list_losses_rec
        save exceptions
            insert into ABOB_USER.ABOB_TBL_LOSSES_BATCH_UPDATE
            values batch_list_losses_rec(indx);
    EXCEPTION
     when forall_error then
        error_count := sql%bulk_exceptions.count;
        abob_user.Spc_Debug('LOSS_RECALC_ALL - forall insert error count is: ' || error_count);
        for i in 1 .. error_count loop
            abob_user.Spc_Debug('LOSS_RECALC_ALL - error index number: ' || sql%bulk_exceptions(i).error_index);
            abob_user.Spc_Debug('LOSS_RECALC_ALL - error index message: ' || sql%bulk_exceptions(i).error_code);
        end loop;
     when forall_error_2 then
        error_count := sql%bulk_exceptions.count;
        abob_user.Spc_Debug('LOSS_RECALC_ALL - forall insert error count is: ' || error_count);
        for i in 1 .. error_count loop
            abob_user.Spc_Debug('LOSS_RECALC_ALL - error index number: ' || sql%bulk_exceptions(i).error_index);
            abob_user.Spc_Debug('LOSS_RECALC_ALL - error index message: ' || sql%bulk_exceptions(i).error_code);
        end loop;    
     WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20106, 'LOSS_RECALC_ALL '|| SQLERRM);
    end;    


select count(*) into p_count from ABOB_USER.ABOB_TBL_LOSSES_BATCH_UPDATE;
    
abob_user.Spc_Debug('LOSS_RECALC_ALL - Done populated temp table with '||p_count||' rows, start merging');
    
merge_batch_update;

commit;

-- reset the batch collections
if batch_list_losses_rec.count > 1 then
    batch_list_losses_rec.delete;
end if;

if batch_list_losses_key.count > 1 then
    batch_list_losses_key.delete;
end if;

abob_user.Spc_Debug('LOSS_RECALC_ALL - Done merging; Contra recalc done');

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20106, 'LOSS_RECALC_ALL '|| SQLERRM); 
  
end; --loss_recalc_all

procedure Loss_recalc_for_upload(p_load_batch_k abob_tbl_load_batch.load_batch_k%type) is

CURSOR cur_fg_policy(c_g_acct_year number, c_g_acct_month number) IS
SELECT distinct 
    g.policy_num, 
    g.policy_sub
FROM 
    abob_user.ABOB_TBL_CORP_GIG g,
    abob_user.ABOB_TBL_LOSSGIG lg, 
    abob_user.ABOB_TBL_LOSS_YEARS ly, 
    abob_user.ABOB_TBL_LOSSES l
    ,abob_user.abob_tbl_load_losses_detail ld
WHERE 
    l.lacctyr_k = ly.lacctyr_k
    AND ly.rev_gig_k = lg.rev_gig_k
    AND g.corp_gig_k = lg.gig_k
 AND ly.acct_yr = c_g_acct_year  
 and L.MONTH = c_g_acct_month
 and l.losses_k = ld. losses_k
 and ld. load_batch_k = p_load_batch_k
 ORDER BY g.policy_num, g.policy_sub;

p_count number;
  
begin

abob_user.Spc_Debug('Loss_recalc_for_upload - START');

g_acct_year := abob_user.abob_pkg_Archive.get_closed_year('LOSS') + 1;
g_acct_month := to_number(substr(to_char(abob_user.abob_pkg_archive.get_current_period('LOSS')),5,2));

-- reset the batch collections
if batch_list_losses_rec.count > 1 then
    batch_list_losses_rec.delete;
end if;

if batch_list_losses_key.count > 1 then
    batch_list_losses_key.delete;
end if;

p_count := 0;

-- init the temp collection to hold the termination information
    init_gig_termination(lst_gig_term_date);

-- it is assumed that all the necessary structures have been created already (either from UPR update or loss upload)
for v_cur in cur_fg_policy(g_acct_year,g_acct_month) loop
    loss_recalc_policy(v_cur.policy_num, v_cur.policy_sub, true,g_acct_year,g_acct_month);
    p_count := p_count + 1;
    if mod(p_count,200) = 0 then
        abob_user.Spc_Debug('Loss_recalc_for_upload - Processed '||p_count||' policies');
    end if;
    
end loop;

abob_user.Spc_Debug('Loss_recalc_for_upload - Done recalc for '||p_count||' policies and '||batch_list_losses_key.count||' loss rows');

abob_user.Spc_Debug('Loss_recalc_for_upload - Start populated temp table');

forall indx in indices of batch_list_losses_rec
    insert into ABOB_USER.ABOB_TBL_LOSSES_BATCH_UPDATE
    values batch_list_losses_rec(indx);

select count(*) into p_count from ABOB_USER.ABOB_TBL_LOSSES_BATCH_UPDATE;
    
abob_user.Spc_Debug('Loss_recalc_for_upload - Done populated temp table with '||p_count||' rows, start merging');
    
merge_batch_update;

commit;

-- reset the batch collections
if batch_list_losses_rec.count > 1 then
    batch_list_losses_rec.delete;
end if;

if batch_list_losses_key.count > 1 then
    batch_list_losses_key.delete;
end if;

abob_user.Spc_Debug('Loss_recalc_for_upload - Done merging; Contra recalc done');

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20106, 'Loss_recalc_for_upload '|| SQLERRM);
  
end; --Loss_recalc_for_upload


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

procedure terminated_cession(p_losses_k abob_user.abob_tbl_losses.losses_k%type
                            , p_prev_losses_k abob_user.abob_tbl_losses.losses_k%type
                            , p_rev_gig_k abob_user.abob_tbl_lossgig.rev_gig_k%type
                            , p_acct_year IN abob_tbl_loss_years.acct_yr%type
                            , p_acct_month      IN abob_tbl_losses.month%type
                            , p_batch_mode boolean default false) is
                            
cursor cur_losses_row(v_losses_k abob_user.abob_tbl_losses.losses_k%type) is
select * from ABOB_USER.abob_tbl_losses
where losses_k = v_losses_k
for update;

c_rec cur_losses_row%rowtype;
prev_rec cur_losses_row%rowtype;    

cursor future_rows 
(a_rev_gig_k abob_user.abob_tbl_lossgig.rev_gig_k%type
,a_currency abob_tbl_losses.CURRENCY_DESC_K%type
,l_year abob_tbl_loss_years.acct_yr%type
,l_month abob_tbl_losses.month%type
,a_deal_currency abob_tbl_losses.deal_currency%type
,a_usd abob_tbl_losses.usd%type
,a_inter_side abob_tbl_losses.inter_side%type
)
is
select
    l.*
    FROM
        abob_user.abob_tbl_losses l,
        abob_user.abob_tbl_loss_years ly
    WHERE
        ly.lacctyr_k = l.lacctyr_k AND
        ly.rev_gig_k = a_rev_gig_k  AND
        l.currency_desc_k = a_currency  AND
        l.deal_currency    = a_deal_currency and
        l.usd = a_usd and
        l.inter_side = a_inter_side and
        (ly.acct_yr    > l_year OR  (ly.acct_yr    = l_year and l.month > l_month))
    ORDER BY
        LY.REV_GIG_K,
        l.inter_side asc,
        ly.acct_yr,
        l.month;        

begin

if p_batch_mode  then

    if not batch_list_losses_rec.exists(p_losses_k) then
        open cur_losses_row(p_losses_k);
        fetch cur_losses_row into c_rec;
        close cur_losses_row;  
        
        batch_list_losses_rec(p_losses_k) := c_rec;        
        batch_list_losses_key(batch_list_losses_key.count + 1) := p_losses_k;
          
    else
        c_rec := batch_list_losses_rec(p_losses_k);
    end if;
    
    if not batch_list_losses_rec.exists(p_prev_losses_k) then
        open cur_losses_row(p_prev_losses_k);
        fetch cur_losses_row into prev_rec;
        close cur_losses_row;                   
    else
        prev_rec := batch_list_losses_rec(p_prev_losses_k);
    end if;        

else

    open cur_losses_row(p_prev_losses_k);
    fetch cur_losses_row into prev_rec;
    close cur_losses_row;
    
    open cur_losses_row(p_losses_k);
    fetch cur_losses_row into c_rec;    
        
end if;

if c_rec.calc_method <> 'T' then
-- the calc method is not T, so it is a termination "NEW to ABOB"

-- update the beginning columns, 26 columns - still set to previous value plust transition adjustment    
-- set the STAT beginning
        c_rec.beg_case_stat := nvl(prev_rec.gross_reserve,0) + nvl(c_rec.gross_reserve_ta,0);
        c_rec.beg_salvage_stat := nvl(prev_rec.salvage_reserve,0) + nvl(c_rec.salvage_reserve_ta,0);
        c_rec.beg_ibnr_stat := nvl(prev_rec.ibnr_sap_balance,0) + nvl(c_rec.ibnr_sap_balance_ta,0);
        c_rec.beg_lae_case_stat := nvl(prev_rec.lae_sap_balance,0) + nvl(c_rec.lae_sap_balance_ta,0);
        c_rec.beg_lae_salvage_stat := nvl(prev_rec.lae_salvage_sap_balance,0) + nvl(c_rec.lae_salvage_sap_balance_ta,0);
        c_rec.beg_stat_undiscounted_loss_res := nvl(prev_rec.stat_undiscounted_loss_res,0);
        c_rec.beg_stat_undiscounted_salv_res := nvl(prev_rec.stat_undiscounted_salv_res,0);
-- set GAAP reserve beginning        
        c_rec.beg_case_gaap := nvl(prev_rec.case_res_gaap,0) + nvl(c_rec.case_res_gaap_ta,0);
        c_rec.beg_salvage_gaap := nvl(prev_rec.salvage_res_gaap,0) + nvl(c_rec.salvage_res_gaap_ta,0);
        c_rec.beg_lae_case_gaap := nvl(prev_rec.lae_res_gaap,0) + nvl(c_rec.lae_res_gaap_ta,0);
        c_rec.beg_lae_salvage_gaap := nvl(prev_rec.lae_salvage_res_gaap,0) + nvl(c_rec.lae_salvage_res_gaap_ta,0);
        c_rec.beg_ibnr_gaap := nvl(prev_rec.ibnr_gap_balance,0) + nvl(c_rec.ibnr_gaap_ta,0);
-- set contra beginning
        c_rec.beg_contra_paid := nvl(prev_rec.contra_bal_paid,0) + nvl(c_rec.contra_paid_ta,0);
--        c_rec.beg_contra_wrapped := nvl(prev_rec.contra_bal_wrapped,0) + nvl(c_rec.contra_wrapped_ta,0);
        c_rec.beg_contra_loss_mit := nvl(prev_rec.contra_bal_loss_mit,0) + nvl(c_rec.contra_loss_mit_ta,0);
        c_rec.beg_salv_gaap_paid := nvl(prev_rec.salvage_res_gaap_paid,0) + nvl(c_rec.salv_gaap_paid_ta,0);
--        c_rec.beg_salv_gaap_wrapped := nvl(prev_rec.salvage_res_gaap_wrapped,0) + nvl(c_rec.salv_gaap_wrapped_ta,0);
        c_rec.beg_salv_gaap_loss_mit := nvl(prev_rec.salvage_res_gaap_loss_mit,0) + nvl(c_rec.salv_gaap_loss_mit_ta,0);
        c_rec.beg_other_income := nvl(prev_rec.other_income,0) + nvl(c_rec.other_income_ta,0);
        c_rec.beg_other_income_stat := nvl(prev_rec.other_income_stat,0) + nvl(c_rec.other_income_stat_ta,0);
        c_rec.beg_salv_res_incurred_benefit := nvl(prev_rec.salv_res_incurred_benefit,0) + nvl(c_rec.SALV_RES_INCURRED_BENEFIT_TA,0);
-- set ITD payments beginning
        c_rec.beg_itd_paid_gaap := nvl(prev_rec.end_itd_paid_gaap,0) + nvl(c_rec.itd_paid_gaap_ta,0);
        c_rec.beg_itd_recovered_gaap := nvl(prev_rec.end_itd_recovered_gaap,0) + nvl(c_rec.itd_recovered_gaap_ta,0);
        c_rec.beg_itd_lae_paid_gaap := nvl(prev_rec.end_itd_lae_paid_gaap,0) + nvl(c_rec.itd_lae_paid_gaap_ta,0);
        c_rec.beg_itd_lae_recovered_gaap := nvl(prev_rec.end_itd_lae_recovered_gaap,0) + nvl(c_rec.itd_lae_recovered_gaap_ta,0);
        c_rec.beg_itd_tsc_paid_gaap := nvl(prev_rec.end_itd_tsc_paid_gaap,0) + nvl(c_rec.itd_tsc_paid_gaap_ta,0);
--        c_rec.beg_itd_wrapped := nvl(prev_rec.end_itd_wrapped,0) + nvl(c_rec.itd_wrapped_ta,0);
        c_rec.beg_itd_loss_mit := nvl(prev_rec.end_itd_loss_mit,0) + nvl(c_rec.itd_loss_mit_ta,0);
--        c_rec.beg_itd_wrapped_int := nvl(prev_rec.end_itd_wrapped_int,0) + nvl(c_rec.itd_wrapped_int_ta,0);
        c_rec.beg_itd_loss_mit_int := nvl(prev_rec.end_itd_loss_mit_int,0) + nvl(c_rec.itd_loss_mit_int_ta,0);
        c_rec.beg_gaap_upr := nvl(prev_rec.f_gaap_upr,0) + nvl(c_rec.f_gaap_upr_ta,0);
-- GAAP expected beginning        
        c_rec.BEG_EXP_CASE_GAAP := nvl(prev_rec.gross_reserve_gaap,0) + nvl(c_rec.case_reserve_gaap_ta,0);
        c_rec.BEG_EXP_SALVAGE_GAAP := nvl(prev_rec.salvage_reserve_gaap,0) + nvl(c_rec.salvage_reserve_gaap_ta,0); 
        c_rec.BEG_EXP_LAE_CASE_GAAP := nvl(prev_rec.lae_gap_balance,0) + nvl(c_rec.lae_gap_balance_ta,0);  
        c_rec.BEG_EXP_LAE_SALVAGE_GAAP := nvl(prev_rec.lae_salvage_gap_balance,0)  + nvl(c_rec.lae_salvage_gap_balance_ta,0);        

-- update the ending columns for GAAP and Contra, 29 columns

-- set GAAP reserve ending        
        c_rec.case_res_gaap :=  0;
        c_rec.salvage_res_gaap := 0;
        c_rec.lae_res_gaap := 0;
        c_rec.lae_salvage_res_gaap := 0;
        c_rec.ibnr_res_gaap := 0;
-- set contra ending
-- move remaining contra to PL
        c_rec.contra_pl_paid := nvl(c_rec.beg_contra_paid,0);
        c_rec.contra_pl_loss_mit := nvl(c_rec.beg_contra_loss_mit,0);
        c_rec.contra_bal_paid := 0;
        c_rec.contra_bal_loss_mit := 0;
        c_rec.salvage_res_gaap_paid := 0;
        c_rec.salvage_res_gaap_loss_mit := 0;
-- keepking other income?
        c_rec.other_income := nvl(c_rec.or_other_income, 0) + c_rec.beg_other_income;
        c_rec.other_income_stat := nvl(c_rec.or_other_income_stat, 0) + c_rec.beg_other_income_stat;
-- set ITD payments ending
        c_rec.end_itd_paid_gaap := c_rec.beg_itd_paid_gaap + nvl(c_rec.losses_gap_paid,0);
        c_rec.end_itd_recovered_gaap := c_rec.beg_itd_recovered_gaap + nvl(c_rec.losses_gap_recovered,0);
        c_rec.end_itd_lae_paid_gaap := c_rec.beg_itd_lae_paid_gaap + nvl(c_rec.lae_gap_paid,0);
        c_rec.end_itd_lae_recovered_gaap := c_rec.beg_itd_lae_recovered_gaap + nvl(c_rec.lae_gap_recovered,0);
        c_rec.end_itd_tsc_paid_gaap := c_rec.beg_itd_tsc_paid_gaap + nvl(c_rec.tsc_paid,0);
        c_rec.end_itd_loss_mit := c_rec.beg_itd_loss_mit + nvl(c_rec.loss_mit_purchase,0);
        c_rec.end_itd_loss_mit_int := c_rec.beg_itd_loss_mit_int + nvl(c_rec.loss_mit_interest,0);
-- no contra reclass
        c_rec.contra_reclass_salv_paid := 0;  
        c_rec.contra_reclass_salv_loss_mit := 0;
        c_rec.calc_method := 'T';  
        c_rec.prev_qtr_contra_paid := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_paid
                else prev_rec.prev_qtr_contra_paid
            end;
        c_rec.prev_qtr_contra_loss_mit := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_loss_mit
                else prev_rec.prev_qtr_contra_loss_mit
            end;
        c_rec.gaap_pl_paid := nvl(c_rec.contra_pl_paid,0);
        c_rec.gaap_pl_loss_mit := nvl(c_rec.contra_pl_loss_mit,0);            
   
        c_rec.stat_undiscounted_loss_res := 0;
        c_rec.stat_undiscounted_salv_res := 0;
        c_rec.salv_res_incurred_benefit := 0;             

-- setting STAT ending
-- first send the remaining reserve to corresponding cash cloumns as reversal   
        c_rec.LOSSES_SAP_PAID := nvl(c_rec.losses_sap_paid,0) - c_rec.beg_case_stat;
        c_rec.LOSSES_SAP_RECOVERED := nvl(c_rec.losses_sap_recovered,0) - c_rec.beg_salvage_stat;
        c_rec.LAE_SAP_PAID := nvl(c_rec.lae_sap_paid,0) - c_rec.beg_lae_case_stat;
        c_rec.LAE_SAP_RECOVERED := nvl(c_rec.lae_sap_recovered,0) - c_rec.beg_lae_salvage_stat;
-- then set the reserve to 0                   
        c_rec.GROSS_RESERVE := 0;
        c_rec.SALVAGE_RESERVE := 0;
        c_rec.IBNR_SAP_BALANCE := 0;
        c_rec.lae_sap_balance  := 0;
        c_rec.lae_salvage_sap_balance := 0;     
-- update the calculated columns
        c_rec.losses_sap_balance := c_rec.gross_reserve - c_rec.salvage_reserve + c_rec.ibnr_sap_balance;
        c_rec.losses_sap_incurred := (c_rec.losses_sap_balance - nvl(prev_rec.losses_sap_balance,0))
                                   + (c_rec.losses_sap_paid + nvl(c_rec.losses_sap_paid_adj,0))
                                   - (c_rec.losses_sap_recovered + nvl(c_rec.losses_sap_recovered_adj,0));
        c_rec.lae_sap_incurred := (c_rec.lae_sap_balance   - nvl(prev_rec.lae_sap_balance,0))
                                - (c_rec.lae_salvage_sap_balance  - nvl(prev_rec.lae_salvage_sap_balance,0))
                                + (c_rec.lae_sap_paid       + nvl(c_rec.lae_sap_paid_adj        ,0))
                                - (c_rec.lae_sap_recovered + nvl(c_rec.lae_sap_recovered_adj,0));                                           

-- none Contra GAAP - i.e. GAAP Expected numbers
        c_rec.gross_reserve_gaap := 0;
        c_rec.salvage_reserve_gaap := 0;
        c_rec.ibnr_gap_balance := 0;
        c_rec.lae_gap_balance := 0;
        c_rec.lae_salvage_gap_balance := 0;
        c_rec.losses_gap_balance := c_rec.gross_reserve_gaap - c_rec.salvage_reserve_gaap + c_rec.ibnr_gap_balance;
        c_rec.losses_gap_incurred := 0;
        c_rec.lae_gap_incurred := 0;
        c_rec.stat_recovered_pl := nvl(c_rec.losses_sap_recovered,0) - c_rec.beg_salvage_stat;

else
-- the calc method is already T, so it has already been terminated, just keep everything 0
--abob_user.Spc_Debug('Terminated cession - existing termination');
-- update the beginning columns, 26 columns - still set to previous value plust transition adjustment    
-- set the STAT beginning
        c_rec.beg_case_stat := nvl(prev_rec.gross_reserve,0) + nvl(c_rec.gross_reserve_ta,0);
        c_rec.beg_salvage_stat := nvl(prev_rec.salvage_reserve,0) + nvl(c_rec.salvage_reserve_ta,0);
        c_rec.beg_ibnr_stat := nvl(prev_rec.ibnr_sap_balance,0) + nvl(c_rec.ibnr_sap_balance_ta,0);
        c_rec.beg_lae_case_stat := nvl(prev_rec.lae_sap_balance,0) + nvl(c_rec.lae_sap_balance_ta,0);
        c_rec.beg_lae_salvage_stat := nvl(prev_rec.lae_salvage_sap_balance,0) + nvl(c_rec.lae_salvage_sap_balance_ta,0);
        c_rec.beg_stat_undiscounted_loss_res := nvl(prev_rec.stat_undiscounted_loss_res,0);
        c_rec.beg_stat_undiscounted_salv_res := nvl(prev_rec.stat_undiscounted_salv_res,0);
-- set GAAP reserve beginning        
        c_rec.beg_case_gaap := nvl(prev_rec.case_res_gaap,0) + nvl(c_rec.case_res_gaap_ta,0);
        c_rec.beg_salvage_gaap := nvl(prev_rec.salvage_res_gaap,0) + nvl(c_rec.salvage_res_gaap_ta,0);
        c_rec.beg_lae_case_gaap := nvl(prev_rec.lae_res_gaap,0) + nvl(c_rec.lae_res_gaap_ta,0);
        c_rec.beg_lae_salvage_gaap := nvl(prev_rec.lae_salvage_res_gaap,0) + nvl(c_rec.lae_salvage_res_gaap_ta,0);
        c_rec.beg_ibnr_gaap := nvl(prev_rec.ibnr_gap_balance,0) + nvl(c_rec.ibnr_gaap_ta,0);
-- set contra beginning
        c_rec.beg_contra_paid := nvl(prev_rec.contra_bal_paid,0) + nvl(c_rec.contra_paid_ta,0);
--        c_rec.beg_contra_wrapped := nvl(prev_rec.contra_bal_wrapped,0) + nvl(c_rec.contra_wrapped_ta,0);
        c_rec.beg_contra_loss_mit := nvl(prev_rec.contra_bal_loss_mit,0) + nvl(c_rec.contra_loss_mit_ta,0);
        c_rec.beg_salv_gaap_paid := nvl(prev_rec.salvage_res_gaap_paid,0) + nvl(c_rec.salv_gaap_paid_ta,0);
--        c_rec.beg_salv_gaap_wrapped := nvl(prev_rec.salvage_res_gaap_wrapped,0) + nvl(c_rec.salv_gaap_wrapped_ta,0);
        c_rec.beg_salv_gaap_loss_mit := nvl(prev_rec.salvage_res_gaap_loss_mit,0) + nvl(c_rec.salv_gaap_loss_mit_ta,0);
        c_rec.beg_other_income := nvl(prev_rec.other_income,0) + nvl(c_rec.other_income_ta,0);
        c_rec.beg_other_income_stat := nvl(prev_rec.other_income_stat,0) + nvl(c_rec.other_income_stat_ta,0);
        c_rec.beg_salv_res_incurred_benefit := nvl(prev_rec.salv_res_incurred_benefit,0) + nvl(c_rec.SALV_RES_INCURRED_BENEFIT_TA,0);
-- set ITD payments beginning
        c_rec.beg_itd_paid_gaap := nvl(prev_rec.end_itd_paid_gaap,0) + nvl(c_rec.itd_paid_gaap_ta,0);
        c_rec.beg_itd_recovered_gaap := nvl(prev_rec.end_itd_recovered_gaap,0) + nvl(c_rec.itd_recovered_gaap_ta,0);
        c_rec.beg_itd_lae_paid_gaap := nvl(prev_rec.end_itd_lae_paid_gaap,0) + nvl(c_rec.itd_lae_paid_gaap_ta,0);
        c_rec.beg_itd_lae_recovered_gaap := nvl(prev_rec.end_itd_lae_recovered_gaap,0) + nvl(c_rec.itd_lae_recovered_gaap_ta,0);
        c_rec.beg_itd_tsc_paid_gaap := nvl(prev_rec.end_itd_tsc_paid_gaap,0) + nvl(c_rec.itd_tsc_paid_gaap_ta,0);
--        c_rec.beg_itd_wrapped := nvl(prev_rec.end_itd_wrapped,0) + nvl(c_rec.itd_wrapped_ta,0);
        c_rec.beg_itd_loss_mit := nvl(prev_rec.end_itd_loss_mit,0) + nvl(c_rec.itd_loss_mit_ta,0);
--        c_rec.beg_itd_wrapped_int := nvl(prev_rec.end_itd_wrapped_int,0) + nvl(c_rec.itd_wrapped_int_ta,0);
        c_rec.beg_itd_loss_mit_int := nvl(prev_rec.end_itd_loss_mit_int,0) + nvl(c_rec.itd_loss_mit_int_ta,0);
        c_rec.beg_gaap_upr := nvl(prev_rec.f_gaap_upr,0) + nvl(c_rec.f_gaap_upr_ta,0);
-- GAAP expected beginning        
        c_rec.BEG_EXP_CASE_GAAP := nvl(prev_rec.gross_reserve_gaap,0) + nvl(c_rec.case_reserve_gaap_ta,0);
        c_rec.BEG_EXP_SALVAGE_GAAP := nvl(prev_rec.salvage_reserve_gaap,0) + nvl(c_rec.salvage_reserve_gaap_ta,0); 
        c_rec.BEG_EXP_LAE_CASE_GAAP := nvl(prev_rec.lae_gap_balance,0) + nvl(c_rec.lae_gap_balance_ta,0);  
        c_rec.BEG_EXP_LAE_SALVAGE_GAAP := nvl(prev_rec.lae_salvage_gap_balance,0)  + nvl(c_rec.lae_salvage_gap_balance_ta,0);        

-- update the ending columns for GAAP and Contra, 29 columns

-- set GAAP reserve ending        
        c_rec.case_res_gaap :=  0;
        c_rec.salvage_res_gaap := 0;
        c_rec.lae_res_gaap := 0;
        c_rec.lae_salvage_res_gaap := 0;
        c_rec.ibnr_res_gaap := 0;
-- set contra ending
-- move remaining contra to PL
        c_rec.contra_pl_paid := 0;
        c_rec.contra_pl_loss_mit := 0;
        c_rec.contra_bal_paid := 0;
        c_rec.contra_bal_loss_mit := 0;
        c_rec.salvage_res_gaap_paid := 0;
        c_rec.salvage_res_gaap_loss_mit := 0;
-- keepking other income?
        c_rec.other_income := nvl(c_rec.or_other_income, 0) + c_rec.beg_other_income;
        c_rec.other_income_stat := nvl(c_rec.or_other_income_stat, 0) + c_rec.beg_other_income_stat;
-- set ITD payments ending
        c_rec.end_itd_paid_gaap := c_rec.beg_itd_paid_gaap + nvl(c_rec.losses_gap_paid,0);
        c_rec.end_itd_recovered_gaap := c_rec.beg_itd_recovered_gaap + nvl(c_rec.losses_gap_recovered,0);
        c_rec.end_itd_lae_paid_gaap := c_rec.beg_itd_lae_paid_gaap + nvl(c_rec.lae_gap_paid,0);
        c_rec.end_itd_lae_recovered_gaap := c_rec.beg_itd_lae_recovered_gaap + nvl(c_rec.lae_gap_recovered,0);
        c_rec.end_itd_tsc_paid_gaap := c_rec.beg_itd_tsc_paid_gaap + nvl(c_rec.tsc_paid,0);
        c_rec.end_itd_loss_mit := c_rec.beg_itd_loss_mit + nvl(c_rec.loss_mit_purchase,0);
        c_rec.end_itd_loss_mit_int := c_rec.beg_itd_loss_mit_int + nvl(c_rec.loss_mit_interest,0);
-- no contra reclass
        c_rec.contra_reclass_salv_paid := 0;  
        c_rec.contra_reclass_salv_loss_mit := 0;
        c_rec.calc_method := 'T';  
        c_rec.prev_qtr_contra_paid := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_paid
                else prev_rec.prev_qtr_contra_paid
            end;
        c_rec.prev_qtr_contra_loss_mit := 
            case
                when mod(c_rec.month,3) = 1 then prev_rec.contra_bal_loss_mit
                else prev_rec.prev_qtr_contra_loss_mit
            end;
        c_rec.gaap_pl_paid := 0;
        c_rec.gaap_pl_loss_mit := 0;            
   
        c_rec.stat_undiscounted_loss_res := 0;
        c_rec.stat_undiscounted_salv_res := 0;
        c_rec.salv_res_incurred_benefit := 0;             

-- setting STAT ending
-- first send the remaining reserve to corresponding cash cloumns as reversal   
        c_rec.LOSSES_SAP_PAID := 0;
        c_rec.LOSSES_SAP_RECOVERED := 0;
        c_rec.LAE_SAP_PAID := 0;
        c_rec.LAE_SAP_RECOVERED := 0;
-- then set the reserve to 0                   
        c_rec.GROSS_RESERVE := 0;
        c_rec.SALVAGE_RESERVE := 0;
        c_rec.IBNR_SAP_BALANCE := 0;
        c_rec.lae_sap_balance  := 0;
        c_rec.lae_salvage_sap_balance := 0;     
-- update the calculated columns
        c_rec.losses_sap_balance := c_rec.gross_reserve - c_rec.salvage_reserve + c_rec.ibnr_sap_balance;
        c_rec.losses_sap_incurred := 0;
        c_rec.lae_sap_incurred := 0;                                           

-- none Contra GAAP - i.e. GAAP Expected numbers
        c_rec.gross_reserve_gaap := 0;
        c_rec.salvage_reserve_gaap := 0;
        c_rec.ibnr_gap_balance := 0;
        c_rec.lae_gap_balance := 0;
        c_rec.lae_salvage_gap_balance := 0;
        c_rec.losses_gap_balance := c_rec.gross_reserve_gaap - c_rec.salvage_reserve_gaap + c_rec.ibnr_gap_balance;
        c_rec.losses_gap_incurred := 0;
        c_rec.lae_gap_incurred := 0;
        c_rec.stat_recovered_pl := nvl(c_rec.losses_sap_recovered,0);

end if; -- check if it is newly terminated

if p_batch_mode then
    batch_list_losses_rec(p_losses_k) := c_rec;
else
    update ABOB_USER.abob_tbl_losses set
-- update the beginning columns, 26 columns    
-- set the STAT beginning    
        beg_case_stat = c_rec.beg_case_stat,
        beg_salvage_stat = c_rec.beg_salvage_stat,
        beg_ibnr_stat = c_rec.beg_ibnr_stat,
        beg_lae_case_stat = c_rec.beg_lae_case_stat,
        beg_lae_salvage_stat = c_rec.beg_lae_salvage_stat,
        beg_stat_undiscounted_loss_res = c_rec.beg_stat_undiscounted_loss_res,
        beg_stat_undiscounted_salv_res = c_rec.beg_stat_undiscounted_salv_res,        
-- set GAAP reserve beginning        
        beg_case_gaap = c_rec.beg_case_gaap,
        beg_salvage_gaap = c_rec.beg_salvage_gaap,
        beg_lae_case_gaap = c_rec.beg_lae_case_gaap,
        beg_lae_salvage_gaap = c_rec.beg_lae_salvage_gaap,
        beg_ibnr_gaap = c_rec.beg_ibnr_gaap,
-- set contra beginning
        beg_contra_paid = c_rec.beg_contra_paid,
--        beg_contra_wrapped = c_rec.beg_contra_wrapped,
        beg_contra_loss_mit = c_rec.beg_contra_loss_mit,
        beg_salv_gaap_paid = c_rec.beg_salv_gaap_paid,
        beg_salv_gaap_loss_mit = c_rec.beg_salv_gaap_loss_mit,        
--        beg_salv_gaap_wrapped = c_rec.beg_salv_gaap_wrapped,
        beg_other_income = c_rec.beg_other_income,
        beg_other_income_stat = c_rec.beg_other_income_stat,
        beg_salv_res_incurred_benefit = c_rec.beg_salv_res_incurred_benefit,
-- set ITD payments beginning
        beg_itd_paid_gaap = c_rec.beg_itd_paid_gaap,
        beg_itd_recovered_gaap = c_rec.beg_itd_recovered_gaap,
        beg_itd_lae_paid_gaap = c_rec.beg_itd_lae_paid_gaap,
        beg_itd_lae_recovered_gaap = c_rec.beg_itd_lae_recovered_gaap,
        beg_itd_tsc_paid_gaap = c_rec.beg_itd_tsc_paid_gaap,
--        beg_itd_wrapped = c_rec.beg_itd_wrapped,
        beg_itd_loss_mit = c_rec.beg_itd_loss_mit,
--        beg_itd_wrapped_int = c_rec.beg_itd_wrapped_int,
        beg_itd_loss_mit_int = c_rec.beg_itd_loss_mit_int,
        beg_gaap_upr = c_rec.beg_gaap_upr,
-- GAAP expected beginning        
        BEG_EXP_CASE_GAAP = c_rec.BEG_EXP_CASE_GAAP,
        BEG_EXP_SALVAGE_GAAP = c_rec.BEG_EXP_SALVAGE_GAAP,
        BEG_EXP_LAE_CASE_GAAP = c_rec.BEG_EXP_LAE_CASE_GAAP,
        BEG_EXP_LAE_SALVAGE_GAAP = c_rec.BEG_EXP_LAE_SALVAGE_GAAP,           
 
-- update the ending columns for GAAP and Contra, 29 columns
-- set GAAP reserve ending        
        case_res_gaap = c_rec.case_res_gaap,
        salvage_res_gaap = c_rec.salvage_res_gaap,
        lae_res_gaap = c_rec.lae_res_gaap,
        lae_salvage_res_gaap = c_rec.lae_salvage_res_gaap,
        ibnr_res_gaap = c_rec.ibnr_res_gaap,
-- set contra ending
        contra_bal_paid = c_rec.contra_bal_paid,
--        contra_bal_wrapped = c_rec.contra_bal_wrapped,
        contra_bal_loss_mit = c_rec.contra_bal_loss_mit,
        salvage_res_gaap_paid = c_rec.salvage_res_gaap_paid,
--        salvage_res_gaap_wrapped = c_rec.salvage_res_gaap_wrapped,
        salvage_res_gaap_loss_mit = c_rec.salvage_res_gaap_loss_mit,
        other_income = c_rec.other_income,
        other_income_stat = c_rec.other_income_stat,
-- set ITD payments beginning
        end_itd_paid_gaap = c_rec.end_itd_paid_gaap,
        end_itd_recovered_gaap = c_rec.end_itd_recovered_gaap,
        end_itd_lae_paid_gaap = c_rec.end_itd_lae_paid_gaap,
        end_itd_lae_recovered_gaap = c_rec.end_itd_lae_recovered_gaap,
        end_itd_tsc_paid_gaap = c_rec.end_itd_tsc_paid_gaap,
--        end_itd_wrapped = c_rec.end_itd_wrapped,
        end_itd_loss_mit = c_rec.end_itd_loss_mit,
--        end_itd_wrapped_int = c_rec.end_itd_wrapped_int,
        end_itd_loss_mit_int = c_rec.end_itd_loss_mit_int,
-- contra through PL, and reclass
        contra_pl_paid = c_rec.contra_pl_paid,
--        contra_pl_wrapped = c_rec.contra_pl_wrapped,
        contra_pl_loss_mit = c_rec.contra_pl_loss_mit,
        contra_reclass_salv_paid = c_rec.contra_reclass_salv_paid,
--        contra_reclass_salv_wrapped = c_rec.contra_reclass_salv_wrapped
        contra_reclass_salv_loss_mit = c_rec.contra_reclass_salv_loss_mit,
        calc_method = c_rec.calc_method,
        prev_qtr_contra_paid = c_rec.prev_qtr_contra_paid,
        prev_qtr_contra_loss_mit = c_rec.prev_qtr_contra_loss_mit,  
        gaap_pl_paid = c_rec.gaap_pl_paid,
        gaap_pl_loss_mit = c_rec.gaap_pl_loss_mit,
        stat_undiscounted_loss_res = c_rec.stat_undiscounted_loss_res,
        stat_undiscounted_salv_res = c_rec.stat_undiscounted_salv_res,
        salv_res_incurred_benefit = c_rec.salv_res_incurred_benefit,   
-- termination reversal fields, 20 columns
-- first send the remaining reserve to corresponding cash cloumns as reversal   
        LOSSES_SAP_PAID = c_rec.LOSSES_SAP_PAID,
        LOSSES_SAP_RECOVERED = c_rec.LOSSES_SAP_RECOVERED,
        LAE_SAP_PAID = c_rec.LAE_SAP_PAID,
        LAE_SAP_RECOVERED = c_rec.LAE_SAP_RECOVERED,
-- then set the reserve to 0                   
        GROSS_RESERVE = c_rec.GROSS_RESERVE,
        SALVAGE_RESERVE = c_rec.SALVAGE_RESERVE,
        IBNR_SAP_BALANCE = c_rec.IBNR_SAP_BALANCE,
        lae_sap_balance  = c_rec.lae_sap_balance,
        lae_salvage_sap_balance = c_rec.lae_salvage_sap_balance,     
-- update the calculated columns
        losses_sap_balance = c_rec.losses_sap_balance,
        losses_sap_incurred = c_rec.losses_sap_incurred,
        lae_sap_incurred = c_rec.lae_sap_incurred,                                           
-- none Contra GAAP - i.e. GAAP Expected numbers
        gross_reserve_gaap = c_rec.gross_reserve_gaap,
        salvage_reserve_gaap = c_rec.salvage_reserve_gaap,
        ibnr_gap_balance = c_rec.ibnr_gap_balance,
        lae_gap_balance = c_rec.lae_gap_balance,
        lae_salvage_gap_balance = c_rec.lae_salvage_gap_balance,
        losses_gap_balance = c_rec.losses_gap_balance,
        losses_gap_incurred = c_rec.losses_gap_incurred,
        lae_gap_incurred = c_rec.lae_gap_incurred,
        stat_recovered_pl = c_rec.stat_recovered_pl        
    where current of cur_losses_row;         

    close cur_losses_row;
end if;

-- now processing future rows, set everything to 0
for f_rec in future_rows
(p_rev_gig_k
,c_rec.CURRENCY_DESC_K
,p_acct_year
,p_acct_month
,c_rec.deal_currency
,c_rec.usd
,c_rec.inter_side
)
loop

-- for the future, it has already been terminated, just keep everything 0

-- update the beginning columns, 25 columns - still set to previous value plus transition adjustment    
-- set the STAT beginning
        f_rec.beg_case_stat := 0;
        f_rec.beg_salvage_stat := 0;
        f_rec.beg_ibnr_stat := 0;
        f_rec.beg_lae_case_stat := 0;
        f_rec.beg_lae_salvage_stat := 0;
        f_rec.beg_stat_undiscounted_loss_res := 0;
        f_rec.beg_stat_undiscounted_salv_res := 0;
-- set GAAP reserve beginning        
        f_rec.beg_case_gaap := 0;
        f_rec.beg_salvage_gaap := 0;
        f_rec.beg_lae_case_gaap := 0;
        f_rec.beg_lae_salvage_gaap := 0;
        f_rec.beg_ibnr_gaap := 0;
-- set contra beginning
        f_rec.beg_contra_paid := 0;
        f_rec.beg_contra_loss_mit := 0;
        f_rec.beg_salv_gaap_paid := 0;
        f_rec.beg_salv_gaap_loss_mit := 0;
        f_rec.beg_other_income := nvl(c_rec.other_income,0);
        f_rec.beg_other_income_stat := nvl(c_rec.other_income_stat,0);
        f_rec.beg_salv_res_incurred_benefit := 0;
-- set ITD payments beginning
        f_rec.beg_itd_paid_gaap := nvl(c_rec.end_itd_paid_gaap,0);
        f_rec.beg_itd_recovered_gaap := nvl(c_rec.end_itd_recovered_gaap,0);
        f_rec.beg_itd_lae_paid_gaap := nvl(c_rec.end_itd_lae_paid_gaap,0);
        f_rec.beg_itd_lae_recovered_gaap := nvl(c_rec.end_itd_lae_recovered_gaap,0);
        f_rec.beg_itd_tsc_paid_gaap := nvl(c_rec.end_itd_tsc_paid_gaap,0);
        f_rec.beg_itd_loss_mit := nvl(c_rec.end_itd_loss_mit,0);
        f_rec.beg_itd_loss_mit_int := nvl(c_rec.end_itd_loss_mit_int,0);
--        f_rec.beg_gaap_upr := nvl(f_rec.f_gaap_upr,0) + nvl(f_rec.f_gaap_upr_ta,0);  -- leave it as last forecasted
-- GAAP expected beginning        
        f_rec.BEG_EXP_CASE_GAAP := 0;
        f_rec.BEG_EXP_SALVAGE_GAAP := 0; 
        f_rec.BEG_EXP_LAE_CASE_GAAP := 0;  
        f_rec.BEG_EXP_LAE_SALVAGE_GAAP := 0;

-- update the ending columns for GAAP and Contra, 29 columns

-- set GAAP reserve ending        
        f_rec.case_res_gaap :=  0;
        f_rec.salvage_res_gaap := 0;
        f_rec.lae_res_gaap := 0;
        f_rec.lae_salvage_res_gaap := 0;
        f_rec.ibnr_res_gaap := 0;
-- set contra ending
-- move remaining contra to PL
        f_rec.contra_pl_paid := 0;
        f_rec.contra_pl_loss_mit := 0;
        f_rec.contra_bal_paid := 0;
        f_rec.contra_bal_loss_mit := 0;
        f_rec.salvage_res_gaap_paid := 0;
        f_rec.salvage_res_gaap_loss_mit := 0;
-- keepking other income?
        f_rec.other_income := f_rec.beg_other_income;
        f_rec.other_income_stat := f_rec.beg_other_income_stat;
-- set ITD payments ending
        f_rec.end_itd_paid_gaap := f_rec.beg_itd_paid_gaap;
        f_rec.end_itd_recovered_gaap := f_rec.beg_itd_recovered_gaap;
        f_rec.end_itd_lae_paid_gaap := f_rec.beg_itd_lae_paid_gaap;
        f_rec.end_itd_lae_recovered_gaap := f_rec.beg_itd_lae_recovered_gaap;
        f_rec.end_itd_tsc_paid_gaap := f_rec.beg_itd_tsc_paid_gaap;
        f_rec.end_itd_loss_mit := f_rec.beg_itd_loss_mit;
        f_rec.end_itd_loss_mit_int := f_rec.beg_itd_loss_mit_int;
-- no contra reclass
        f_rec.contra_reclass_salv_paid := 0;  
        f_rec.contra_reclass_salv_loss_mit := 0;
        f_rec.calc_method := 'T';  
        f_rec.prev_qtr_contra_paid := 
            case
                when mod(c_rec.month,3) = 0 then 0  -- current period is quarter end, future period all take the current ending, which is 0
                when f_rec.lacctyr_k = c_rec.lacctyr_k and (f_rec.month - c_rec.month) <= (3 - mod(c_rec.month,3))
                    then c_rec.prev_qtr_contra_paid  --current period is non quarter end, up to 2 future period can take the prior quarter end
                else 0  -- future years, just 0
            end;
        f_rec.prev_qtr_contra_loss_mit := 
            case
                when mod(c_rec.month,3) = 0 then 0
                when f_rec.lacctyr_k = c_rec.lacctyr_k and (f_rec.month - c_rec.month) <= (3 - mod(c_rec.month,3))
                    then c_rec.prev_qtr_contra_loss_mit  
                else 0
            end;
        f_rec.gaap_pl_paid := 0;
        f_rec.gaap_pl_loss_mit := 0;            
   
        f_rec.stat_undiscounted_loss_res := 0;
        f_rec.stat_undiscounted_salv_res := 0;
        f_rec.salv_res_incurred_benefit := 0;             

-- setting STAT ending
-- first send the remaining reserve to corresponding cash cloumns as reversal   
        f_rec.LOSSES_SAP_PAID := 0;
        f_rec.LOSSES_SAP_RECOVERED := 0;
        f_rec.LAE_SAP_PAID := 0;
        f_rec.LAE_SAP_RECOVERED := 0;
-- then set the reserve to 0                   
        f_rec.GROSS_RESERVE := 0;
        f_rec.SALVAGE_RESERVE := 0;
        f_rec.IBNR_SAP_BALANCE := 0;
        f_rec.lae_sap_balance  := 0;
        f_rec.lae_salvage_sap_balance := 0;     
-- update the calculated columns
        f_rec.losses_sap_balance := 0;
        f_rec.losses_sap_incurred := 0;
        f_rec.lae_sap_incurred := 0;                                           

-- none Contra GAAP - i.e. GAAP Expected numbers
        f_rec.gross_reserve_gaap := 0;
        f_rec.salvage_reserve_gaap := 0;
        f_rec.ibnr_gap_balance := 0;
        f_rec.lae_gap_balance := 0;
        f_rec.lae_salvage_gap_balance := 0;
        f_rec.losses_gap_balance := 0;
        f_rec.losses_gap_incurred := 0;
        f_rec.lae_gap_incurred := 0;
        
        f_rec.stat_recovered_pl := 0;

    if p_batch_mode then
        batch_list_losses_rec(f_rec.losses_k) := f_rec;
    else

        update ABOB_USER.abob_tbl_losses set
    -- update the beginning columns, 26 columns    
    -- set the STAT beginning    
            beg_case_stat = f_rec.beg_case_stat,
            beg_salvage_stat = f_rec.beg_salvage_stat,
            beg_ibnr_stat = f_rec.beg_ibnr_stat,
            beg_lae_case_stat = f_rec.beg_lae_case_stat,
            beg_lae_salvage_stat = f_rec.beg_lae_salvage_stat,
            beg_stat_undiscounted_loss_res = f_rec.beg_stat_undiscounted_loss_res,
            beg_stat_undiscounted_salv_res = f_rec.beg_stat_undiscounted_salv_res,        
    -- set GAAP reserve beginning        
            beg_case_gaap = f_rec.beg_case_gaap,
            beg_salvage_gaap = f_rec.beg_salvage_gaap,
            beg_lae_case_gaap = f_rec.beg_lae_case_gaap,
            beg_lae_salvage_gaap = f_rec.beg_lae_salvage_gaap,
            beg_ibnr_gaap = f_rec.beg_ibnr_gaap,
    -- set contra beginning
            beg_contra_paid = f_rec.beg_contra_paid,
    --        beg_contra_wrapped = f_rec.beg_contra_wrapped,
            beg_contra_loss_mit = f_rec.beg_contra_loss_mit,
            beg_salv_gaap_paid = f_rec.beg_salv_gaap_paid,
            beg_salv_gaap_loss_mit = f_rec.beg_salv_gaap_loss_mit,        
    --        beg_salv_gaap_wrapped = f_rec.beg_salv_gaap_wrapped,
            beg_other_income = f_rec.beg_other_income,
            beg_other_income_stat = f_rec.beg_other_income_stat,
            beg_salv_res_incurred_benefit = f_rec.beg_salv_res_incurred_benefit,
    -- set ITD payments beginning
            beg_itd_paid_gaap = f_rec.beg_itd_paid_gaap,
            beg_itd_recovered_gaap = f_rec.beg_itd_recovered_gaap,
            beg_itd_lae_paid_gaap = f_rec.beg_itd_lae_paid_gaap,
            beg_itd_lae_recovered_gaap = f_rec.beg_itd_lae_recovered_gaap,
            beg_itd_tsc_paid_gaap = f_rec.beg_itd_tsc_paid_gaap,
    --        beg_itd_wrapped = f_rec.beg_itd_wrapped,
            beg_itd_loss_mit = f_rec.beg_itd_loss_mit,
    --        beg_itd_wrapped_int = f_rec.beg_itd_wrapped_int,
            beg_itd_loss_mit_int = f_rec.beg_itd_loss_mit_int,
            beg_gaap_upr = f_rec.beg_gaap_upr,
-- GAAP expected beginning        
            BEG_EXP_CASE_GAAP = c_rec.BEG_EXP_CASE_GAAP,
            BEG_EXP_SALVAGE_GAAP = c_rec.BEG_EXP_SALVAGE_GAAP,
            BEG_EXP_LAE_CASE_GAAP = c_rec.BEG_EXP_LAE_CASE_GAAP,
            BEG_EXP_LAE_SALVAGE_GAAP = c_rec.BEG_EXP_LAE_SALVAGE_GAAP,               
     
    -- update the ending columns for GAAP and Contra, 29 columns
    -- set GAAP reserve ending        
            case_res_gaap = f_rec.case_res_gaap,
            salvage_res_gaap = f_rec.salvage_res_gaap,
            lae_res_gaap = f_rec.lae_res_gaap,
            lae_salvage_res_gaap = f_rec.lae_salvage_res_gaap,
            ibnr_res_gaap = f_rec.ibnr_res_gaap,
    -- set contra ending
            contra_bal_paid = f_rec.contra_bal_paid,
    --        contra_bal_wrapped = f_rec.contra_bal_wrapped,
            contra_bal_loss_mit = f_rec.contra_bal_loss_mit,
            salvage_res_gaap_paid = f_rec.salvage_res_gaap_paid,
    --        salvage_res_gaap_wrapped = f_rec.salvage_res_gaap_wrapped,
            salvage_res_gaap_loss_mit = f_rec.salvage_res_gaap_loss_mit,
            other_income = f_rec.other_income,
            other_income_stat = f_rec.other_income_stat,
    -- set ITD payments beginning
            end_itd_paid_gaap = f_rec.end_itd_paid_gaap,
            end_itd_recovered_gaap = f_rec.end_itd_recovered_gaap,
            end_itd_lae_paid_gaap = f_rec.end_itd_lae_paid_gaap,
            end_itd_lae_recovered_gaap = f_rec.end_itd_lae_recovered_gaap,
            end_itd_tsc_paid_gaap = f_rec.end_itd_tsc_paid_gaap,
    --        end_itd_wrapped = f_rec.end_itd_wrapped,
            end_itd_loss_mit = f_rec.end_itd_loss_mit,
    --        end_itd_wrapped_int = f_rec.end_itd_wrapped_int,
            end_itd_loss_mit_int = f_rec.end_itd_loss_mit_int,
    -- contra through PL, and reclass
            contra_pl_paid = f_rec.contra_pl_paid,
    --        contra_pl_wrapped = f_rec.contra_pl_wrapped,
            contra_pl_loss_mit = f_rec.contra_pl_loss_mit,
            contra_reclass_salv_paid = f_rec.contra_reclass_salv_paid,
    --        contra_reclass_salv_wrapped = f_rec.contra_reclass_salv_wrapped
            contra_reclass_salv_loss_mit = f_rec.contra_reclass_salv_loss_mit,
            calc_method = f_rec.calc_method,
            prev_qtr_contra_paid = f_rec.prev_qtr_contra_paid,
            prev_qtr_contra_loss_mit = f_rec.prev_qtr_contra_loss_mit,  
            gaap_pl_paid = f_rec.gaap_pl_paid,
            gaap_pl_loss_mit = f_rec.gaap_pl_loss_mit,
            stat_undiscounted_loss_res = f_rec.stat_undiscounted_loss_res,
            stat_undiscounted_salv_res = f_rec.stat_undiscounted_salv_res,
            salv_res_incurred_benefit = f_rec.salv_res_incurred_benefit,   
    -- termination reversal fields, 20 columns
    -- first send the remaining reserve to corresponding cash cloumns as reversal   
            LOSSES_SAP_PAID = f_rec.LOSSES_SAP_PAID,
            LOSSES_SAP_RECOVERED = f_rec.LOSSES_SAP_RECOVERED,
            LAE_SAP_PAID = f_rec.LAE_SAP_PAID,
            LAE_SAP_RECOVERED = f_rec.LAE_SAP_RECOVERED,
    -- then set the reserve to 0                   
            GROSS_RESERVE = f_rec.GROSS_RESERVE,
            SALVAGE_RESERVE = f_rec.SALVAGE_RESERVE,
            IBNR_SAP_BALANCE = f_rec.IBNR_SAP_BALANCE,
            lae_sap_balance  = f_rec.lae_sap_balance,
            lae_salvage_sap_balance = f_rec.lae_salvage_sap_balance,     
    -- update the calculated columns
            losses_sap_balance = f_rec.losses_sap_balance,
            losses_sap_incurred = f_rec.losses_sap_incurred,
            lae_sap_incurred = f_rec.lae_sap_incurred,                                           
    -- none Contra GAAP - i.e. GAAP Expected numbers
            gross_reserve_gaap = f_rec.gross_reserve_gaap,
            salvage_reserve_gaap = f_rec.salvage_reserve_gaap,
            ibnr_gap_balance = f_rec.ibnr_gap_balance,
            lae_gap_balance = f_rec.lae_gap_balance,
            lae_salvage_gap_balance = f_rec.lae_salvage_gap_balance,
            losses_gap_balance = f_rec.losses_gap_balance,
            losses_gap_incurred = f_rec.losses_gap_incurred,
            lae_gap_incurred = f_rec.lae_gap_incurred,  
            stat_recovered_pl = f_rec.stat_recovered_pl      
        where losses_k = f_rec.losses_k;                
    end if;

end loop;
           
end; -- terminated_cession

PROCEDURE init_gig_termination(
        p_gig_term_array in out tbl_gig_term_date,
        p_policy_num IN abob_user.abob_tbl_corp_gig.policy_num%TYPE default null,
        p_policy_sub IN abob_user.abob_tbl_corp_gig.policy_sub%TYPE default null
        ) is

tmp_gig_term_date tbl_gig_term_date;

c_limit number := 200;

cursor cur_gig_term is
select distinct
     rs."gig_k"
    ,abob_fun_sql_date(rs."terminate_dt")
    ,abob_fun_sql_date(rs."stop_dt")
    ,abob_fun_sql_date(rs."start_dt")
    ,CG.ORIGIN_CO
    ,CG.OWNER_CO
from ABOB_USER.das_reins_struc_s rs, ABOB_USER.ABOB_TBL_CORP_GIG cg
where rs."gig_k" = CG.CORP_GIG_K
and nvl(rtrim(nvl(p_policy_num, cg.policy_num)),-1) = nvl(rtrim(cg.policy_num),-1)
and nvl(rtrim(nvl(p_policy_sub, cg.policy_sub)),-1) = nvl(rtrim(cg.policy_sub),-1)
;

/*
cursor cur_gig_term is
select distinct
     rs."gig_k"
    ,rs."terminate_dt"
    ,rs."stop_dt"
    ,rs."start_dt"
    ,CG.ORIGIN_CO
    ,CG.OWNER_CO
from ABOB_USER.das_reins_struc_s rs, ABOB_USER.ABOB_TBL_CORP_GIG cg
where rs."gig_k" = CG.CORP_GIG_K
and nvl(rtrim(nvl(p_policy_num, cg.policy_num)),-1) = nvl(rtrim(cg.policy_num),-1)
and nvl(rtrim(nvl(p_policy_sub, cg.policy_sub)),-1) = nvl(rtrim(cg.policy_sub),-1)
;
*/
begin

abob_user.Spc_Debug('Init GIG Termination - Start initialization');

if p_gig_term_array.count = 0 then

    open cur_gig_term;
    loop

        fetch cur_gig_term
        bulk collect into
            tmp_gig_term_date
        limit c_limit
        ;
        exit when tmp_gig_term_date.count = 0
        ;
        
        for indx in 1 .. tmp_gig_term_date.count
        loop
            lst_gig_term_date(tmp_gig_term_date(indx).gig_k) := tmp_gig_term_date(indx);     
        end loop;

    end loop;

    commit;
    p_gig_term_array := lst_gig_term_date;
    
else
abob_user.Spc_Debug('Init GIG Termination - Array already initialized');
    lst_gig_term_date := p_gig_term_array;
end if;

abob_user.Spc_Debug('Init GIG Termination - Done initialization; '||lst_gig_term_date.count||' policies initialized');

end; -- init_gig_termination

END ABOB_PKG_LOSS_CONTRA;
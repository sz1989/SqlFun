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
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
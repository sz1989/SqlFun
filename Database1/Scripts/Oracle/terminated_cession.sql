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
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
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
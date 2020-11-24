create or replace PACKAGE BODY           abob_pkg_losses_upload  is


--PROCEDURE create_rein_detail(anLoadBatchK IN abob_tbl_load_batch.load_batch_k%type, anReturn out number);

/******************************************************************************
Purpose:  Package will move data from the spreadsheet upload staging table into abob_tbl_losses
    Staging table holds gross losses.  This will push down to cessions based on rein pct in core or abob override pct
    It assumes all loss structures are entered (abob_Tbl_lossgig, losses, lossyears)

    package return 0 for sucess and -1 for failure
    
    

Update Log:
    08/15/13 AJH Top10-8 Initial version
    03/29/17 AJH SQL gateway return dates as char.  put function around core dates to convert to date
   11/30/17 YY Add step to calculate pooling agreement reins_pct during initialization step
   10/12/18 AJH modified insert into abob_tbl_das_reins_struc  changed select * to select actual column names
******************************************************************************/

-- private package variables
bContinue boolean := TRUE;
bInitialized boolean := FALSE;
sError varchar(100);

nCurrentPeriod number;
nCurrentMonth number;
nCurrentYear number;
dCurrentPeriodBeg date;
dCurrentPeriodEnd date;
nClear number;
nCnt number;

cursor cur (anLoadBatchK number) is 
-- all ag gigs for the policiy numbers in the batch
-- YY change to pulling in all active gigs for the policy number
select 
    load_losses_k, 
    ll.policy_num, 
    ll.policy_sub, 
    g.corp_gig_k,
    ll.accident_year
from 
    abob_user.abob_tbl_load_losses ll, 
    abob_user.abob_tbl_corp_gig g
    ,ABOB_USER.ABOB_TBL_DAS_REINS_STRUC_S rs
where 
    ll.load_batch_k = anLoadBatchK and 
    ll.policy_num = g.policy_num and
    nvl(rtrim(ll.policy_sub),'null') = nvl(rtrim(g.policy_sub),'null')
    and rs."gig_k" = g.corp_gig_k
    and (
        (origin_co > 100 and owner_co < 100)  -- for direct and external assumed, always populate
            or
        ( (origin_co < 100 or owner_co < 100) and     
            NOT
            (abob_user.abob_fun_sql_date(rs."start_dt" )> dCurrentPeriodEnd or 
    --    (abob_user.abob_fun_sql_date(rs."stop_dt" ) is not null and abob_user.abob_fun_sql_date(rs."stop_dt" ) < dCurrentPeriodBeg) or 
            (nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_user.abob_fun_sql_date(rs."stop_dt" )) is not null and nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_user.abob_fun_sql_date(rs."stop_dt" )) < dCurrentPeriodBeg))
        )   -- for cessions, limit to active only
        )    
    ;    



procedure initialize_package IS

v_sql long;

begin
-- initialize
spc_debug(' starting initialize package');
nCurrentPeriod := abob_pkg_archive.get_current_period('LOSS');
nCurrentYear := to_number(substr(to_char(nCurrentPeriod),1,4));
nCurrentMonth := to_number(substr(to_char(nCurrentPeriod),5,2));
dCurrentPeriodBeg := to_date(nCurrentMonth||'/01/'||nCurrentYear,'mm/dd/yyyy');
dCurrentPeriodEnd := last_day(dCurrentPeriodBeg);

-- cache the das_reins_struc_s table to avoid going across the Oracle/SQL gateway multiple times
v_sql := 'truncate table ABOB_USER.ABOB_TBL_DAS_REINS_STRUC_S';
execute immediate v_sql;


v_sql :=
'insert into abob_tbl_das_reins_struc_s
("stream_no",
"parent_stream_no",
"policy_num",
"policy_sub",
"treaty",
"loss_pos",
"tran_num",
"stream_type",
"start_dt",
"eff_dt",
"stop_dt",
"terminate_dt",
"pct_reins",
"pct_prem",
"real_parent_stream_no",
"reins_co",
"net_pct_reins",
"cont_res_method",
"gig_k",
"chg_dt",
"net_pct_prem",
"parent_id",
"real_parent_id",
"policy_id")
select 
"stream_no",
"parent_stream_no",
"policy_num",
"policy_sub",
"treaty",
"loss_pos",
"tran_num",
"stream_type",
"start_dt",
"eff_dt",
"stop_dt",
"terminate_dt",
"pct_reins",
"pct_prem",
"real_parent_stream_no",
"reins_co",
"net_pct_reins",
"cont_res_method",
"gig_k",
"chg_dt",
"net_pct_prem",
"parent_id",
"real_parent_id",
"policy_id"
from abob_user.das_reins_struc_s';

execute immediate v_sql;

--v_sql := 'insert into ABOB_TBL_DAS_REINS_STRUC_S select * from das_reins_struc_s';
--execute immediate v_sql;

-- For pooling agreement streams (PP), the reins_pct (gross reins percent) is incorrect in Core, need to recalculate in the cache table
-- the formula is PP Gross Reins Pct = PP Net Reins Pct + SUM(Net Reins Pct of Descendants of PP)

v_sql := 'truncate table ABOB_USER.ABOB_TBL_PP_REINS_PCT';
execute immediate v_sql;




v_sql := 
'insert into ABOB_TBL_PP_REINS_PCT
(stream_no
,orig_pct_reins
,modify_pct_reins
)
(
select
 pc."pp_parent_stream_no" stream_no
,pc."pp_parent_pct_reins" orig_pct_reins
,sum(pc."net_pct_reins") modify_pct_reins
from 
(
select
 s."stream_no"
,s."gig_k"
,s."parent_stream_no"
,s."stream_type"
,s."net_pct_reins"
,s."pct_reins"
,connect_by_root "stream_no" "pp_parent_stream_no"
,connect_by_root "stream_type" "pp_parent_stream_type"
,connect_by_root "gig_k" "pp_parent_gig_k"
,connect_by_root "pct_reins" "pp_parent_pct_reins"
,LEVEL
from ABOB_TBL_DAS_REINS_STRUC_S s
where s."stop_dt" is null and s."terminate_dt" is null
start with s."stream_type" = ''PP''
connect by nocycle "parent_stream_no" = prior "stream_no"
order siblings by "parent_stream_no"
) pc
group by
 pc."pp_parent_stream_no" 
,pc."pp_parent_pct_reins" 
)';

execute immediate v_sql;

v_sql := 
'update abob_tbl_das_reins_struc_s d
set d."pct_reins"
=
(
select
 s.modify_pct_reins
from ABOB_TBL_PP_REINS_PCT s
where  s.stream_no = d."stream_no"
)
where exists
(
select
 1
from ABOB_TBL_PP_REINS_PCT s
where  s.stream_no = d."stream_no"
)';


execute immediate v_sql;
spc_debug(' complete initialize');

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20109, 'initialize_package '|| SQLERRM);


end; -- initialize package




procedure update_currency_desc_k(anLoadBatchK abob_user.abob_tbl_load_batch.load_batch_k%type)IS

begin


update abob_user.abob_tbl_load_losses u
set currency_desc_k = (select currency_desc_k from gbl_user.gbl_tbl_currency_desc cd where u.currency_iso = cd.currency_iso)
where load_batch_k = anLoadBatchK;

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20107, 'update_currency_desc_k '|| SQLERRM);


end;

procedure update_loss_layer(anLoadBatchK abob_user.abob_tbl_load_batch.load_batch_k%type, anReturn out number)IS

begin

update abob_user.abob_tbl_load_losses u
set u.loss_layer_yn = 
    (select decode(count(*),0,'N',null,null,'Y') from abob_user.ABOB_TBL_DAS_REINS_STRUC_S rs
     where 
        u.policy_num = rs."policy_num" and 
        nvl(rtrim(u.policy_sub),'null') = nvl(rtrim(rs."policy_sub"),'null') and    
     rtrim(nvl(rs."loss_pos", '0')) <> '0')
where load_batch_k = anLoadBatchK;

commit;

anReturn := 0;

END;


procedure validate_user_input (anLoadBatchK IN abob_tbl_load_batch.load_batch_k%type, anReturn out number) IS  


-- validations tbd
-- return 0 for sucess - everything validated ok
-- return -1 if any of the validations failed
v_Cnt number;
nExistingRevGigK number;
v_result number;
v_error_count number;
v_update number;
v_msg varchar(100);

-- cursor for duplicate records
cursor cur_dup_record is 
select 
    load_batch_k,
    policy_num,
    policy_sub,
    accident_year,
    currency_iso,
    count(*)
from abob_user.abob_tbl_load_losses
where load_batch_k = anLoadBatchK
group by 
    load_batch_k,
    policy_num,
    policy_sub,
    accident_year,
    currency_iso
having count(*) > 1;

cursor cur_multi_ay is
select 
    load_batch_k,
    policy_num,
    policy_sub,
     max(accident_year) accident_year
    ,count(distinct accident_year) count_ay
from abob_user.abob_tbl_load_losses
where load_batch_k = anLoadBatchK
group by
    load_batch_k,
    policy_num,
    policy_sub
having count(distinct accident_year) > 1    
;

cursor cur_policy is
select
 load_batch_k
,policy_num
,policy_sub
,max(accident_year) accident_year
,min(bypass_warning) bypass_warning
from (
select distinct
    ll.load_batch_k,
    ll.policy_num,
    ll.policy_sub,
    ll.accident_year
    ,G.CORP_GIG_K
    ,LG.REV_GIG_K
    ,LG.ACCIDENT_YEAR ay2
    ,nvl(ll.BYPASS_WARNING,'F') bypass_warning
from
 abob_user.abob_tbl_load_losses ll
,abob_user.abob_tbl_corp_gig g
,ABOB_USER.ABOB_TBL_DAS_REINS_STRUC_S rs
,ABOB_USER.ABOB_TBL_LOSSGIG lg
where load_batch_k = anLoadBatchK
and LL.POLICY_NUM = G.POLICY_NUM
and nvl(rtrim(LL.POLICY_SUB),'null') = nvl(rtrim(g.policy_sub),'null')
and G.CORP_GIG_K = LG.GIG_K(+)
--and LL.ACCIDENT_YEAR = LG.ACCIDENT_YEAR
and rs."gig_k" = g.corp_gig_k
and (
        (origin_co > 100 and owner_co < 100)  -- for direct and external assumed, always populate
            or
        ((origin_co < 100 or owner_co < 100) and     
            NOT
            (abob_user.abob_fun_sql_date(rs."start_dt" )> dCurrentPeriodEnd or 
    --    (abob_user.abob_fun_sql_date(rs."stop_dt" ) is not null and abob_user.abob_fun_sql_date(rs."stop_dt" ) < dCurrentPeriodBeg) or 
            (nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_user.abob_fun_sql_date(rs."stop_dt" )) is not null and nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_user.abob_fun_sql_date(rs."stop_dt" )) < dCurrentPeriodBeg))
        )   -- for cessions, limit to active only
        )    
) s
where rev_gig_k is null or accident_year <> ay2
group by 
load_batch_k
,policy_num
,policy_sub
order by policy_num, policy_sub
;
type tbl_policy_num is table of ABOB_USER.ABOB_TBL_CORP_GIG.POLICY_NUM%type index by pls_integer
;
lst_policy_num tbl_policy_num
;
lst_multi_yr_pn tbl_policy_num
;
type tbl_policy_sub is table of ABOB_USER.ABOB_TBL_CORP_GIG.POLICY_SUB%type index by pls_integer
;
lst_policy_sub tbl_policy_sub
;
lst_multi_yr_ps tbl_policy_sub
;
type tbl_status is table of number index by pls_integer
;
lst_status tbl_status
;
type tbl_accident_year is table of ABOB_USER.ABOB_TBL_LOSSGIG.ACCIDENT_YEAR%type index by pls_integer
;
lst_accident_year tbl_accident_year
;
lst_multi_yr tbl_accident_year
;
type tbl_msg is table of varchar(100) index by pls_integer
;
lst_msg tbl_msg
;

BEGIN 

spc_debug('pkg_losses_upload.validate_user_input - start');

anReturn := 0;
initialize_package;
update_currency_desc_k(anLoadBatchK);

-- set to validated.  will be set to error code if there is an error
update abob_tbl_load_losses
set load_status = 25
where load_batch_k = anLoadBatchK;


-------------------------------------------------------------    
-- invalid currency_desc_k
update abob_tbl_load_losses u
set u.load_status = 36
where
    u.load_batch_k = anLoadBatchK and
    not exists (select 1 from gbl_user.gbl_tbl_currency_desc cd where u.currency_desc_k = cd.currency_desc_k);

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

-------------------------------------------------------------------------------------
-- invalid accident year
update abob_Tbl_load_losses u
set u.load_status = 37 
where 
    u.load_batch_k = anLoadBatchK and
    (u.accident_year < 1980 or u.accident_year > nCurrentYear);

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

------------------------------------------------------------------------------
-- invalid currency iso
update abob_tbl_load_losses u
set u.load_status = 39
where
    u.load_batch_k = anLoadBatchK and
    not exists (select 1 from gbl_user.gbl_tbl_currency_desc cd where u.currency_iso= cd.currency_iso);

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

---------------------------------------------------------------------------------
-- accounting year and month are current
-- user does not enter this.  It would be some programming problem is this occurs
update abob_tbl_load_losses u
set u.load_status = 40 
where
    u.load_batch_k = anLoadBatchK and
    (acct_year <> nCurrentYear or acct_month <> nCurrentMonth);

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

--------------------------------------------------------------------------
-- policy num is not null
update abob_tbl_load_losses u
set u.load_status = 41 
where
    u.load_batch_k = anLoadBatchK and
    u.policy_num is null;

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    


-------------------------------------------------------------------------
-- accident_year is not null
update abob_tbl_load_losses u
set u.load_status = 42 
where
    u.load_batch_k = anLoadBatchK and
    u.accident_year is null;

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

spc_debug('pkg_losses_upload.validate_user_input - checking for missing lossgig');

----------------------------------------------------------------------------
-- check lossgig exists
-- the cursor only has policy with missing lossgig, or different accident year
v_cnt := 0;
v_update := 0;
v_result := 25;
v_error_count := 0;
for rec in cur_policy loop
-- just check the whole policy
    add_missing_lossgig(rec.Policy_Num, rec.Policy_Sub, rec.accident_year,true, v_result,v_msg);  -- true for checking only

    CASE
        when v_result = 460 then
        -- successfully created new lossgig records
            v_cnt := v_cnt + 1;
            lst_status(lst_status.count + 1) := 25;
            lst_policy_num(lst_policy_num.count + 1) := rec.policy_num;
            lst_policy_sub(lst_policy_sub.count + 1) := rec.policy_sub;
            lst_accident_year(lst_accident_year.count + 1) := rec.accident_year;  
            lst_msg(lst_msg.count + 1) := v_msg;          
        when v_result = 461 then
            v_update := v_update + 1;
        -- the accident year is different between upload file and the system
            if nvl(rec.bypass_warning,'F') = 'T' then
                -- bypassing warning, set to pass
                lst_status(lst_status.count + 1) := 25;
            else
                -- not bypassing
                v_error_count := v_error_count + 1; 
                lst_status(lst_status.count + 1) := v_result;
            end if;            
            lst_policy_num(lst_policy_num.count + 1) := rec.policy_num;
            lst_policy_sub(lst_policy_sub.count + 1) := rec.policy_sub;
            lst_accident_year(lst_accident_year.count + 1) := rec.accident_year;
            lst_msg(lst_msg.count + 1) := v_msg;
        when v_result = 462 then
        -- no accident year was given (i.e. blank on the upload file), but in the system multiple accident years detected
        -- did not update the accident year
            lst_status(lst_status.count + 1) := 25;
            lst_policy_num(lst_policy_num.count + 1) := rec.policy_num;
            lst_policy_sub(lst_policy_sub.count + 1) := rec.policy_sub;
            lst_accident_year(lst_accident_year.count + 1) := rec.accident_year;
            lst_msg(lst_msg.count + 1) := v_msg;
        when v_result = 463 then
        -- an accident year was given, but in the system multiple accident years detected
        -- cannot automatically merge the accident years, need user intervention
            v_error_count := v_error_count + 1;
            lst_status(lst_status.count + 1) := v_result;
            lst_policy_num(lst_policy_num.count + 1) := rec.policy_num;
            lst_policy_sub(lst_policy_sub.count + 1) := rec.policy_sub;
            lst_accident_year(lst_accident_year.count + 1) := rec.accident_year;
            lst_msg(lst_msg.count + 1) := v_msg;
        else
            lst_status(lst_status.count + 1) := v_result;
            lst_policy_num(lst_policy_num.count + 1) := rec.policy_num;
            lst_policy_sub(lst_policy_sub.count + 1) := rec.policy_sub;
            lst_accident_year(lst_accident_year.count + 1) := rec.accident_year;
            lst_msg(lst_msg.count + 1) := v_msg;                        
    end case;
                            
end loop;

spc_debug('There are '||v_cnt||' new lossgigs');
spc_debug('There are '||v_update||' change in accident year');
spc_debug('There are '||v_error_count||' errors');
--v_cnt := lst_status.count - v_cnt;
--spc_debug('Updated accident year for '||v_cnt||' policies');

forall indx in 1..lst_policy_num.count 
    update abob_user.abob_tbl_load_losses u
        set u.load_status = lst_status(indx)
            ,u.Validation_Message = lst_msg(indx)
    where u.load_batch_k = anLoadBatchK
    and u.policy_num = lst_policy_num(indx)
    and nvl(rtrim(u.policy_sub),'null') = nvl(rtrim(lst_policy_sub(indx)),'null')
    and u.accident_year = lst_accident_year(indx);

if v_error_count > 0 then
    anReturn:= -1;
end if;
    
for rec in cur_multi_ay loop     

    if rec.count_ay > 1 then
    -- this indicates we have single policy with multiple accident year on the file, only the maximum accident year row will be considered
    -- setting an error code on the other row(s) to notify the user    
        lst_multi_yr_pn(lst_multi_yr_pn.count + 1) := rec.policy_num;
        lst_multi_yr_ps(lst_multi_yr_ps.count + 1) := rec.policy_sub;
        lst_multi_yr(lst_multi_yr.count + 1) := rec.accident_year;
        anReturn := -1;
--spc_debug('Multiple accident year for '||rec.policy_num||rec.policy_sub);        
    end if;    
       
end loop;
--spc_debug('Multiple accident year count is '||lst_multi_yr.count);

forall indx in 1..lst_multi_yr.count
    update abob_user.abob_tbl_load_losses u set
     u.load_status = 462
    ,u.Validation_Message = 'Multiple accident years for this policy in the upload file'
    where load_batch_k = anLoadBatchK
    and U.POLICY_NUM = lst_multi_yr_pn(indx)
    and rtrim(nvl(u.policy_sub,'null')) = rtrim(nvl(lst_multi_yr_ps(indx),'null'))
    and u.accident_year <> lst_multi_yr(indx)    
    ;        

spc_debug('Done missing lossgig');

----------------------------------------------------------------------
-- acct_year not null
update abob_tbl_load_losses u
set u.load_status = 43 
where
    u.load_batch_k = anLoadBatchK and
    u.acct_year is null;

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

----------------------------------------------------------------------
-- acct_month not null
update abob_tbl_load_losses u
set u.load_status = 44 
where
    u.load_batch_k = anLoadBatchK and
    u.acct_month is null;

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

------------------------------------------------------------------------------
-- currency iso not null
update abob_tbl_load_losses u
set u.load_status = 45 
where
    u.load_batch_k = anLoadBatchK and
    u.currency_iso is null;

IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

---------------------------------------------------------------
-- invalid policy number
-- if policy number exists in abob but not in core (ex credit or auto res) it is also flagged as invalid
update abob_tbl_load_losses u
set u.load_status = 38
where
    u.load_batch_k = anLoadBatchK and
    not exists (select 1 
                from abob_user.abob_tbl_corp_gig g 
                where 
                    u.policy_num = g.policy_num and
                    g.system = 'AGM' and 
                    nvl(rtrim(u.policy_sub),'null') = nvl(rtrim(g.policy_sub),'null'));
IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    
----------------------------------------------------------
-- duplicate records.  takes the place of AK.  This is more user friendly
for rec in cur_dup_record loop

    update abob_user.abob_tbl_load_losses
    set load_status = 47
    where 
        load_batch_k = rec.load_batch_k and
        policy_num = rec.policy_num and
        nvl(rtrim(policy_sub),'null') = nvl(rtrim(rec.policy_sub),'null') and
        accident_year = rec.accident_year and
        currency_iso = rec.currency_iso;

        anReturn := -1;
end loop;    

---------------------------------------------------------------
-- MTM policy having overrides in Contra columns
update abob_tbl_load_losses u
set u.load_status = 48
where
    u.load_batch_k = anLoadBatchK and
    (OR_CONTRA_BAL_PAID  is not null or
    OR_CONTRA_BAL_LOSS_MIT   is not null or
    OR_CONTRA_PL_PAID is not null or
    OR_CONTRA_PL_LOSS_MIT is not null or
    OR_CONTRA_RECLASS_SALV_PAID is not null or  
    OR_CONTRA_RECLASS_SAL_LOSS_MIT   is not null
    )
    and exists (select 1 
                from abob_user.abob_tbl_corp_gig cg 
                where 
                    u.policy_num = cg.policy_num and 
                    nvl(rtrim(u.policy_sub),'null') = nvl(rtrim(cg.policy_sub),'null')
                    and (cg.mtm_flg = 'Y' or CG.LINE_OF_BUSINESS not in (1,8))
                    );
IF sql%rowcount <> 0 THEN
    anReturn := -1;
END IF;    

-- all the main validations are done, do the insert/update to ensure there is no missing lossgig, and pass the very last check
if anReturn <> -1 then
    spc_debug('pkg_losses_upload.validate_user_input - validation passed; start adding missing lossgig');   
    for rec in cur_policy loop
        add_missing_lossgig(rec.Policy_Num, rec.Policy_Sub, rec.accident_year,false, v_result,v_msg);  -- false for doing the inserts/updates
    end loop;
    spc_debug('pkg_losses_upload.validate_user_input - done adding missing lossgig'); 
else
    spc_debug('pkg_losses_upload.validate_user_input - validation incomplete; missing lossgig NOT CREATED');
end if;

-- IMPORTANT, PLEASE DO NOT ADD ANY MORE CHECKS AFTER THIS STEP, NEED TO KEEP THIS AS THE LAST STEP

-- also if loss_year or losses are missing add them
-- still need to check this, as the add_missing_lossgig only add loss_year for new lossgig
-- and does not add loss_year for existing gig
for rec in cur(anLoadBatchK) loop

    -- see if an revgig record exists
    select count(*) , max(rev_gig_k)
    into nCnt, nExistingRevGigK
    from abob_user.abob_tbl_lossgig lg
    where 
        lg.gig_k = rec.corp_gig_k and
        lg.accident_year = rec.accident_year;

    IF nCnt = 0 THEN
    -- after checking the whole policy above, this branch is only possible if we could not update
    -- existing lossgig to the given accident_year
    -- by only limiting to load status = 1, we will never update anything to 46
    
        update abob_user.abob_tbl_load_losses 
        set load_status = 46
        where load_losses_k = rec.load_losses_k
        AND load_status in (1);  -- do not override other error code,        
    
        anReturn := -1;
    
        IF sql%rowcount >  1 THEN
            raise_application_error(-20101,'too many rows for error 46');
        END IF;        
    ELSE -- rev gig exists.  Make sure lossyears and losses exist.
        select count(*)
        into nCnt
        from 
            abob_user.abob_tbl_loss_years ly
        where 
            ly.rev_gig_k = nExistingRevGigK and  
            ly.acct_yr = nCurrentYear;

        -- insert into losses is triggered by this insert
        IF nCnt = 0 THEN
            insert into abob_user.abob_tbl_loss_years(  
                lacctyr_k,
                acct_yr,
                rev_gig_k)
            values (
                abob_user.losses_seq_lacctyr_k.nextval,
                nCurrentYear,
                nExistingRevGigK);
        END IF;
    END IF; -- lossgig exists
END LOOP; -- lossgigs in batch


-----------------------------------------------------------
-- if any failed set bcontinue to false
IF anReturn < 0 THEN
    bContinue := FALSE;
ELSE
    bContinue := TRUE;   
END IF;        

commit;


EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20101, 'validate_data '|| SQLERRM);
    
End; --validate_data

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


procedure get_losses_k (anLoadBatchK IN ABOB_USER.abob_tbl_load_batch.load_batch_k%type) IS

-- update losses_k in the upload table
-- YY 9/2/2015 with introduction of Inter Side, need to do this different, as we would need to insert a second row on any 
-- that has both A and C
nCnt number;

uCnt number;

v_prior_lld_k ABOB_USER.ABOB_TBL_LOAD_LOSSES_detail.LOAD_LOSSES_DETAIL_K%type
;
c_limit pls_integer := 100;

type lld_compare_rt is record
(load_losses_detail_k  ABOB_USER.ABOB_TBL_LOAD_LOSSES_detail.LOAD_LOSSES_DETAIL_K%type,
 losses_k  ABOB_USER.abob_tbl_losses.losses_k%type,
 inter_side   ABOB_USER.abob_tbl_losses.inter_side%type
);

type tbl_lld_compare is table of lld_compare_rt index by pls_integer;

lst_lld_compare tbl_lld_compare;

type tbl_lld is table of ABOB_USER.ABOB_TBL_LOAD_LOSSES_detail.LOAD_LOSSES_DETAIL_K%type index by pls_integer
;
lst_update_lld tbl_lld
;
lst_add_lld tbl_lld
;

type tbl_losses_k is table of ABOB_USER.ABOB_TBL_LOSSES.losses_k%type index by pls_integer
;
lst_update_losses_k tbl_losses_k
;
lst_add_losses_k tbl_losses_k
;

cursor cur_ll_compare is
    select 
     U.LOAD_LOSSES_DETAIL_K
    ,l.losses_k
    ,L.INTER_SIDE
    from 
        abob_user.abob_tbl_load_losses ll,
        abob_user.abob_tbl_lossgig lg,
        abob_user.abob_tbl_loss_years ly,
        abob_user.abob_tbl_losses l,
        ABOB_USER.ABOB_TBL_LOAD_LOSSES_detail u
    where
        u.load_losses_k = ll.load_losses_k and
        lg.rev_gig_k = ly.rev_gig_k and
        ly.lacctyr_k = l.lacctyr_k and
        u.corp_gig_k = lg.gig_k and
        l.deal_currency = 'T' and
        ll.accident_year = lg.accident_year and 
        ll.acct_year = ly.acct_yr and
        ll.acct_month = l.month and 
        ll.currency_desc_k = l.currency_desc_k
        and U.LOAD_BATCH_K = anLoadBatchK
        and LL.LOAD_BATCH_K = anLoadBatchK
    order by load_losses_detail_k, inter_side, losses_k
;

BEGIN 

spc_debug('Start get losses k');

select count(*)
into nCnt
from abob_user.abob_Tbl_load_losses_detail
where load_batch_k = anLoadBatchK;

v_prior_lld_k := 0
;
spc_debug('There are '||nCnt||' rows to update');

open cur_ll_compare
;
loop

--spc_debug('Start fetching');

    fetch cur_ll_compare
    bulk collect into
        lst_lld_compare
    limit c_limit
    ;
    exit when lst_lld_compare.count = 0
    ;
--spc_debug('Fetch '||lst_lld_compare.count||' rows so far');
       
    for indx in 1 .. lst_lld_compare.count
    loop
        if v_prior_lld_k = 0 or lst_lld_compare(indx).LOAD_LOSSES_DETAIL_K <> v_prior_lld_k then
            -- different load_losses_detail record, do update
            lst_update_lld(lst_update_lld.count + 1) := lst_lld_compare(indx).LOAD_LOSSES_DETAIL_K;
            lst_update_losses_k(lst_update_losses_k.count + 1) := lst_lld_compare(indx).losses_k;            
        else
            -- same load_losses_detail record, but map to different inter_side, need to insert
            lst_add_lld(lst_add_lld.count + 1) := lst_lld_compare(indx).LOAD_LOSSES_DETAIL_K;
            lst_add_losses_k(lst_add_losses_k.count + 1) := lst_lld_compare(indx).losses_k;
        end if;  -- check for inter side
         
        v_prior_lld_k := lst_lld_compare(indx).LOAD_LOSSES_DETAIL_K;
        
    end loop; -- loop through 100 fetch
         
end loop;  -- loop through cursor

uCnt := lst_update_lld.count;

spc_debug('Updating '||lst_update_lld.count||' rows');

forall indx in 1 .. lst_update_lld.count
    update ABOB_USER.abob_tbl_load_losses_detail u
    set losses_k = lst_update_losses_k(indx)
    where load_batch_k = anLoadBatchK
    and load_losses_detail_k = lst_update_lld(indx)
;
spc_debug('There are '||lst_add_lld.count||' rows to insert');
forall indx in 1 .. lst_add_lld.count
    insert into ABOB_USER.abob_tbl_load_losses_detail
    ( LOAD_LOSSES_K
    , LOAD_LOSSES_DETAIL_K    
    , CORP_GIG_K
    , LOSSES_K
    ,PCT_REINS, LOSS_POS, 
       PCT_REINS_OVERRIDE, PAID_STAT, RECOVERED_STAT, 
       LAE_PAID_STAT, LAE_RECOVERED_STAT, CASE_STAT, 
       IBNR_STAT, LAE_CASE_STAT, LAE_SALVAGE_STAT, 
       RECOVERED_GAAP, PAID_GAAP, LAE_PAID_GAAP, 
       LAE_RECOVERED_GAAP, CASE_GAAP, SALVAGE_GAAP, 
       IBNR_GAAP, LAE_CASE_GAAP, LAE_SALVAGE_GAAP, 
       SALVAGE_STAT, LOAD_BATCH_K, LOAD_STATUS, 
       MODIFIED_BY_USER, DATE_MODIFIED
       --, WRAP_BOND_PURCHASE, WRAP_BOND_INTEREST
       , LOSS_MIT_PURCHASE, LOSS_MIT_INTEREST
       , TSC_PAID, OR_OTHER_INCOME
       ,OR_OTHER_INCOME_STAT
       , OR_CONTRA_BAL_PAID
--       , OR_CONTRA_BAL_WRAPPED, 
       , OR_CONTRA_BAL_LOSS_MIT
       , OR_CONTRA_PL_PAID
--       , OR_CONTRA_PL_WRAPPED
       , OR_CONTRA_PL_LOSS_MIT
       , OR_CASE, 
       OR_SALVAGE_PAID
--       , OR_SALVAGE_WRAPPED
       , OR_SALVAGE_LOSS_MIT
       , OR_LAE, 
       OR_LAE_SALVAGE, OR_CONTRA_RECLASS_SALV_PAID
--       , OR_CONTRA_RECLASS_SALV_WRAPPED
       , OR_CONTRA_RECLASS_SAL_LOSS_MIT
       ,stat_undiscounted_loss_res
       ,stat_undiscounted_salv_res
    )               
    SELECT 
      LOAD_LOSSES_K
    , abob_user.abob_seq_load_losses_detail.nextval  LOAD_LOSSES_DETAIL_K    
    , CORP_GIG_K
    , lst_add_losses_k(indx)  losses_k
    , PCT_REINS, LOSS_POS, 
       PCT_REINS_OVERRIDE, PAID_STAT, RECOVERED_STAT, 
       LAE_PAID_STAT, LAE_RECOVERED_STAT, CASE_STAT, 
       IBNR_STAT, LAE_CASE_STAT, LAE_SALVAGE_STAT, 
       RECOVERED_GAAP, PAID_GAAP, LAE_PAID_GAAP, 
       LAE_RECOVERED_GAAP, CASE_GAAP, SALVAGE_GAAP, 
       IBNR_GAAP, LAE_CASE_GAAP, LAE_SALVAGE_GAAP, 
       SALVAGE_STAT, LOAD_BATCH_K, LOAD_STATUS, 
       MODIFIED_BY_USER, DATE_MODIFIED
       --, WRAP_BOND_PURCHASE, WRAP_BOND_INTEREST
       , LOSS_MIT_PURCHASE, LOSS_MIT_INTEREST
       , TSC_PAID, OR_OTHER_INCOME
       ,OR_OTHER_INCOME_STAT
       , OR_CONTRA_BAL_PAID
--       , OR_CONTRA_BAL_WRAPPED, 
       , OR_CONTRA_BAL_LOSS_MIT
       , OR_CONTRA_PL_PAID
--       , OR_CONTRA_PL_WRAPPED
       , OR_CONTRA_PL_LOSS_MIT
       , OR_CASE, 
       OR_SALVAGE_PAID
--       , OR_SALVAGE_WRAPPED
       , OR_SALVAGE_LOSS_MIT
       , OR_LAE, 
       OR_LAE_SALVAGE, OR_CONTRA_RECLASS_SALV_PAID
--       , OR_CONTRA_RECLASS_SALV_WRAPPED
       , OR_CONTRA_RECLASS_SAL_LOSS_MIT    
       ,stat_undiscounted_loss_res
       ,stat_undiscounted_salv_res   
    FROM ABOB_USER.ABOB_TBL_LOAD_LOSSES_DETAIL    
    where load_batch_k = anLoadBatchK
    and load_losses_detail_k = lst_add_lld(indx)
    ;

IF uCnt <> nCnt THEN
    bContinue := false;
    sError := 'rowcount in losses_k';
END IF;    


select count(*) 
into nCnt
from abob_user.abob_tbl_load_losses_detail
where 
    load_batch_k = anLoadBatchK and 
    losses_k is null; 

IF nCnt > 0 THEN
    bContinue := FALSE;
    sError := 'there are null losses_k';
END IF;    

spc_debug('Done get losses k');

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20104, 'get_losses_k '|| SQLERRM);

End; --get_loss_k

procedure populate_abob (anLoadBatchK IN abob_tbl_load_batch.load_batch_k%type) IS
 
-- update abob loss table with data from the upload table
-- if the upload table value is null then we want to keep the value in the losses table.
-- users don't have to enter all categories.  nulls mean don't change the value.  it does not mean zero.   
-- YY 8/27/2015 add columns from Contra project 

BEGIN 


UPDATE abob_user.abob_Tbl_losses u
SET (
    u.losses_sap_paid, 
    u.losses_sap_recovered, 
    u.losses_gap_paid, 
    u.losses_gap_recovered, 
    u.lae_sap_paid, 
    u.lae_sap_recovered, 
    u.lae_gap_paid, 
    u.lae_gap_recovered, 
    u.r_sap_gross, 
    u.r_sap_salvage, 
    u.r_sap_ibnr, 
    u.r_sap_lae_gross, 
    u.r_gap_gross, 
    u.r_gap_salvage, 
    u.r_gap_ibnr, 
    u.r_gap_lae_gross, 
    u.r_sap_lae_salvage_gross, 
    u.r_gap_lae_salvage_gross,
-- new columns from Contra project
--    u.WRAP_BOND_PURCHASE  ,
    u.LOSS_MIT_PURCHASE  ,
--    u.WRAP_BOND_INTEREST  ,
    u.LOSS_MIT_INTEREST  ,
    u.TSC_PAID  ,
    u.OR_OTHER_INCOME  ,
    u.OR_OTHER_INCOME_STAT  ,
    u.OR_CONTRA_BAL_PAID  ,
--    u.OR_CONTRA_BAL_WRAPPED  ,
    u.OR_CONTRA_BAL_LOSS_MIT  ,
    u.OR_CONTRA_PL_PAID  ,
--    u.OR_CONTRA_PL_WRAPPED  ,
    u.OR_CONTRA_PL_LOSS_MIT  ,
    u.OR_CASE  ,
    u.OR_SALVAGE_PAID  ,
--    u.OR_SALVAGE_WRAPPED  ,
    u.OR_SALVAGE_LOSS_MIT  ,
    u.OR_LAE  ,
    u.OR_LAE_SALVAGE  ,
    u.OR_CONTRA_RECLASS_SALV_PAID  ,
--    u.OR_CONTRA_RECLASS_SALV_WRAPPED    
    u.OR_CONTRA_RECLASS_SAL_LOSS_MIT,
    u.stat_undiscounted_loss_res,
    u.stat_undiscounted_salv_res
    ) = 
(SELECT 
    nvl(ld.Paid_stat,l.losses_sap_paid), 
    nvl(ld.Recovered_stat,l.losses_sap_recovered),
    nvl(ld.Paid_gaap, l.losses_gap_paid),
    nvl(ld.Recovered_gaap, l.losses_gap_recovered),
    nvl(ld.Lae_paid_stat,l.lae_sap_paid), 
    nvl(ld.Lae_recovered_stat, l.lae_sap_recovered),
    nvl(ld.Lae_paid_gaap, l.lae_gap_paid),
    nvl(ld.Lae_recovered_gaap, l.lae_gap_recovered),
    nvl(ld.case_stat, l.r_sap_gross),
    nvl(ld.salvage_stat, l.r_sap_salvage),
    nvl(ld.Ibnr_stat, l.r_sap_ibnr),
    nvl(ld.Lae_case_stat, l.r_sap_lae_gross),
    nvl(ld.Case_gaap, l.r_gap_gross),
    nvl(ld.Salvage_gaap, l.r_gap_salvage),
    nvl(ld.Ibnr_gaap, l.r_gap_ibnr),
    nvl(ld.Lae_case_gaap, l.r_gap_lae_gross),
    nvl(ld.Lae_salvage_stat, l.r_gap_lae_salvage_gross),
    nvl(ld.Lae_salvage_gaap, l.r_gap_lae_salvage_gross),
-- new columns from Contra project    
--    nvl(ld.WRAP_BOND_PURCHASE, l.WRAP_BOND_PURCHASE),
    nvl(ld.LOSS_MIT_PURCHASE, l.LOSS_MIT_PURCHASE),
--    nvl(ld.WRAP_BOND_INTEREST, l.WRAP_BOND_INTEREST),
    nvl(ld.LOSS_MIT_INTEREST, l.LOSS_MIT_INTEREST),
    nvl(ld.TSC_PAID, l.TSC_PAID),
-- for Override columns, keep the blank in the upload file    
    ld.OR_OTHER_INCOME,
    ld.OR_OTHER_INCOME_STAT  ,
    ld.OR_CONTRA_BAL_PAID,
--    nvl(ld.OR_CONTRA_BAL_WRAPPED, l.OR_CONTRA_BAL_WRAPPED)  ,
    ld.OR_CONTRA_BAL_LOSS_MIT,
    ld.OR_CONTRA_PL_PAID,
--    nvl(ld.OR_CONTRA_PL_WRAPPED, l.OR_CONTRA_PL_WRAPPED)  ,
    ld.OR_CONTRA_PL_LOSS_MIT,
    ld.OR_CASE,
    ld.OR_SALVAGE_PAID,
--    nvl(ld.OR_SALVAGE_WRAPPED, L.OR_SALVAGE_WRAPPED)  ,
    ld.OR_SALVAGE_LOSS_MIT,
    ld.OR_LAE,
    ld.OR_LAE_SALVAGE,
    ld.OR_CONTRA_RECLASS_SALV_PAID,
--    nvl(ld.OR_CONTRA_RECLASS_SALV_WRAPPED, L.OR_CONTRA_RECLASS_SALV_WRAPPED)      
    ld.OR_CONTRA_RECLASS_SAL_LOSS_MIT,
    nvl(ld.stat_undiscounted_loss_res, l.stat_undiscounted_loss_res),
    nvl(ld.stat_undiscounted_salv_res, l.stat_undiscounted_salv_res)
    FROM 
        abob_user.abob_tbl_load_losses_detail ld ,
        abob_user.abob_tbl_losses l
    WHERE
        u.losses_k = ld.losses_k AND
        ld.losses_k = l.losses_k and 
        ld.load_batch_k = anLoadBatchK)
WHERE
    u.losses_k in (SELECT ld.losses_k FROM abob_tbl_load_losses_detail ld WHERE ld.load_batch_k = anLoadBatchK);  
 
EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20105, 'update_abob '|| SQLERRM);
End; --populate_abob


procedure call_losses_calc (anLoadBatchK abob_tbl_load_batch.load_batch_k%type) IS

begin

ABOB_USER.ABOB_PKG_LOSS_CONTRA.Loss_recalc_for_upload(anLoadBatchK);

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20106, 'call_losses_calc '|| SQLERRM);



END; -- call_losses_calc


procedure update_load_status(anLoadBatchK abob_user.abob_tbl_load_batch.load_batch_k%type)IS

begin


update abob_user.abob_tbl_load_losses_detail 
set load_status = 99 
where load_batch_k = anLoadBatchK;

update abob_user.abob_tbl_load_losses 
set load_status = 99 
where load_batch_k = anLoadBatchK;

update abob_user.abob_tbl_load_batch
set 
    processed_by_user = user,
    date_processed = sysdate,
    load_batch_status = 'Complete'
where
    load_batch_k = anLoadBatchK;
commit;    

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20108, 'update_load_stats '|| SQLERRM);

end; 


procedure add_missing_lossgig
            (anPolicyNum abob_user.abob_tbl_corp_gig.policy_num%type
             ,asPolicySub abob_user.abob_tbl_corp_gig.policy_sub%type
             ,p_accident_year ABOB_USER.ABOB_TBL_LOSSGIG.ACCIDENT_YEAR%type default null
             ,p_checking_only   boolean
             ,p_result out number  
             ,p_msg out varchar     
              ) IS
-- YY per Contra loss project
-- rewrite this to be the general purpose procedure to add any missing lossgig record given a policy
-- the accident year is an optional input parameter
-- return the following code:
--  25 - if nothing needs to be added
-- 460 - we only added gig that is not in lossgig before
-- 461 - if we updated an existing gig with a new accident year (as part of loss upload, we conform to the accounting accident year)
-- 462 - when we were not given an accident_year, and we skip over lossgig record from accident year update
--       (this indicates we have single policy with multiple accident year)
-- 463 - when we were given an accident_year (such as part of loss upload), we encounter single gig with multiple accident year,
--      we need human intervention to merge the multiple accident year 

v_Cnt number;
nRevSrK number;
nPolicyK number;
nTrnsumK number;
v_accident_year ABOB_USER.ABOB_TBL_LOSSGIG.ACCIDENT_YEAR%type;
v_ay_case number;


cursor cur_missing
(c_anPolicyNum abob_user.abob_tbl_corp_gig.policy_num%type, c_asPolicySub abob_user.abob_tbl_corp_gig.policy_sub%type
,c_accident_year ABOB_USER.ABOB_TBL_LOSSGIG.ACCIDENT_YEAR%type
) IS
-- cartisian of gig and accident years that should exist
-- all gigs in gig table and all accident years in lossgig table
-- (YY - changed to use a given accident_year, which we would determine outside of the cursor, take off the FSA limit)
-- then minus the combos that exist in lossgig
select distinct 
 corp_gig_k
,c_accident_year accident_year 
from  
    (select distinct corp_gig_k 
        from 
            abob_user.abob_tbl_corp_gig g,
            abob_user.ABOB_TBL_DAS_REINS_STRUC_S rs
        where 
            g.policy_num = c_anPolicyNum and 
            nvl(rtrim(g.policy_sub),'null') = nvl(rtrim(c_asPolicySub),'null') and
            g.policy_num||trim(g.policy_sub) = rs."policy_num"||trim(rs."policy_sub")  
           and rs."gig_k" = g.corp_gig_k 
        and (    
                (origin_co > 100 and owner_co < 100)  -- for direct and external assumed, always populate
            or
            ((origin_co < 100 or owner_co < 100)            
                and NOT
            (abob_user.abob_fun_sql_date(rs."start_dt" )> dCurrentPeriodEnd or 
            --    (abob_user.abob_fun_sql_date(rs."stop_dt" ) is not null and abob_user.abob_fun_sql_date(rs."stop_dt" ) < dCurrentPeriodBeg) or 
            (nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_user.abob_fun_sql_date(rs."stop_dt" )) is not null and nvl(abob_user.abob_fun_sql_date(rs."terminate_dt" ),abob_fun_sql_date("stop_dt")) < dCurrentPeriodBeg))
            ) -- for cessions, limit to active only
        )
     union  -- this union should include inactive streams that have loss record in the current or future periods
     select distinct cg.corp_gig_k
     from
      abob_user.abob_tbl_corp_gig cg
     ,abob_user.abob_tbl_lossgig lg
     ,abob_user.abob_tbl_loss_years ly
     ,abob_user.abob_tbl_losses l    
     where CG.CORP_GIG_K = LG.GIG_K
     and cg.policy_num = c_anPolicyNum
     and nvl(rtrim(cg.policy_sub),'null') = nvl(rtrim(c_asPolicySub),'null')     
     and LG.REV_GIG_K = LY.REV_GIG_K
     and LY.LACCTYR_K = L.LACCTYR_K
     and ((LY.ACCT_YR = nCurrentYear and L.MONTH >= nCurrentMonth)
           or ly.acct_yr > nCurrentYear)       
            )   
minus
-- gig accident year combos that exist
select lg.gig_k, lg.accident_year
    from 
        abob_user.abob_tbl_corp_gig g,
        abob_user.abob_tbl_lossgig lg
    where
        g.policy_num = c_anPolicyNum and 
        nvl(rtrim(g.policy_sub),'null') = nvl(rtrim(c_asPolicySub),'null') and
        g.corp_gig_k = lg.gig_k
order by corp_gig_k, accident_year;

type tbl_cur_missing is table of cur_missing%rowtype index by pls_integer;

lst_cur_missing tbl_cur_missing;

type tbl_gig_k is table of ABOB_TBL_CORP_GIG.CORP_GIG_K%type index by pls_integer;

lst_new_lossgig tbl_gig_k;
lst_update_lossgig tbl_gig_k;
lst_error_lossgig tbl_gig_k;

c_limit pls_integer := 100;

-- 12/09/15 AJH copied from upr_for_losses
CURSOR cur_max_accident_year(
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
    ly.acct_yr = nCurrentYear and 
    l.month >= nCurrentMonth and    
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

CURSOR cur_max_accident_year_noAmt(
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
    ly.acct_yr = nCurrentYear and 
    l.month >= nCurrentMonth and    
    l.lacctyr_k = ly.lacctyr_k and   
    l.currency_desc_k = a_currency_k;
        
begin

--spc_debug('Start checking missing lossgig for '||anPolicyNum||asPolicySub);

p_result := 25;
     
if nCurrentYear is null then  -- in case this procedure is called outside of loss upload process
    initialize_package;
end if;

if p_accident_year is null then
    v_accident_year := 0;
    v_ay_case := 0;
    
-- if accident year is not provided, then determine using the following
-- first try to find the max accident year with some loss/contra amount
    open cur_max_accident_year(anPolicyNum||rtrim(asPolicySub), 10000038);
    fetch cur_max_accident_year into v_accident_year;
    close cur_max_accident_year;
    
    if nvl(v_accident_year,0) = 0 then
-- if there is none, expand to max of anything    
        open cur_max_accident_year_noAmt(anPolicyNum||rtrim(asPolicySub), 10000038);
        fetch cur_max_accident_year_noAmt into v_accident_year;
        close cur_max_accident_year_noAmt;
    else
        v_ay_case := 2;  -- 2 is using maximum of exising accident year with amount
    end if;    
    
    if nvl(v_accident_year,0) = 0 then
-- if there is still none, then default to current year    
        v_accident_year :=nCurrentYear;  -- if the policy is indeed brand new to loss system, then use current accounting year as accident year
        v_ay_case := 4; -- 4 is using current accounting year
    else
        if nvl(v_ay_case,0) = 0 then
            v_ay_case := 3;  -- 3 is using maximum of existing accident year with 0 amount    
        end if; 
    end if;    

else
    v_accident_year := p_accident_year; -- use provided one if available, usually the case when calling during excel loss upload
    v_ay_case := 1; -- 1 is using a given accident year
end if;   -- if p_accident_year is blank

open cur_missing(anPolicyNum, asPolicySub, v_accident_year);

loop
    fetch cur_missing 
    bulk collect into lst_cur_missing
    limit c_limit;
    
    exit when lst_cur_missing.count = 0;
    
--spc_debug('There are missing lossgig for '||anPolicyNum||asPolicySub||' - '||lst_cur_missing.count||' rows');
    
    for indx in 1..lst_cur_missing.count
    loop
    
    -- first test if we already have a lossgig record for this gig, but in a different accident year
    -- be awared that we could have multiple accident years due to historical data quality issue
    begin
        select count(distinct lg.accident_year), max(lg.accident_year)
        into v_Cnt, p_msg
        from abob_user.abob_tbl_lossgig lg
        where gig_k = lst_cur_missing(indx).corp_gig_k;
    exception when no_data_found then
        v_Cnt := 0;
    end;     
--spc_debug('Processing missing lossgig for '||lst_cur_missing(indx).corp_gig_k||' count is '||v_Cnt);

    case
        when v_Cnt = 0 then               
            -- we don't have this gig at all, safe to add the gig/accident year combination
            
            lst_new_lossgig(lst_new_lossgig.count + 1) := lst_cur_missing(indx).corp_gig_k;
            if p_result <= 460 then 
                p_result := greatest(p_result,460);            
                p_msg := 'New Lossgig(s) needed';
            end if;            
                              
        when v_Cnt = 1 then
            -- we have gigs already, but they are for a different, single accident year, two possibilities
            -- first, if accounting specify the accident year, such as when calling this procedure with the accident year parameter 
            -- then per accounting, the rule is to interpret this as instruction to UPDATE the existing accident year to new value
            if v_ay_case = 1 then
                lst_update_lossgig(lst_update_lossgig.count + 1) := lst_cur_missing(indx).corp_gig_k;
                if p_result <= 461 then 
                p_result := greatest(p_result,461);
                p_msg := 'Updating accident year from '||p_msg||' to '||v_accident_year;
                end if;
            else
            -- otherwise, if the accident year is not specified, but derived using the MAX logic, then don't update the existing
            -- just skip this gig-accident year combo
                if p_result <= 25 then 
                p_result := greatest(p_result,25);
                p_msg := null;
                end if;
            end if;                   
        else
            -- we are in the case of already having 1 gig - multiple accident year
            if v_ay_case = 1 then
                lst_error_lossgig(lst_error_lossgig.count + 1) := lst_cur_missing(indx).corp_gig_k;
                if p_result <= 463 then 
                p_result := greatest(p_result,463);
                p_msg := 'There are '||v_Cnt||' accident years in the system for corp gig k - '||lst_cur_missing(indx).corp_gig_k;
                        -- the only serious case, user specifies the accident year, but we cannot update because that
                        -- would result in multiple records of same gig - same accident year combination 
                        -- need more human intervention to properly merge the exising records 
                end if;
            else
                if p_result <= 462 then 
                p_result := greatest(p_result,462);  -- if the accident year is not specified, but derived, then skip the combo
                p_msg := 'Detected multiple accident years for corp_gig_k '||lst_cur_missing(indx).corp_gig_k;
                end if;
            end if;
    
    end case; -- check if the gig has existing record with different accident year    
    
    end loop; -- loop through 100 records
    
end loop; -- loop through cur_missing

close cur_missing;
-- commit;  -- YES commit, have to commit to clear the connection to das_reins_struc

--spc_debug('starting add missing lossgig for '||anPolicyNum||asPolicySub||' - '||lst_new_lossgig.count||' rows');

if p_checking_only = false then
-- not just checking, so do the inserts/updates    
if lst_new_lossgig.count > 0 then
    -- first figure out the rev_sr_k, policy_k and trnsum_k
    begin
        -- keeping it simple, use existing rev_sr_k, policy_k, trnsum_k if available
        -- if there are multiple possiblities, just arbitarily pick 1 (the one associated with the latest rev_sr_k)
        -- then successively the one accociated with the latest policy_k
        select 
            max(lg.rev_sr_k)
        into
            nRevSrK
        from abob_user.abob_tbl_corp_gig g, abob_user.abob_tbl_lossgig lg, gbl_user.gbl_tbl_client cliori, gbl_user.gbl_tbl_client cliown 
        where 
            g.policy_num = anPolicyNum and 
            nvl(rtrim(g.policy_sub),'null') = nvl(rtrim(asPolicySub),'null') and
            g.corp_gig_k = lg.gig_k and 
            g.origin_co = cliori.client_cod and
            g.owner_co = cliown.client_cod and
            (origin_co < 100 or owner_co < 100)
        ;
        select 
            max(policy_k)
        into
            nPolicyK 
        from abob_user.abob_tbl_corp_gig g, abob_user.abob_tbl_lossgig lg, gbl_user.gbl_tbl_client cliori, gbl_user.gbl_tbl_client cliown 
        where 
            g.policy_num = anPolicyNum and 
            nvl(rtrim(g.policy_sub),'null') = nvl(rtrim(asPolicySub),'null') and
            g.corp_gig_k = lg.gig_k and 
            g.origin_co = cliori.client_cod and
            g.owner_co = cliown.client_cod and
            (origin_co < 100 or owner_co < 100)
            and LG.REV_SR_K = nRevSrK
        ;        
        select 
            max(trnsum_k)
        into
            nTrnsumK 
        from abob_user.abob_tbl_corp_gig g, abob_user.abob_tbl_lossgig lg, gbl_user.gbl_tbl_client cliori, gbl_user.gbl_tbl_client cliown 
        where 
            g.policy_num = anPolicyNum and 
            nvl(rtrim(g.policy_sub),'null') = nvl(rtrim(asPolicySub),'null') and
            g.corp_gig_k = lg.gig_k and 
            g.origin_co = cliori.client_cod and
            g.owner_co = cliown.client_cod and
            (origin_co < 100 or owner_co < 100)
            and LG.REV_SR_K = nRevSrK
            and LG.POLICY_K = nPolicyK
        ;             
        --spc_debug('found '||nRevSrK||' '||nPolicyK||' '||nTrnsumK);
    exception when no_data_found then
        --spc_debug('no RevSrK or PolicyK or TrnsumK; calling PFM to create');
        CREATE_PFM_RECORD(anPolicyNum, asPolicySub, nRevSrK, nPolicyk, nTrnsumK);
    end;

    if nRevSrK is null or nPolicyK is null or nTrnsumK is null then
        --spc_debug('no RevSrK or PolicyK or TrnsumK; calling PFM to create');
        CREATE_PFM_RECORD(anPolicyNum, asPolicySub, nRevSrK, nPolicyk, nTrnsumK);
    end if;

    forall indx in 1..lst_new_lossgig.count
        insert into abob_user.abob_tbl_lossgig
        (rev_gig_k, rev_sr_k, gig_k, accident_year, policy_k, trnsum_k)
        values
        (abob_user.losses_seq_rev_gig_k.NEXTVAL, nRevSrK, lst_new_lossgig(indx), v_accident_year, nPolicyK, nTrnsumK)
        ;
    
    forall indx in 1..lst_new_lossgig.count
        INSERT INTO abob_user.ABOB_TBL_LOSS_YEARS
       (lacctyr_k, acct_yr, rev_gig_k)
       select
        abob_user.losses_seq_lacctyr_k.NEXTVAL
       ,nCurrentYear
       ,LG.REV_GIG_K
       from abob_user.abob_tbl_lossgig lg
       where LG.GIG_K = lst_new_lossgig(indx)
       and LG.ACCIDENT_YEAR = v_accident_year
       and LG.REV_SR_K = nRevSrK
       and LG.POLICY_K = nPolicyK
       and LG.TRNSUM_K = nTrnsumK
       ;       

end if; -- if there are new lossgig to be added

--spc_debug('starting update lossgig to new accident year '||anPolicyNum||asPolicySub||' - '||lst_update_lossgig.count||' rows');

if lst_update_lossgig.count > 0 then
    
    forall indx in 1 .. lst_update_lossgig.count
        update abob_user.abob_tbl_lossgig lg set
                    lg.accident_year = v_accident_year
                where lg.gig_k = lst_update_lossgig(indx)
                ;

end if; -- if there are lossgig that need accident year update 

end if; -- if checking only = false

--spc_debug('End checking missing lossgig for '||anPolicyNum||asPolicySub);

end;  -- end add_missing_loss_gig

PROCEDURE validate_data(anLoadBatchK IN abob_tbl_load_batch.load_batch_k%type, anReturn out number) IS 
-- validate user spreadsheet. If it passes populate the detail table with reinsurance pct and pushdown
lnReturn number;

BEGIN

initialize_package;

validate_user_input(anLoadBatchK, anReturn);

update_loss_layer(anLoadBatchK, anReturn);
   
IF bContinue THEN
    create_rein_detail(anLoadBatchK, lnReturn); 
else
    spc_debug('pkg_losses_upload.validate_date - bContinue is false');
--    RAISE_APPLICATION_ERROR(-20112, 'validate_data - bContinue is false');    
END IF;


EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20112, 'validate_data '|| SQLERRM);

END;

PROCEDURE create_rein_detail(anLoadBatchK IN abob_tbl_load_batch.load_batch_k%type, anReturn out number) IS 
-- populate the detail table with rms pcts and pushdown to reinsurance
--lnReturn number;

BEGIN

initialize_package;

spc_debug('starting populate_from_rein_struct');
IF bcontinue THEN populate_from_rein_struct(anLoadBatchK); END IF;
spc_debug('starting get_losses_k');
IF bcontinue THEN get_losses_k(anLoadBatchK); END IF;
-- populate loss layer flag

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20112, 'create_rein_detail '|| SQLERRM);
END;


PROCEDURE run_upload(anLoadBatchK IN abob_tbl_load_batch.load_batch_k%type, anReturn out number) IS 
-- upload data into ABOB
lnReturn number;

BEGIN

spc_debug('starting abob_pkg_losses_upload.run_upload');
bContinue := TRUE;

initialize_package;

-- revalidate user template.  If it passes it will call create_rein_detail
spc_debug('starting validate_user_input');
IF bcontinue THEN validate_user_input(anLoadBatchK, lnReturn); END IF;
spc_debug('starting populate_abob');
IF bcontinue THEN populate_abob(anLoadBatchK); END IF;
--spc_debug('starting call_losses_calc');
--IF bcontinue THEN call_losses_calc(anLoadBatchK); END IF;

spc_debug('starting update_load_status');
IF bcontinue THEN update_load_status(anLoadBatchK); END IF;


-- act on results of program
IF bContinue THEN
    -- sucess
    commit;
     anReturn := 0;        
ELSE
    -- failure
    delete from abob_tbl_load_losses_detail where load_batch_k = anLoadBatchK;
    commit;
    spc_debug('failed in main program.  '||sError);
    anReturn := -1;

END IF;        

EXCEPTION
 WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20110, 'run_upload '|| SQLERRM);

End; --run-Upload
-----------

PROCEDURE CREATE_PFM_RECORD(P_POLICY_NUM ABOB_USER.ABOB_TBL_CORP_GIG.POLICY_NUM%TYPE
                            ,P_POLICY_SUB ABOB_USER.ABOB_TBL_CORP_GIG.POLICY_SUB%TYPE
                            ,P_REV_SR_K OUT ABOB_USER.ABOB_TBL_LOSSGIG.REV_SR_K%TYPE
                            ,P_POLICY_K OUT ABOB_USER.ABOB_TBL_LOSSGIG.POLICY_K%TYPE
                            ,P_TRNSUM_K OUT ABOB_USER.ABOB_TBL_LOSSGIG.TRNSUM_K%TYPE                            
                            ) IS

nPolicyK NUMBER; 
nRevSrK NUMBER; 
nPolicyNum NUMBER; 
sPolicySub VARCHAR2(5); 
dClosedDate DATE; 
sPolicyAbbr VARCHAR2(50); 
dMaturityDate DATE; 
sPremType CHAR(1);        
v_origin_co number;
v_client_k gbl_user.gbl_tbl_client.client_k%type;
v_client_d GBL_USER.GBL_TBL_CLIENT.CLIENT_D%type;

cursor cur_policy_k (anPolicyNum number, asPolicySub varchar, anOriginCo number) is
select policy_k
from pfm_user.pfm_tbl_policy
where 
    policy_num =  anPolicyNum || rtrim(asPolicySub) and
    client_cod = anOriginCo;    

BEGIN
    P_TRNSUM_K := 0;  -- per Valda, using 0 going forward

-- policy_k
    begin
    
    select DISTINCT
        g.origin_co, 
        cl.client_k, 
        cl.client_d
    into
        v_origin_co, v_client_k, v_client_d
    from 
    abob_user.abob_tbl_corp_gig g,  
    gbl_user.gbl_tbl_client cl  
    where 
    g.policy_num = p_policy_num 
    and nvl(rtrim(g.policy_sub),' ') = nvl(rtrim(p_policy_sub),' ')
    and g.origin_co = cl.client_cod
    and (G.ORIGIN_CO > 100 and G.OWNER_CO < 100)
    ;

    -- following will fail without this being run first
    select max("policy_num") into nClear from abob_user.das_reins_struc_s where "policy_num" = 13;    
    
    SELECT
        "policy_num", 
        RTRIM("policy_sub") policy_sub ,  
        abob_fun_sql_date("closed_dt") , 
        substr("policy_abbr",1,50) policy_abbr, 
        abob_fun_sql_date("mat_dt"), 
        trim("prem_type") 
    INTO    
        nPolicyNum, 
        sPolicySub, 
        dClosedDate, 
        sPolicyAbbr, 
        dMaturityDate, 
        sPremType 
    FROM abob_user.das_policy_s 
    WHERE 
        "policy_num" = p_policy_num 
        AND NVL(RTRIM("policy_sub"),' ') = nvl(rtrim(p_policy_sub), ' ')
    ;  
    
    exception
        when no_data_found then RAISE_APPLICATION_ERROR(-20200, 'create PFM policy - no policy found '|| SQLERRM);
        when too_many_rows then RAISE_APPLICATION_ERROR(-20200, 'create PFM policy - more than 1 policy found '|| SQLERRM);
    end;

    nPolicyK := 0; 
    
    open  cur_policy_k(nPolicyNum, sPolicySub, v_origin_co) ;
    fetch cur_policy_k into nPolicyK;
    close cur_policy_k;
     
    IF nPolicyK is null or nPolicyK = 0 THEN -- policy doesnt extist

        --abob_user.spc_debug('it doesnt exist '||npolicyk);    

        SELECT pfm_user.pfm_seq_policy.NEXTVAL 
        INTO nPolicyK 
        FROM dual;        
        
        INSERT INTO pfm_user.PFM_TBL_POLICY 
            (POLICY_K ,
            POLICY_NUM, 
            CLIENT_K, 
            CLIENT_D, 
            POLICY_DAT, 
            POL_TYPE,
            CLIENT_COD, 
            MATURITY_DATE, 
            ISSUE_FULL_NAME,
            LEGAL_NAME, 
            ISSUER_NAME, 
            ORIG_FX_RATE,
            STRUCTURE_TYPE)      
            -- REV_NO, SP_CAP_CHARGE, DATED_DATE, POL_PAR, 
            -- PREMIUM_FREQ, ORIGINAL_EXP_AMT, 
            -- SP_CAP_CHARGE_BASIS, MULTI_CURRENCY_YN 
            VALUES 
                (nPolicyK, 
                nPolicyNum || rtrim(sPolicySub), 
                v_client_k,
                v_client_d, 
                dClosedDate, 
                sPremType,  
                v_origin_co, 
                dMaturityDate, 
                sPolicyAbbr, 
                sPolicyAbbr,  
                SUBSTR(sPolicyAbbr,1,50), 1, 'T'); 
     END IF;  -- policy_num already exists   
     
   p_policy_k := nPolicyK;
    
    -- insert into pfm revenue source table 
    -- 
    
    nRevSrK := 0; 
    
    select min(rev_sr_k)
    into nRevSrK 
    from pfm_user.pfm_tbl_rev_sr
    where  
        rev_sr_d =   p_policy_num || ' ' || substr(sPolicyAbbr, 1, 15 - length(p_policy_num) - 1);         
    
    IF nRevSrK is null or nRevSrK = 0 THEN -- rev_sr doesnt exist
            
        SELECT pfm_user.pfm_seq_rev_sr.NEXTVAL 
        INTO nRevSrK  
        FROM dual; 

        -- for lack of a better automated way to get a unique value for REV_SR_D, this populates the column by putting 
        -- the policy number first and then as many characters as fit from the policy_abbr value for the remainder. It's  
        -- not the best code - if accounting wants, they can give us codes in the upload spreadsheet to populate from. 

        INSERT INTO pfm_user.PFM_TBL_REV_SR 
            (rev_sr_k, 
            rev_sr_d, 
            name_revs1, 
            naic_id, 
            country, 
            sp_rate_adj_cc, 
            employee_id, 
            losses_yn) 
            -- state, bond_type, revenue_type, rev_sr_aggr_k, super_senior_yn, bond_type_mdy, cap_charge 
            values (nRevSrK, 
               p_policy_num || ' ' || substr(sPolicyAbbr, 1, 15 - length(p_policy_num) - 1),   
               UPPER(sPolicyAbbr), 
               'MUNI', 
               'USA', 
               0, 
               999999, 
               'Y');   
               -- , state, bond_type, revenue_type, NULL, NULL, NULL, cap_charge 
    END IF; -- rev sr already exists
    
    p_rev_sr_k := nRevSrK;
                    
END; -- create_pfm_record
                            
End;
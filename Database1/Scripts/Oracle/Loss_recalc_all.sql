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
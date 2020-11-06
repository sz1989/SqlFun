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
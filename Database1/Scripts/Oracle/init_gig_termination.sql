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
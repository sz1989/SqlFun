create or replace PACKAGE           ABOB_PKG_LOSS_CONTRA AS
/******************************************************************************
   NAME:       ABOB_PKG_LOSS_CONTRA
   PURPOSE:    Contain procedues to calculate the GAAP Reserve and Contra values

   REVISIONS:
   Ver        Date        Author           Description
   ---------  ----------  ---------------  ------------------------------------
   1.0        8/21/2015      yyang       1. Created this package.
   1.1       10/14/2015     YYANG       2. Changes due to QA and UAT feedbacks
   1.2      10/29/2015      yyang       3. Add the incurred benefit concept
   1.3      3/29/2016       yyang       3. Rewrite the other income calculation
   1.4      3/28/2017       yyang       Add handling of newly created loss record properly in ABOB_SPC_LOSSES_CALC
******************************************************************************/
g_acct_year abob_user.ABOB_TBL_SEGMENT.acct_yr%TYPE;
g_acct_month abob_user.abob_tbl_losses.month%TYPE;

losses_row abob_user.abob_tbl_losses%rowtype;

type tbl_losses_rec is table of abob_user.abob_tbl_losses%rowtype index by pls_integer;

batch_list_losses_rec tbl_losses_rec;

type tbl_losses_k is table of abob_user.abob_tbl_losses.losses_k%type index by pls_integer;

batch_list_losses_key tbl_losses_k;

type gig_term_date_rt is record
(gig_k  ABOB_USER.ABOB_TBL_CORP_GIG.CORP_GIG_K%type,
 terminate_dt  date,
 stop_dt date,
 start_dt date,
 origin_co ABOB_USER.ABOB_TBL_CORP_GIG.ORIGIN_CO%type,
 owner_co ABOB_USER.ABOB_TBL_CORP_GIG.OWNER_CO%type
);

type tbl_gig_term_date is table of gig_term_date_rt index by pls_integer;

lst_gig_term_date tbl_gig_term_date;
  
  PROCEDURE Contra_Loss_Calc_Monthly(p_losses_k IN abob_tbl_losses.losses_k%type, p_prev_losses_k IN abob_tbl_losses.losses_k%type,
                                        p_mtm boolean, p_refi boolean
                                        ,p_batch_mode boolean default false);
  PROCEDURE Contra_Loss_Calc_Quarterly(p_losses_k IN abob_tbl_losses.losses_k%type, p_prev_losses_k IN abob_tbl_losses.losses_k%type,
                                         p_mtm boolean, p_refi boolean
                                         ,p_batch_mode boolean default false);
  PROCEDURE Contra_Loss_Calc(p_losses_k IN abob_tbl_losses.losses_k%type, p_prev_losses_k IN abob_tbl_losses.losses_k%type,
                             p_mtm boolean, p_refi boolean, p_terminated boolean
                             ,p_rev_gig_k abob_user.abob_tbl_lossgig.rev_gig_k%type
                            , p_acct_year IN abob_tbl_loss_years.acct_yr%type
                            , p_acct_month      IN abob_tbl_losses.month%type
                                         ,p_batch_mode boolean default false);
PROCEDURE ABOB_SPC_LOSSES_CALC (
    a_rev_gig_k IN abob_tbl_lossgig.rev_gig_k%type,
    a_year IN abob_tbl_loss_years.acct_yr%type,
    a_month      IN abob_tbl_losses.month%type,
    a_currency  IN abob_tbl_losses.currency_desc_k%type,
    p_batch_mode boolean default false);
    
  procedure Loss_recalc_policy(
        p_policy_num IN abob_user.abob_tbl_corp_gig.policy_num%TYPE,
        p_policy_sub IN abob_user.abob_tbl_corp_gig.policy_sub%TYPE,
        p_batch_mode boolean default false,
        p_acct_year IN abob_tbl_loss_years.acct_yr%type,
        p_acct_month      IN abob_tbl_losses.month%type
        );
        
  procedure Loss_recalc_all(p_acct_year number default null, p_acct_month number default null);  
  
  procedure Loss_recalc_for_upload(p_load_batch_k abob_tbl_load_batch.load_batch_k%type); 
  
procedure terminated_cession(p_losses_k abob_user.abob_tbl_losses.losses_k%type
                            , p_prev_losses_k abob_user.abob_tbl_losses.losses_k%type
                            , p_rev_gig_k abob_user.abob_tbl_lossgig.rev_gig_k%type
                            , p_acct_year IN abob_tbl_loss_years.acct_yr%type
                            , p_acct_month      IN abob_tbl_losses.month%type
                            , p_batch_mode boolean default false);  

procedure merge_batch_update;      

PROCEDURE init_gig_termination(
        p_gig_term_array in out tbl_gig_term_date,
        p_policy_num IN abob_user.abob_tbl_corp_gig.policy_num%TYPE default null,
        p_policy_sub IN abob_user.abob_tbl_corp_gig.policy_sub%TYPE default null
        );                                                                  

END ABOB_PKG_LOSS_CONTRA;
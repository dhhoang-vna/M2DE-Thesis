capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
/********************************************
BASELINE IV REGRESSIONS (Orbis firm-year + sector-year shocks)
- Endogenous regressor: China import penetration (IP)
- Instrument: Shift-share output IV (output_IV)
- Fixed effects: isic4 and year
- Standard errors: clustered by isic4 (variation is sector-year)
********************************************/
clear mata
capture log close
clear

log using "$LOGS\1 baseline_regressions", replace

global folder "$REPLICATION_ROOT"

use "$DATA_DERIVED\data_ready_mec.dta", clear

*----------------------------------
* 0. Create sector-year controls
*----------------------------------
capture confirm variable post2016
if _rc gen byte post2016 = year >= 2016 if !missing(year)

capture confirm variable exporter
if _rc gen byte exporter = (export_revenue>0) if !missing(export_revenue)

bys isic4 year firm_id: gen tag_firm = _n == 1
bys isic4 year: egen n_firms = total(tag_firm)

reg dln_mu ln_mu
reg exit ln_mu

reg dln_mu ebit_margin_
reg exit ebit_margin_

*----------------
* 1. First stage
*----------------
keep bvd_id_number exchange_rate_from_original_curr intangible_fixed_assets tangible_fixed_assets current_assets cash_cash_equivalent total_assets long_term_debt current_liabilities loans working_capital operating_revenue_turnover_ costs_of_goods_sold gross_profit extr_and_other_revenue export_revenue interest_paid gross_margin_ ebit_margin_ interest_cover_x_ current_ratio_x_ liquidity_ratio_x_ nace_num nace4 year firm_id nace4_num nace3 nace2 ppi net_sales isic4 dom_sales dom_sales_1 dom_pos total_sales share_sales rank_sales top20_share CR20_dom top10_share CR10_dom s2 HHI_dom N_dom one seen_t1 seen_t2 seen_t3 exit exit1 first_year age young agebin turnover cogs tfa itfa ln_rev dln_rev ln_tfa dln_tfa ebit_t1 gross_margin_ leverage high_leverage curr_ratio curr_ratio_lag wc_to_assets int_burden cash_to_assets mu ln_mu dln_mu dln_import_share shares output_IV Z_input value_isic IP lnSize ls_pre_filled change_IP post2016 exporter


* Ensure year is numeric
* Sort and declare panel-time (recommended for L.)
sort firm_id year

* Create log and log-difference safely
by firm_id: gen L_IP = IP[_n-1]   // manual lag
by firm_id: gen dln_IP = ln(IP) - ln(L_IP)
by firm_id: gen ln_IP = ln(IP)


reghdfe change_IP output_IV, absorb(year isic4) vce(cluster isic4)
estimates store FS

*----------------------------------
* 1.1. Outcome = firm growth (ok)
*----------------------------------
preserve
sort firm_id year
collapse(mean) dln_rev change_IP output_IV Z_input age leverage lnSize ls_pre_filled export_revenue isic4 post2016 if dom_sales > 0 & !missing(dom_sales) [aw=dom_sales], by(firm_id year)
tsset firm_id year

ivreghdfe dln_rev (change_IP = output_IV) Z_input L.age L.leverage L.lnSize L.export_revenue c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(firm_id) vce(cluster isic4) // 1%, -2.5209; 1%, -4.0822

ivreghdfe dln_rev (change_IP = output_IV) Z_input L.age L.leverage L.lnSize L.export_revenue c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) // 1%, -2.5209; 1%, -4.0822


restore

*------------------

preserve
sort firm_id year
collapse(mean) dln_rev change_IP output_IV Z_input age leverage lnSize ls_pre_filled isic4 post2016, by(firm_id year)
tsset firm_id year

ivreghdfe dln_rev (change_IP = output_IV) Z_input age leverage lnSize c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first // 1%, -2.5209

local y dln_rev 
local x change_IP
local z output_IV
local w Z_input age lnSize c.ls_pre_filled##i.post2016
local fe i.isic4##c.year

reghdfe `y' `w', absorb(`fe') resid(y_rev) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe') resid(x_rev) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe') resid(z_rev) vce(cluster isic4)

ivreg2 y_rev (x_rev= z_rev), nocons cluster(isic4) first //10%, -1.7975

boottest x_rev, cluster(isic4) reps(9999) seed(12345) // p = 0.0392, z = -1.7708

restore



/* Residualize change_IP and output_IV on controls + FE
reghdfe change_IP Z_input age l_leverage lnSize, absorb(isic4 year) resid
predict double uhat, resid

reghdfe output_IV Z_input age l_leverage lnSize, absorb(isic4 year) resid
predict double zhat, resid

* Regress residualized endogenous on residualized instrument
reg uhat zhat, vce(cluster isic4)
test zhat */
	
ivreghdfe dln_rev (change_IP = output_IV) Z_input age  lnSize, absorb(isic4 year) vce(cluster isic4#year) first
	
* Reduced form
reghdfe dln_rev output_IV Z_input age l_leverage lnSize, absorb(isic4 year) vce(cluster isic4)

* Add firm FE and drop 'age' (doesn't work rightaway)
ivreghdfe dln_rev (change_IP = output_IV) Z_input l_leverage lnSize, ///
    absorb(firm_id isic4 year) vce(cluster isic4) first

*/ remove year FE, include it as dummy
ivreghdfe dln_rev (change_IP = output_IV) Z_input l_leverage lnSize i.year, ///
    absorb(firm_id) vce(cluster isic4)

*---------------------------
* 1.2. Outcome = firm exit
* contemporaneous selection effects within shocked cells 
*---------------------------

preserve
sort firm_id year
collapse(max) exit (mean) change_IP output_IV Z_input age l_leverage lnSize ls_pre_filled liquidity_ratio_x_ isic4 post2016 if dom_sales > 0 & !missing(dom_sales) [aw=dom_sales], by(firm_id year)
tsset firm_id year

gen l_age = L.age
gen l_size = L.lnSize
gen l_liquidity = L.liquidity_ratio_x_

ivreghdfe exit (change_IP = output_IV) Z_input age l_leverage lnSize liquidity_ratio_x_ c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first // 5%, -0.5049

ivreghdfe exit (change_IP = output_IV) Z_input l_age l_size c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) // 10%, -0.3194

ivreghdfe exit (change_IP = output_IV) Z_input l_age l_size c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) // 10%, -0.3194


restore

* Model 1 equivalent: sector-year FE
reghdfe exit output_IV Z_input age leverage lnSize curr_ratio wc_to_assets c.ls_pre_filled##i.post2016 ///
    if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) //-0.3675, 5%



sum change_IP, detail

*** 5%
preserve
sort firm_id year
collapse(max) exit (mean) change_IP output_IV Z_input age l_leverage exporter ls_pre_filled liquidity_ratio_x_ isic4 post2016 if dom_sales > 0 & !missing(dom_sales) [aw=dom_sales], by(firm_id year)
tsset firm_id year

local y exit 
local x change_IP
local z output_IV
local w Z_input age exporter c.ls_pre_filled##i.post2016
local fe2 i.isic4##c.year
local fe1 isic4 year


reghdfe `y' `w', absorb(`fe1') resid(y_exit) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe1') resid(x_exit) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe1') resid(z_exit) vce(cluster isic4)

ivreg2 y_exit (x_exit= z_exit), nocons cluster(isic4) first // 1%, -0.7402

boottest x_exit, cluster(isic4) reps(9999) seed(12345) // p = 0.0799

restore

summ change_IP, detail


*------------------------
* 1.3. Outcome = markups
*------------------------

* 1.3.1. Baseline, markup change as outcome
tsset firm_id year
ivreghdfe dln_mu (change_IP = output_IV) Z_input L.age L.leverage L.lnSize, absorb(i.isic4##c.year) vce(cluster isic4) first //p=0.046, coeff = -0.507

ivreghdfe dln_mu (change_IP = output_IV) Z_input age L.leverage L.lnSize c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //p=0.052, coeff = -0.4406

ivreghdfe dln_mu (change_IP = output_IV) Z_input age L.leverage L.lnSize c.ls_pre_filled##i.post2016 i.year i.year#c.isic4 if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year i.year#c.isic4) //p=0.047, coeff = -0.4405


preserve
sort firm_id year
collapse(mean) dln_mu change_IP ln_mu output_IV Z_input age leverage lnSize liquidity_ratio_x_ ls_pre_filled isic4 post2016, by(firm_id year)
tsset firm_id year

bys firm_id: egen lnmu_base = mean(ln_mu) if inrange(year,2011,2012)
bys firm_id: egen lnmu_base2 = max(lnmu_base)
replace lnmu_base = lnmu_base2
drop lnmu_base2

ivreghdfe dln_mu (change_IP = output_IV) Z_input L.Z_input age L.leverage L.lnSize L.liquidity_ratio_x_ c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) // 5%, -0.5482

restore


* 
preserve
sort firm_id year
collapse(mean) dln_mu change_IP ln_mu output_IV Z_input exporter age leverage lnSize liquidity_ratio_x_ ls_pre_filled isic4 post2016, by(firm_id year)
tsset firm_id year

local y dln_mu 
local x change_IP
local z output_IV
local w Z_input age exporter c.ls_pre_filled##i.post2016
local fe2 i.isic4##c.year
local fe1 isic4 year


reghdfe `y' `w', absorb(`fe1') resid(y_mu) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe1') resid(x_mu) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe1') resid(z_mu) vce(cluster isic4)

ivreg2 y_mu (x_mu= z_mu), nocons cluster(isic4) first // p = 0.050, z = -0.5121

boottest x_mu, cluster(isic4) reps(9999) seed(12345) // p = 0.0497, coef = -0.5032

restore

* 1.3.2. Markup as heterogeneous treatment effect

tsset firm_id year
* Predicted markup level to isolate the China-driven component of markup changes
reghdfe ln_mu output_IV if inrange(year, 2011, 2019), absorb(firm_id isic4##c.year) vce(cluster isic4)

* Compute pre vs post averages
predict ln_mu_hat
gen pre = inrange(year, 2011, 2016)
gen post = inrange(year, 2017, 2019)

drop ln_mu_pre ln_mu_post

bysort firm_id: egen ln_mu_pre = mean(ln_mu_hat) if pre
bysort firm_id: egen ln_mu_post = mean(ln_mu_hat) if post

summ ln_mu_post ln_mu_pre

bysort firm_id: egen ln_mu_pre_1 = max(ln_mu_pre)
bysort firm_id: egen ln_mu_post_1 = max(ln_mu_post)

* Classify firms by markup change
gen delta_mu = ln_mu_post_1 - ln_mu_pre_1
summ delta_mu

gen increasing_mu = (delta_mu > 0) if !missing(delta_mu)

* Descriptive stats (non-exhaustive)
ttest ln_mu, by(increasing_mu) 

* Regressions with heterogeneous effects
ivreghdfe dln_rev (c.change_IP c.change_IP#1.increasing_mu = c.output_IV c.output_IV#1.increasing_mu) Z_input age lnR lnSize, absorb(firm_id isic4##c.year) vce(cluster isic4) first

// group 0
ivreghdfe dln_rev (c.change_IP = c.output_IV) ///
    Z_input age l_leverage lnSize ///
    if increasing_mu==0, ///
    absorb(isic4##c.year) vce(cluster isic4) first //p=0.016, coef = -3.9
	
// group 1 
ivreghdfe dln_rev (c.change_IP = c.output_IV) ///
    Z_input age l_leverage lnSize ///
    if increasing_mu==1, ///
    absorb(isic4##c.year) vce(cluster isic4) first //p=0.143, coef = -5.47, weak instrument
	
tsset firm_id year	

ivreghdfe dln_tfa (c.change_IP c.change_IP#i.increasing_mu = c.output_IV c.output_IV#i.increasing_mu) Z_input age L.lnSize, absorb(isic4##c.year) vce(cluster isic4) first savefprefix(fs_) //the interaction is not significant 

by firm_id: gen d_ebit = ebit_t1 - L.ebit_t1
by firm_id: gen d_gross_margin = gross_margin_t1 - L.gross_margin_t1


ivreghdfe d_gross_margin (c.change_IP c.change_IP#1.increasing_mu = c.output_IV c.output_IV#1.increasing_mu) Z_input age L.lnSize, absorb(i.isic4##c.year) vce(cluster isic4) first savefprefix(fs_) //the interaction is not significant 


* Interact China shock with continuous markup change. For every 1 std increase in markup change, how does the effect of Chinese competition on exit change? 

ivreghdfe dln_rev (c.change_IP c.change_IP#c.delta_mu = c.output_IV c.output_IV#c.delta_mu) Z_input age L.lnSize, absorb(i.isic4##c.year) vce(cluster isic4) first savefprefix(fs_) //

ivreghdfe dln_rev (c.change_IP c.change_IP#c.dln_mu = c.output_IV c.output_IV#c.dln_mu) dln_mu Z_input age L.lnSize, absorb(i.isic4##c.year year) vce(cluster isic4) first savefprefix(fs_) //the interaction is not significant 

corr Z_input output_IV


* Interact 
summ delta_mu

ivreghdfe exit_lead (change_IP = output_IV) Z_input age lnSize, absorb(i.isic4##c.year) vce(cluster isic4) first savefprefix(fs_) // for 1, it's significant, 


ivreghdfe exit_lead (c.change_IP c.change_IP#i.increasing_mu = c.output_IV c.output_IV#i.increasing_mu) i.increasing_mu Z_input age lnSize, absorb(i.isic4##c.year) vce(cluster isic4) first savefprefix(fs_) // for 1, it's significant, 


*** Pre-period markup and heterogeneity? 

gen pre_1112 = inrange(year, 2011, 2012)

/*reghdfe ln_mu, absorb(isic4#year) resid 
gen ln_mu_resid = e(resid) // residualize log markup level within isic4 x year

bys firm_id: egen mu_pre_1112 = mean(ln_mu_resid) if pre_1112 //firm baseline average (smoothing)
summ ln_mu_resid*/

bys firm_id: egen mu_pre_1112 = mean(ln_mu) if pre_1112

bys firm_id: egen mu_pre_f = max(mu_pre_1112)

bys isic4: egen med_mu = median(mu_pre_f)
gen high_mu = (mu_pre_f > med_mu)

tsset firm_id year
ivreghdfe dln_rev (c.change_IP c.change_IP#i.high_mu = c.output_IV c.output_IV#i.high_mu) i.high_mu Z_input age L.lnSize, absorb(i.isic4##c.year) vce(cluster isic4) first

gen xH = change_IP*(high_mu==1)
gen xL = change_IP*(high_mu==0)
gen zH = output_IV*(high_mu==1)
gen zL = output_IV*(high_mu==0)

ivreghdfe dln_rev (xH xL = zH zL) i.high_mu Z_input age L.lnSize, absorb(i.isic4##c.year) vce(cluster isic4) first

test xH = xL // p = 0.965. Both groups lose revenue growth by approx the same amount when import penetration rises. No heterogeneity


// 2009-2012

gen pre_0912 = inrange(year, 2009, 2012)

/*reghdfe ln_mu, absorb(isic4#year) resid 
gen ln_mu_resid = e(resid) // residualize log markup level within isic4 x year

bys firm_id: egen mu_pre_1112 = mean(ln_mu_resid) if pre_1112 //firm baseline average (smoothing)
summ ln_mu_resid*/

bys firm_id: egen mu_pre_0912= mean(ln_mu) if pre_0912

bys firm_id: egen mu_pre_f1 = max(mu_pre_0912)

bys isic4: egen med_mu1 = median(mu_pre_f1)
gen high_mu1 = (mu_pre_f1 > med_mu1)

tsset firm_id year
ivreghdfe dln_rev (c.change_IP c.change_IP#i.high_mu = c.output_IV c.output_IV#i.high_mu) i.high_mu Z_input age L.lnSize if inrange(year, 2013, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first

gen xH1 = change_IP*(high_mu1==1)
gen xL1 = change_IP*(high_mu1==0)
gen zH1 = output_IV*(high_mu1==1)
gen zL1 = output_IV*(high_mu1==0)

ivreghdfe dln_rev (xH1 xL1 = zH1 zL1) i.high_mu1 Z_input age L.lnSize if inrange(year, 2013, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first

ivreghdfe dln_rev (xH1 xL1 = zH1 zL1) i.high_mu1 Z_input age L.lnSize c.ls_pre_filled##i.post2016 if inrange(year, 2013, 2019), absorb(isic4 year) vce(cluster isic4) first

test xH1 = xL1 // p = 0.965. Both groups lose revenue growth by approx the same amount when import penetration rises. No heterogeneity

tab high_mu // 2/3 is high_mu

************************

preserve
sort firm_id year
collapse(mean) dln_rev change_IP output_IV Z_input age leverage lnSize ls_pre_filled isic4 post2016 high_mu1, by(firm_id year)
tsset firm_id year

gen xH1 = change_IP*(high_mu1==1)
gen xL1 = change_IP*(high_mu1==0)
gen zH1 = output_IV*(high_mu1==1)
gen zL1 = output_IV*(high_mu1==0)

ivreghdfe dln_rev (xH1 xL1 = zH1 zL1) i.high_mu1 Z_input age lnSize leverage c.ls_pre_filled##i.post2016 if inrange(year, 2013, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first //z1 = -3.0208, p1=0.061, z2 = -5.3135, p2 = 0.010

local y dln_rev
local x1 xH1
local x2 xL1
local z1 zH1
local z2 zL1
local w Z_input age lnSize leverage c.ls_pre_filled##i.post2016
local fe i.isic4##c.year

reghdfe `y' `w', absorb(`fe') resid(y_rev_he) vce(cluster isic4)
reghdfe `x1' `w', absorb(`fe') resid(xH_rev) vce(cluster isic4)
reghdfe `z1' `w', absorb(`fe') resid(zH_rev) vce(cluster isic4)
reghdfe `x2' `w', absorb(`fe') resid(xL_rev) vce(cluster isic4)
reghdfe `z2' `w', absorb(`fe') resid(zL_rev) vce(cluster isic4)

ivreg2 y_rev_he (xH_rev xL_rev = zH_rev zL_rev), nocons cluster(isic4) first

boottest xH_rev xL_rev, cluster(isic4) reps(1999) seed(12345) // too time-consuming

restore

****************************

ivreghdfe F3.exit (xH1 xL1 = zH1 zL1) i.high_mu1 Z_input age lnSize c.ls_pre_filled##i.post2016 if inrange(year, 2013, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first //no heterogeneity, insignificant


	
*--------------------------------	
* 1.4. Domestic concentration (!!!)
*--------------------------------
drop s2 HHI_dom

gen s2 = share_sales^2 if dom_pos
bys isic4 year: egen HHI_dom = total(s2)

//HHI
preserve
collapse (mean) HHI_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

gen d_HHI = HHI_dom - L.HHI_dom

ivreghdfe d_HHI (change_IP = output_IV) Z_input age curr_ratio leverage lnSize interest_cover_x_ HHI_dom c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first //10%, 0.6097

restore


preserve

collapse (mean) HHI_dom age curr_ratio leverage lnSize interest_cover_x_ ///
         change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

* 1) Generate the lead once
gen F_HHI_dom = F.HHI_dom
gen d_HHI_dom = HHI_dom - L.HHI_dom

* 2) Define the exact analysis sample first
gen sample = inrange(year, 2011, 2018) ///
             & !missing(F_HHI_dom, d_HHI_dom, change_IP, output_IV, Z_input, ///
                       age, curr_ratio, leverage, lnSize, interest_cover_x_, ///
                       HHI_dom, ls_pre_filled, post2016)

keep if sample

* 3) Run ivreghdfe on this restricted sample
ivreghdfe F_HHI_dom (change_IP = output_IV) Z_input age curr_ratio ///
    leverage lnSize interest_cover_x_ HHI_dom ///
    c.ls_pre_filled##i.post2016, ///
    absorb(i.isic4##c.year) vce(cluster isic4) first

* 4) Residualize using the same sample and regressors
local y F_HHI_dom
local x change_IP
local z output_IV
local w Z_input c.ls_pre_filled##i.post2016 HHI_dom ///
         curr_ratio leverage lnSize interest_cover_x_ age
local fe i.isic4##c.year

reghdfe `y' `w' if sample, absorb(`fe') resid(y_hhi) vce(cluster isic4)
reghdfe `x' `w' if sample, absorb(`fe') resid(x_hhi) vce(cluster isic4)
reghdfe `z' `w' if sample, absorb(`fe') resid(z_hhi) vce(cluster isic4)

ivreg2 y_hhi (x_hhi = z_hhi) if sample, nocons cluster(isic4) first
boottest x_hhi if sample, cluster(isic4) reps(9999) seed(12345) ///
    gridmin(-5) gridmax(5) level(90)

restore

tab exit


//CR20
preserve
collapse (mean) CR20_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

ivreghdfe F.CR20_dom (change_IP = output_IV) Z_input c.ls_pre_filled#i.post2016 if inrange(year, 2011, 2018), absorb(i.isic4##c.year) vce(cluster isic4) first //1 year, 10%, -0.6703

local y F.CR20_dom 
local x change_IP
local z output_IV
local w Z_input c.ls_pre_filled##i.post2016 CR20_dom curr_ratio leverage lnSize interest_cover_x_ age
local fe i.isic4##c.year

reghdfe `y' `w', absorb(`fe') resid(y_cr20_) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe') resid(x_cr20_) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe') resid(z_cr20_) vce(cluster isic4)

ivreg2 y_cr20_ (x_cr20_ = z_cr20_) if inrange(year,2011,2018), nocons cluster(isic4) first //insignificant 

boottest x_cr20_, cluster(isic4) reps(9999) seed(12345) gridmin(-5) gridmax(5) level(90) //insignificant

restore

//CR20--------------------

preserve

* 1. Collapse to sector-year level
collapse (mean) CR20_dom age curr_ratio leverage lnSize interest_cover_x_ ///
         change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

* 2. Construct lead once
gen F_CR20_dom = F.CR20_dom

* 3. Define exact analysis sample (years + non-missing)
gen byte sample = inrange(year, 2011, 2018) ///
    & !missing(F_CR20_dom, change_IP, output_IV, Z_input, ///
              ls_pre_filled, post2016, CR20_dom, ///
              curr_ratio, leverage, lnSize, interest_cover_x_, age)

keep if sample

* 4. Main IV regression with ivreghdfe on this sample
ivreghdfe F_CR20_dom (change_IP = output_IV) Z_input ///
    c.ls_pre_filled##i.post2016 ///
    curr_ratio leverage lnSize interest_cover_x_ age CR20_dom ///
    , absorb(i.isic4##c.year) vce(cluster isic4) first

* 5. Residualize y, x, z with identical controls, FE, and sample
local y F_CR20_dom
local x change_IP
local z output_IV
local w Z_input c.ls_pre_filled##i.post2016 ///
         CR20_dom curr_ratio leverage lnSize interest_cover_x_ age
local fe i.isic4##c.year

reghdfe `y' `w' if sample, absorb(`fe') resid(y_cr20_) vce(cluster isic4)
reghdfe `x' `w' if sample, absorb(`fe') resid(x_cr20_) vce(cluster isic4)
reghdfe `z' `w' if sample, absorb(`fe') resid(z_cr20_) vce(cluster isic4)

* 6. IV on residuals, same sample
ivreg2 y_cr20_ (x_cr20_ = z_cr20_) if sample, nocons cluster(isic4) first

* 7. Wild-cluster bootstrap
boottest x_cr20_ if sample, cluster(isic4) reps(9999) seed(12345) ///
    gridmin(-5) gridmax(5) level(90)

restore


//CR10------------------
preserve
collapse (mean) CR10_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

ivreghdfe F.CR10_dom (change_IP = output_IV) Z_input c.ls_pre_filled#i.post2016 if inrange(year, 2011, 2018), absorb(i.isic4##c.year) vce(cluster isic4) first //1 year, 10%, -0.6703

local y F.CR10_dom 
local x change_IP
local z output_IV
local w Z_input c.ls_pre_filled##i.post2016 CR10_dom curr_ratio leverage lnSize interest_cover_x_ age
local fe i.isic4##c.year

reghdfe `y' `w', absorb(`fe') resid(y_cr10_) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe') resid(x_cr10_) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe') resid(z_cr10_) vce(cluster isic4)

ivreg2 y_cr10_ (x_cr10_ = z_cr10_) if inrange(year,2011,2018), nocons cluster(isic4) first //5%, -0.56

boottest x_cr10_, cluster(isic4) reps(9999) seed(12345) gridmin(-5) gridmax(5) level(90) //insignificant

restore

//-----------------
preserve

* 1. Collapse to sector-year level
collapse (mean) CR10_dom age curr_ratio leverage lnSize interest_cover_x_ ///
         change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

* 2. Construct lead once
gen F_CR10_dom = F.CR10_dom

* 3. Define exact analysis sample (years + non-missing)
gen byte sample = inrange(year, 2011, 2018) ///
    & !missing(F_CR10_dom, change_IP, output_IV, Z_input, ///
              ls_pre_filled, post2016, CR10_dom, ///
              curr_ratio, leverage, lnSize, interest_cover_x_, age)

keep if sample

* 4. Main IV regression with ivreghdfe on this sample (10%)
ivreghdfe F_CR10_dom (change_IP = output_IV) Z_input ///
    c.ls_pre_filled##i.post2016 ///
    curr_ratio leverage lnSize interest_cover_x_ age CR10_dom ///
    , absorb(i.isic4##c.year) vce(cluster isic4) first

* 5. Residualize y, x, z with identical controls, FE, and sample
local y F_CR10_dom
local x change_IP
local z output_IV
local w Z_input c.ls_pre_filled##i.post2016 ///
         CR10_dom curr_ratio leverage lnSize interest_cover_x_ age
local fe i.isic4##c.year

reghdfe `y' `w' if sample, absorb(`fe') resid(y_cr10_) vce(cluster isic4)
reghdfe `x' `w' if sample, absorb(`fe') resid(x_cr10_) vce(cluster isic4)
reghdfe `z' `w' if sample, absorb(`fe') resid(z_cr10_) vce(cluster isic4)

* 6. IV on residuals, same sample (10%)
ivreg2 y_cr10_ (x_cr10_ = z_cr10_) if sample, nocons cluster(isic4) first

* 7. Wild-cluster bootstrap
boottest x_cr10_ if sample, cluster(isic4) reps(9999) seed(12345) ///
    gridmin(-5) gridmax(5) level(90)

restore

*------------------



ivreghdfe F3.CR10_dom (c.change_IP##i.post2016 = c.output_IV##i.post2016) Z_input age lnSize c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) first //


// Import competition reallocates toward the very top of the domestic distribution. Right-tail dominance.

// t+3: top firms absorb demand, labor, and market share. Concentration among the largest firms rises measurably.

gen d3_CR10 = F3.CR10_dom - CR10_dom

ivreghdfe d3_CR10 (change_IP = output_IV) Z_input age lnSize c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first //


// In local projection IV regressions, the effect of import penetration on concentration is economically large but only shows up with a delay.	
forvalues h = 0/4 {
    ivreghdfe F`h'.CR20_dom ///
        (change_IP = output_IV) ///
        Z_input i.year ///
        if inrange(year,2011,2019-`h'), ///
        absorb(isic4) vce(cluster isic4) first
    estimates store h`h'
}
esttab h0 h1 h2 h3 h4, se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP) label

//Bootstrap test
ivreghdfe F3.CR20_dom ///
        (change_IP = output_IV) ///
        Z_input i.year ///
        if inrange(year,2011,2019), ///
        absorb(isic4) vce(cluster isic4) first

boottest change_IP, cluster(isic4) reps(9999) seed(12345)



// Point estimates indicate an increase in concentration at horizon 3, but the effect is not statistically distinguishable from zero under wild cluster bootstrap inference (p = 0.31), suggesting limited precision.

// 
ivreghdfe d3_CR10 (change_IP = output_IV) Z_input i.year ///
    if inrange(year,2011,2016), absorb(isic4) vce(cluster isic4)




*--------------------------
* 2. Baseline 2SLS outcomes
*--------------------------
cap which ivreghdfe 
if _rc {
	di as error "ivreghdfe not installed. Run ssc install ivreghdfe"
	exit 199
}

* Outcomes 
local Y "exit_lead dln_rev dln_tfa ebit_t1 gross_margin_t1"

cap which eststo
if _rc {
	* Run without storing
	foreach y of local Y {
		di as txt "=== 2SLS: `y' on IP (IV=output_IV) ==="
		ivreghdfe `y' (IP = output_IV) Z_input `X', absorb(`FE') vce(cluster isic4)
	}
}
else {
	eststo clear
	foreach y of local Y {
		eststo `y': ivreghdfe `y' (IP = output_IV) Z_input `X', absorb(`FE') vce(cluster isic4)
	}
	* Compact table: coefficient on IP only
    esttab exit_lead dln_rev dln_tfa ebit_t1 gross_margin_t1, ///
        se star(* 0.10 ** 0.05 *** 0.01) ///
        keep(IP) ///
        stats(N, fmt(%9.0g) labels("Obs")) ///
        title("Baseline 2SLS: Outcome(t+1) on China Import Penetration (IP)")
}




log close

















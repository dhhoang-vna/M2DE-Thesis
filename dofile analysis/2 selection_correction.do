/*******************************************
To remedy selection bias (which has been seen in exit  diagnostic regression) in the baseline, I use the semiparametric approach (Backus, 2020) to derive the within-firm treatment effect of import penetration on markup adjustment.  
- Selection: firm-level markup adjustment dln_mu observed only if firm observed in t-1 and t (consecutive)
- Correction: add g(.) as 3rd-order polynomial series in lagged markup level (ln_mu)/lagged profitability (ebit_margin_)

In addition, I use grouped IV quantiles at sector-year level (unfinished)
*******************************************/

clear mata
capture log close
clear

log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\2 selection_correction.log", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

use "$folder\Data\data_ready.dta", clear

* lagged state
gen lln_mu = L.ln_mu
gen l_ebitm = L.ebit_margin_

* selection indicator (!)
gen byte S = !missing(dln_mu)

* export status control
gen exporter = (export_revenue>0)

** markup and market share comovement?
gen ln_share = ln(share_sales)
bysort isic4 year: gen dln_share = ln_share - ln_share[_n-1]
 
reghdfe dln_mu dln_share $X_lag if inrange(year, 2011, 2019), absorb(isic4 year firm_id) vce(cluster firm_id)

*----------------------------------------------
* 1. Construct flexible control function g(.)
*----------------------------------------------

* centering
summ lln_mu if S==1, meanonly
gen clln_mu = lln_mu - r(mean)

summ l_ebitm if S==1, meanonly
gen cl_ebitm = l_ebitm - r(mean)

* 3rd-order polynomial terms
gen clln_mu2 = clln_mu^2
gen clln_mu3 = clln_mu^3

gen cl_ebitm2 = cl_ebitm^2
gen cl_ebitm3 = cl_ebitm^3


* put them in a macro
global g_poly1 "clln_mu clln_mu2 clln_mu3"
global g_poly2 "cl_ebitm cl_ebitm2 cl_ebitm3"

* robustness: g(.) based on lagged states and decile bins
xtile bin_lnmu = lln_mu, nq(10)
xtile bin_ebit = l_ebitm, nq(10)

*-----------------------------------
* 2. Predetermined controls (t-1)
*-----------------------------------

gen llnsize = L.lnSize
gen lleverage = L.leverage
gen lliquidity = L.liquidity_ratio_x_
gen l_age = L.age
gen l_exporter = L.exporter

global X_lag "lleverage lliquidity llnsize l_age l_exporter"


reg output_IV Z_input
predict output_IV_resid if e(sample), resid

corr output_IV_resid Z_input


* Stay true
isid firm_id year
ivreghdfe F.exit (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE, 0.817, insignificant

estat endogenous llnsize lleverage lliquidity l_age l_exporter

ivreghdfe F.exit (change_IP = output_IV_resid) Z_input c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE, no lagged controls 0.914, 5% significant

summ exit exit1, detail

reg exit llnsize
reg exit l_exporter
reg exit lleverage
reg exit l_age

tab exit

*-----------------------------------
* 3. Baseline 2SLS 
*-----------------------------------

ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE // 5%, -0.4610

ivreghdfe dln_mu (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE, no controls // 10%, -0.4221


*-------------------------------------------
* 4. Diagnostics for the latent state proxy
*-------------------------------------------
xtset firm_id year

eststo clear

* Persistence
reghdfe ebit_margin_ l_ebitm $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(firm_id isic4 year) vce(cluster firm_id) //coef = 0.0437, 1%
eststo PERSIST
estadd local DV "EBIT margin(t)"


* Survival prediction
reghdfe exit c.l_ebitm $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(firm_id isic4 year) vce(cluster firm_id) //5%, -0.0005
eststo EXIT_L
estadd local DV "Exit"

// U-shaped correlation between exit probability and lagged EBIT margin, not monotonic.

* Nonlinearity
gen l_ebitm2 = l_ebitm^2
reghdfe exit c.l_ebitm c.l_ebitm2 $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(firm_id isic4 year) vce(cluster firm_id) //both significant, quadratic term 1%
eststo EXIT_Q
test c.l_ebitm2
estadd scalar p_quad = r(p)
estadd local DV "Exit"


// Yes, EBIT margin proxy predicts exit proba nonlinearly

* Markup adjustment prediction
reghdfe dln_mu l_ebitm $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(firm_id isic4 year) vce(cluster firm_id) //coef = -0.0087, 1%
eststo MU
estadd local DV "Markup_Adjustment"


* Markov structure test
xtset firm_id year
reghdfe exit l_ebitm L.l_ebitm $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(firm_id isic4 year) vce(cluster firm_id) //L2 is irrelevant, Markov persistence is plausibly credible
eststo MARKOV
test L.l_ebitm
estadd scalar p_L2 = r(p)
estadd local DV "Exit"

* Export table
local keepvars "l_ebitm l_ebitm2 L.l_ebitm"

esttab PERSIST EXIT_L EXIT_Q MU MARKOV using "proxy_validation_table.tex", replace ///
	booktabs label se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(`keepvars') ///
    order(l_ebitm l_ebitm2 L.l_ebitm) ///
    stats(N r2 DV p_quad p_L2, ///
          labels("Obs." "R-sq." "Dependent var." "p-value: l_ebitm^2" "p-value: 2nd lag")) ///
    mtitles("Persistence" "Exit (lin.)" "Exit (quad.)" "Markup Adjustments" "Markov test") ///
    title("Validation of Lagged EBIT Margin as State Proxy") ///
    addnotes("All specs include firm, sector (isic4), and year fixed effects; SEs clustered at firm level.", ///
             "Controls: $X_lag and c.ls_pre_filled##i.post2016. Sample: 2011–2019.")


* Monotonicity diagnostics: survival by deciles of lagged proxy
xtile l_ebitm_dec10 = l_ebitm, nq(10)

preserve
collapse (mean) exit l_ebitm (count) N=exit, by(l_ebitm_dec10)
sort l_ebitm_dec10
list l_ebitm_dec10 N l_ebitm exit, sep(0)
twoway line exit l_ebitm_dec10, ///  
	ytitle("Pr(exit to t+1)") xtitle("Decile of lagged proxy") ///
	title("Monotonicity: survival vs lagged proxy deciles")
restore
			 

*-----------------------------------
* 5. Selection correction
*-----------------------------------

preserve

sort firm_id year
collapse(mean) dln_mu change_IP output_IV Z_input llnsize lleverage lliquidity l_age l_exporter HHI_dom $g_poly2 ls_pre_filled isic4 post2016 [aw=dom_sales], by(firm_id year)
tsset firm_id year

* Main IV regression
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter $g_poly2 c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) 
eststo iv_main 

restore

* Residual-based IV (2‑stage)
local y dln_mu 
local x change_IP
local z output_IV
local w Z_input llnsize lleverage lliquidity l_age l_exporter $g_poly2 c.ls_pre_filled##i.post2016
local fe1 isic4 year

reghdfe `y' `w', absorb(`fe1') resid(y_mu) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe1') resid(x_mu) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe1') resid(z_mu) vce(cluster isic4)

ivreg2 y_mu (x_mu = z_mu), nocons cluster(isic4) first
eststo iv_resid

* Wild bootstrap p-value (just store p)
boottest x_mu, cluster(isic4) reps(9999) seed(12345)
eststo iv_resid
estadd scalar p_wild = r(p)  // this works: p = 0.0185

restore

* 5. Clean console table (p-value + CI as note)
esttab iv_resid ///
    keep(x_mu) ///
    coeflabels(x_mu "Δ Chinese import penetration") ///
    b(3) se(3) ///
    stats(N r2 p_wild, ///
          fmt(0 3 3) ///
          labels("N" "R²" "Wild p-val")) ///
    mtitles("Residualized 2SLS") ///
    title("IV Results: Markup Change") ///
    note("Wild 95% CI: [-1.131, 0.034]") ///
    nogaps compress wide


restore


*------------------------------------------------------------
* Panel collapse + IV (main + residualized), wild bootstrap p
*------------------------------------------------------------


* Robustness: running with decile dummies as flexible g(.)

ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age c.ls_pre_filled##i.post2016 i.year i.bin_ebit i.bin_lnmu if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE (partial out...) // 11.9%, coef = -0.4539


* Quantify selection bias


*------------------------
* Heterogeneity with CR4
*------------------------

// Sum of shares for top 4 firms 
gen top4_share = share_sales if rank_sales<=4 & dom_pos
bys isic4 year: egen CR4_dom = total(top4_share)

summ CR4_dom if inrange(year,2011,2019), meanonly
gen CR4_c = CR4_dom - r(mean)

// Regressions 
ivreghdfe dln_mu (change_IP c.change_IP#c.CR4_dom = output_IV c.output_IV#c.CR4_dom) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE, with controls and selection correction function // beta interaction = -2.195 (10%), but F-stat = 3.886 (10% is 7.03)

ivreghdfe dln_mu (change_IP c.change_IP#c.CR4_dom = output_IV c.output_IV#c.CR4_dom) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year $g_poly2 if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE, with controls and selection correction function // beta interaction = -3.568 (1%), but F-stat = 3.877 (10% is 7.03)



*-------------------------
* 6. Grouped IV quantiles
*-------------------------

preserve

/*keep if S==1
    keep isic4 year dln_mu dIP Z
    drop if missing(dln_mu) | missing(dIP) | missing(Z)*/

bys isic4 year: egen n_jt = count(dln_mu)

* Quantiles within sector-year
forvalues p = 5(5)95 {
    bys isic4 year: egen q`p' = pctile(dln_mu), p(`p')
}

* Keep one row per sector-year
bys isic4 year: keep if _n==1
bys isic4 year: egen lleverage_j = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j  = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j = mean(llnsize)

global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"

* Order-statistic bias controls: 3rd-order polynomial in n_jt
gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

* Run IV for each quantile 
 
matrix results = J(20, 4, .)
matrix colnames results = beta_IP se_IP N R2

local percentiles "5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95"
local row = 1
isid firm_id year
tsset firm_id year
foreach p of local percentiles {
    ivreghdfe q`p' (c.change_IP = c.output_IV) Z_input $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
    
    matrix results[`row',1] = _b[change_IP]
    matrix results[`row',2] = _se[change_IP]
    matrix results[`row',3] = e(N)
    matrix results[`row',4] = e(r2)
    
    local row = `row' + 1
}

* Set rownames once after loop
matrix rownames results = `percentiles'

matrix list results, format(%9.3f)

restore

*------------------------------------------------
* Mechanism: Verify the distribution of markup adjustments and the distribution of markup levels across firms
*------------------------------------------------

preserve

/*keep if S==1
    keep isic4 year dln_mu dIP Z
    drop if missing(dln_mu) | missing(dIP) | missing(Z)*/

bys isic4 year: egen n_jt = count(dln_mu)

* Quantiles within sector-year
forvalues p = 5(5)95 {
    bys isic4 year: egen q`p' = pctile(dln_mu), p(`p')
}

* Aggregate markup levels and controls to sector-year
bys isic4 year: egen llnmu_j = mean(lln_mu)

bys isic4 year: egen lleverage_j = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j  = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j = mean(llnsize)

global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"


* Keep one row per sector-year
bys isic4 year: keep if _n==1

* Order-statistic bias controls: 3rd-order polynomial in n_jt
gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

* Run IV for each quantile 
 
matrix results = J(20, 6, .)
matrix colnames results = beta_IP se_IP beta_int_terms se_int_terms N R2

local percentiles "5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95"
local row = 1

foreach p of local percentiles {
    ivreghdfe q`p' (c.change_IP##c.llnmu_j = c.output_IV##c.llnmu_j) Z_input $n_poly $X_lag_j llnmu_j c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
    
    matrix results[`row',1] = _b[change_IP]
    matrix results[`row',2] = _se[change_IP]
    matrix results[`row',3] = _b[c.change_IP#c.llnmu_j]
    matrix results[`row',4] = _se[c.change_IP#c.llnmu_j]
    matrix results[`row',5] = e(N)
    matrix results[`row',6] = e(r2)
    
    local row = `row' + 1
}

* Set rownames once after loop
matrix rownames results = `percentiles'

matrix list results, format(%9.3f)

restore

// Heterogeneity: The upper-tail quantiles fall sharply with change in IP, but 

** 

preserve
keep if year >= 2011 & year <= 2019

* Generate within-industry-year ranks (0-1 scale)
bysort isic4 year: egen rank_level = rank(lln_mu)
bysort isic4 year: egen rank_adjust = rank(dln_mu)
bysort isic4 year: gen n_firms = _N

* Convert to terciles (1=Low, 2=Med, 3=High)
gen tercile_level = 1 if rank_level <= n_firms/3
replace tercile_level = 2 if rank_level > n_firms/3 & rank_level <= 2*n_firms/3
replace tercile_level = 3 if rank_level > 2*n_firms/3 & !missing(rank_level)

gen tercile_adjust = 1 if rank_adjust <= n_firms/3
replace tercile_adjust = 2 if rank_adjust > n_firms/3 & rank_adjust <= 2*n_firms/3
replace tercile_adjust = 3 if rank_adjust > 2*n_firms/3 & !missing(rank_adjust)

* Labels
label define tercile_lab 1 "Low" 2 "Med" 3 "High"
label values tercile_level tercile_lab
label values tercile_adjust tercile_lab

* Summary table for paper
tab tercile_level tercile_adjust, cell row col chi2
restore

**************

preserve
keep if inrange(year,2011,2019)
drop if missing(lln_mu, dln_mu)

* --- Baseline markup terciles within sector-year ---
bys isic4 year: egen p33_mu = pctile(lln_mu), p(33.3333)
bys isic4 year: egen p67_mu = pctile(lln_mu), p(66.6667)

gen tercile_level = .
replace tercile_level = 1 if lln_mu <= p33_mu
replace tercile_level = 2 if lln_mu >  p33_mu & lln_mu <= p67_mu
replace tercile_level = 3 if lln_mu >  p67_mu

* --- Adjustment terciles within sector-year ---
bys isic4 year: egen p33_d = pctile(dln_mu) if dln_mu>0, p(33.3333)
bys isic4 year: egen p67_d = pctile(dln_mu) if dln_mu>0, p(66.6667)

gen tercile_adjust = .
replace tercile_adjust = 1 if dln_mu <= p33_d
replace tercile_adjust = 2 if dln_mu >  p33_d & dln_mu <= p67_d
replace tercile_adjust = 3 if dln_mu >  p67_d

label define tercile_lab 1 "Low" 2 "Med" 3 "High"
label values tercile_level tercile_lab
label values tercile_adjust tercile_lab

tab tercile_level tercile_adjust, row col chi2

restore




log close



// issue: coefficient shrink, SE rises modestly

// use both
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age $g_poly1 $g_poly2 c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE (partial out...) // 8.8%, coef = -0.4213

//interact both with post2016
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age i.post2016##c.$g_poly1 i.post2016##c.$g_poly2 c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE (partial out...) // 8.8%, coef = -0.4199

//interact both with exit
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age $g_poly1 $g_poly2 exit#c.$g_poly1 exit#c.$g_poly2 c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE (partial out...) // 8.5%, coef = -0.4308

//interact both with exit and post2016???

ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age $g_poly1 exit#c.$g_poly1 c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) //sector FE + year FE (partial out...) // 





preserve

*-----------------------------
* (A) Build sector-year quantiles of firm-level dln_mu
*-----------------------------
bys isic4 year: egen n_jt = count(dln_mu)

* Quantiles within sector-year (firm-level distribution)
forvalues p = 5(5)95 {
    bys isic4 year: egen q`p' = pctile(dln_mu), p(`p')
}

* Keep one row per sector-year
bys isic4 year: keep if _n==1

* Order-statistic bias controls: 3rd-order polynomial in n_jt
gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

*-----------------------------
* (B) Run IV by quantile and store results
*-----------------------------
local percentiles "5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95"
local K : word count `percentiles'

matrix results = J(`K', 4, .)
matrix colnames results = beta_IP se_IP N R2

local row = 1
foreach p of local percentiles {

    ivreghdfe q`p' ///
        (c.change_IP c.change_IP#c.CR4_dom = c.output_IV c.output_IV#c.CR4_dom) ///
        Z_input $n_poly $X_lag ///
        c.ls_pre_filled##i.post2016 i.year ///
        if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

    matrix results[`row',1] = _b[c.change_IP#c.CR4_dom]
    matrix results[`row',2] = _se[c.change_IP#c.CR4_dom]
    matrix results[`row',3] = e(N)
    matrix results[`row',4] = e(r2)

    local ++row
}

matrix rownames results = `percentiles'
matrix list results, format(%9.3f)

*-----------------------------
* (C) Convert matrix to dataset for plotting
*-----------------------------
clear
svmat double results, names(col)

gen p = .
local i = 1
foreach q of local percentiles {
    replace p = `q' in `i'
    local ++i
}

gen ci_lo = beta_IP - 1.96*se_IP
gen ci_hi = beta_IP + 1.96*se_IP

label var p       "Quantile (p)"
label var beta_IP "2SLS coef on ΔIP"
label var ci_lo   "95% CI lower"
label var ci_hi   "95% CI upper"

*-----------------------------
* (D) Plot: beta(p) with 95% CI
*-----------------------------
twoway ///
    (rcap ci_lo ci_hi p, lwidth(thin)) ///
    (connected beta_IP p, msymbol(o) lwidth(medthick)) ///
    , ///
    yline(0) ///
    xtitle("Quantile p of sector-year markup distribution") ///
    ytitle("IV coefficient on Δ Chinese import penetration") ///
    xlabel(5(5)95, grid) ///
    legend(off)

restore



// China import pressure doesn't uniformly compress markups; it affects the hardest where market power is both (i) high (upper-tail firms) and (ii) protected by concentration (high CR4)!!






*--------------------
* PRELIMINARY TABLES
*--------------------

preserve

sort firm_id year
collapse(mean) dln_mu exit  Z_input llnsize lleverage lliquidity l_age l_exporter $g_poly2 ls_pre_filled isic4 post2016 (first) change_IP output_IV [aw=dom_sales], by(firm_id year)
tsset firm_id year

* Main IV regression
ivreghdfe exit (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) 

ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) 

ivreghdfe dln_mu (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) 

ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter $g_poly2 c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)

restore 







* Residual-based IV (2‑stage)
local y dln_mu 
local x change_IP
local z output_IV
local w Z_input llnsize lleverage lliquidity l_age l_exporter $g_poly2 c.ls_pre_filled##i.post2016
local fe1 isic4 year

reghdfe `y' `w', absorb(`fe1') resid(y_mu) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe1') resid(x_mu) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe1') resid(z_mu) vce(cluster isic4)

ivreg2 y_mu (x_mu = z_mu), nocons cluster(isic4) first
eststo iv_resid

* Wild bootstrap p-value (just store p)
boottest x_mu, cluster(isic4) reps(9999) seed(12345)
eststo iv_resid
estadd scalar p_wild = r(p)  // this works: p = 0.0185

restore





preserve

sort firm_id year
collapse(mean) dln_mu exit Z_input llnsize lleverage lliquidity l_age ///
         l_exporter $g_poly2 ls_pre_filled isic4 post2016 ///
         (first) change_IP output_IV [aw=dom_sales], by(firm_id year)
tsset firm_id year

*--- Store regressions + add diagnostics right after each
eststo clear

* (1) Exit
ivreghdfe exit ///
    (change_IP = output_IV) ///
    Z_input c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar N_g = e(N)
estadd scalar r2_g = e(r2)
estadd scalar F_first = e(first_first)
estadd local FE = "isic4"
estadd local Cluster = "isic4"
eststo exit
matrix list e(b)  // see all coefficient names
ereturn list      // confirm F_first exists

* (2) dln_mu w/ lagged controls
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input llnsize lleverage lliquidity l_age l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar N_g = e(N)
estadd scalar r2_g = e(r2)
estadd scalar F_first = e(first_first)
estadd local FE = "isic4"
estadd local Cluster = "isic4"
eststo mu_full

* (3) dln_mu no lagged controls
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar N_g = e(N)
estadd scalar r2_g = e(r2)
capture estadd scalar F_kp = e(widstat)
capture estadd scalar F_cd = e(cdf)
estadd scalar F_first = e(first_first)
estadd local FE = "isic4"
estadd local Cluster = "isic4"
eststo mu_base

* (4) dln_mu full + g_poly2
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input llnsize lleverage lliquidity l_age l_exporter $g_poly2 ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar N_g = e(N)
estadd scalar r2_g = e(r2)
estadd scalar F_first = e(first_first)
estadd local FE = "isic4"
estadd local Cluster = "isic4"
eststo mu_poly

*--- Export focused LaTeX table
esttab exit mu_base mu_full mu_poly using "$folder/tables/prelim_1.tex", ///
    replace ///
    keep(change_IP Z_input *ls_pre_filled#*) ///
    order(change_IP Z_input *ls_pre_filled#*) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Exit" "Revenue (base)" "Revenue (+ lags)" "Revenue (+ poly)") ///
    stats(N_g r2_g F_kp FE Cluster, ///
      fmt(0 3 0%9.2fc " " " ") ///
      labels("Observations" "R$^2$" "KP F-stat" "FE" "Cluster SE"))
 ///
    label booktabs fragment nogaps compress ///
    title("Firm Dynamics: IV Estimates") ///
    note("All columns include year FEs. Standard errors clustered by isic4.")


restore

eststo clear






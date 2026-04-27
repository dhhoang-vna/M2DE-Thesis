clear mata
capture log close
clear


log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\1 orbis_data.log", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

cd "$folder\RawData\Orbis"

*************************************
**** ORBIS/AMADEUS DATA CLEANING ****
*************************************

** 1. Clean the Bvd classification table

import delimited "TR_industry_classifications.csv", clear varnames(1)
save "$folder\Data\Orbis\TR_industry_classifications.dta", replace
destring nace_rev_2_core_code_4_digits_, gen(nace_num) force

gen nace2 = nace_rev_2_core_code_4_digits_

* Collapse to one row per firm
bysort bvd_id_number: keep if _n == 1

duplicates report bvd_id_number

save "$folder\Data\Orbis\industry_manuf_clean.dta", replace

** 2. Clean the main financial dataset and create the ready-to-use dataset

import delimited "$folder\RawData\Orbis\TR_global_financials_and_ratios_eur.csv", clear
save "$folder\Data\Orbis\TR_global_financials_and_ratios_eur.dta", replace

* Merge the cleaned industry file
merge m:1 bvd_id_number using "$folder\Data\Orbis\industry_manuf_clean.dta"

keep if _merge == 3
drop _merge 

replace nace2 = nace_rev_2_secondary_code_s_ if nace2 == "NA"

// Some firm data doesn't have NACE primary codes, so the secondary codes are used to reduce missing firms 

* Check for real duplicates (firm-year)
gen closing_date_clean = substr(closing_date, 1, 10)
gen closing_date_stata = date(closing_date_clean, "YMD")
gen year = year(closing_date_stata)
drop closing_date_clean closing_date_stata
tab year
summ year

duplicates report bvd_id_number year

* Remedy duplicates
tab consolidation_code
tab filing_type
tab accounting_practice
tab source_for_publicly_quoted_compa
tab closing_date

gen cons_priority = .
replace cons_priority = 1 if consolidation_code == "U1"
replace cons_priority = 2 if consolidation_code == "U2"
replace cons_priority = 3 if consolidation_code == "C1"
replace cons_priority = 4 if consolidation_code == "C2"

sort bvd_id_number year cons_priority
bysort bvd_id_number year: keep if _n == 1
drop cons_priority

duplicates report bvd_id_number year

// Notes: Duplicates were driven by consolidated vs unconsolidated filings within the same year.

save "$folder\Data\Orbis\orbis.dta", replace 

*-----------------------------------------
* Sectoral PPI (3-digit) as a deflator
*-----------------------------------------

import delimited "$folder\RawData\TR_PPI.csv", delimiter("|") clear

drop in 1/3

rename v1 indicator
rename v2 sector
rename v3 year
rename v4 jan
rename v5 feb
rename v6 mar
rename v7 apr
rename v8 may
rename v9 jun
rename v10 jul
rename v11 aug
rename v12 sep
rename v13 oct
rename v14 nov
rename v15 dec

replace indicator = indicator[_n-1] if missing(indicator) & !missing(sector)

destring year, replace

drop indicator 
drop in 1

gen sector_code = regexs(1) if regexm(sector, "^([0-9]+\.?[0-9]*)\.")

drop sector

gen long _order = _n
sort _order

gen long _blk = sum(sector_code!="")
bys _blk: replace sector_code = sector_code[1] if sector_code==""

save "$folder\Data\ppi_23.dta", replace

* Make the 3-digit PPI dataset
use "$folder\Data\ppi_23.dta", clear
drop if strpos(sector_code, ".")==0

gen nace3 = subinstr(sector_code, ".", "", .)

keep if year >= 2010 & year <= 2020
drop sector_code _order _blk v16

destring jan feb mar apr may jun jul aug sep oct nov dec, replace ignore(" ,")

egen ppi = rowmean(jan feb mar apr may jun jul aug sep oct nov dec)
drop jan feb mar apr may jun jul aug sep oct nov dec

destring nace3, replace
keep if nace3 >= 100 & nace3 < 340
tostring nace3, replace

save "$folder\Data\ppi_3.dta", replace

* Make the 2-digit PPI dataset
use "$folder\Data\ppi_23.dta", clear

keep if strpos(sector_code, ".") == 0

drop _order _blk v16

destring jan feb mar apr may jun jul aug sep oct nov dec, replace ignore(" ,")

egen ppi = rowmean(jan feb mar apr may jun jul aug sep oct nov dec)
drop jan feb mar apr may jun jul aug sep oct nov dec

rename sector_code nace2

destring nace2, replace
keep if nace2 >= 10 & nace2 < 34
tostring nace2, replace

save "$folder\Data\ppi_2.dta", replace

* Merge PPI with Orbis dataset
use "$folder\Data\ORBIS\orbis.dta", clear

// Numeric Firm ID
egen long firm_id = group(bvd_id_number)
label var firm_id "Numeric id from bvd_id_number"

replace nace2 = nace_rev_2_secondary_code_s_ if nace2 == "NA"

drop if nace2 == "NA"

gen str4 nace4 = substr("0000"+nace2, -4, 4)
gen str3 nace3 = substr(nace4,1,3)
gen str2 nace2d = substr(nace4,1,2)

merge m:1 year nace3 using "$folder\Data\ppi_3.dta"
destring nace4, replace
keep if nace4 >= 1000 & nace4 < 3400

rename nace4 nace4_num
rename nace2 nace4
rename nace2d nace2
rename ppi ppi_3

drop _merge

merge m:1 year nace2 using "$folder\Data\ppi_2.dta"
rename ppi ppi_2
replace ppi_3 = ppi_2 if missing(ppi_3)

gen byte ppi_miss = missing(ppi_3)

tab nace2 ppi_miss, row // NACE 33 missing

drop if missing(ppi_3)
drop ppi_2 _merge ppi_miss
rename ppi_3 ppi

save "$folder\Data\ORBIS\orbis_ppi.dta", replace

*-----------------------
* Mapping NACE2 - ISIC4 
*-----------------------

tostring nace4, replace
rename nace2 nace2d
rename nace4 nace2 

merge m:1 nace2 using "$folder\Data\Concordance\isic4_nace2.dta"

drop if _merge==2 
drop _merge
rename nace2 nace4
rename nace2d nace2


*****************************
**** FIRM-LEVEL OUTCOMES ****
*****************************

use "$folder\Data\Orbis\orbis_ppi.dta", clear

/*tab number_of_employees if manuf == 1

gen byte lobs = !missing(number_of_employees) & number_of_employees != "NA"

bys firm_id: egen byte anyL = max(lobs)
bys firm_id: egen shareL = mean(lobs)

tab anyL
sum shareL, detail

bys firm_id: gen byte firmtag = (_n==1)
sum shareL if firmtag & anyL==1, detail

bys firm_id: egen nL = total(lobs)
tab nL if firmtag, m
tab nL if firmtag & anyL==1, m */

* Firm age
sort bvd_id_number nace2 year
bysort bvd_id_number (year): gen first_year = year[1]
gen age = year - first_year + 1 //since 1984
gen byte young = (age<=5)

gen agebin = .
replace agebin = 1 if age<=2
replace agebin = 2 if inrange(age,3,5)
replace agebin = 3 if inrange(age,6,10)
replace agebin = 4 if age>=11
label define agebin 1 "0-2" 2 "3-5" 3 "6-10" 4 "11+"
label values agebin agebin

*// China import competition reallocates resources via selection (higher exit in exposed sectors), within-sector restructuring among survivors (tangible fixed assets, operating revenue turnover, EBIT margin, current ratio). To capture firm heterogeneity, firm size (baseline log assets), leverage, cash buffer are used.

*// Note: A reporting-selection diagnostic for each non-exit outcome. If this is flat, it's good. If not, we label the mechanism as "among reporting firms"
* gen byte y_obs = !missing(interest_cover_x_)   // example
* reghdfe y_obs Zout, absorb(nace_num year) vce(cluster nace_num)

** 1. FIRM EXIT

//based on panel disappearance and NACE change 

sort bvd_id_number year
by bvd_id_number: gen obs_next = (year[_n+1] == year + 1) //firm observed next year

by bvd_id_number: gen exit_gap = 0
by bvd_id_number: replace exit_gap = 1 if obs_next == 0 // firm disappears after this year

* For EXIT: disappearance for 2+ years
by bvd_id_number: gen future_obs_2yrs = 0
by bvd_id_number: replace future_obs_2yrs = 1 if (year[_n+2] == year + 2| year[_n+3] == year + 3)

gen exit1 = 0
replace exit1 = 1 if exit_gap == 1 & future_obs_2yrs == 0 

// alternative 
isid firm_id year, sort
xtset firm_id year

gen byte one = 1
gen byte seen_t1 = (F.one == 1) // observed in t+1
gen byte seen_t2 = (F2.one == 1) // observed in t+2
gen byte seen_t3 = (F3.one == 1) // observed in t+3

gen byte exit = (seen_t1==0 & seen_t2==0 & seen_t3==0)

summ year, meanonly
local maxy = r(max)
replace exit = . if year > `maxy' - 3

corr exit exit1
tab exit exit1, row col
tab year if exit!=exit1

gen byte samp1119 = inrange(year, 2011, 2019)

/*ivreghdfe Y ... if samp1119 & exit<., absorb... */


* 2. FINANCIAL OUTCOMES


// Competition shock, then margin squeeze, liquidity stress and debt-service stress, which lead to investment collapse and exit

// Numeric Firm ID
label var firm_id "Numeric id from bvd_id_number"

// CLEANING
local varlist operating_revenue_turnover_ costs_of_goods_sold tangible_fixed_assets intangible_fixed_assets ebit_margin_ gross_margin total_assets loans long_term_debt current_assets current_liabilities current_ratio_x_ liquidity_ratio_x_ working_capital interest_cover_x_ interest_paid cash_cash_equivalent

foreach var of local varlist {
    replace `var' = "" if `var' == "NA"
    destring `var', replace
}

gen turnover = operating_revenue_turnover_ / (ppi/100)
gen cogs = costs_of_goods_sold / (ppi/100)
gen tfa = tangible_fixed_assets / (ppi/100)
gen itfa = intangible_fixed_assets / (ppi/100)

* (1) Activity contraction: Change in operating revenue turnover

* Define manufacturing dummy
drop if nace4 == "NA"
destring nace4, replace
gen manuf = (nace4 >= 1000 & nace4< 3400)
tab manuf
tab nace4 if manuf == 1

tsset firm_id year
gen ln_rev = ln(operating_revenue_turnover_) if operating_revenue_turnover_>0
gen dln_rev = F.ln_rev - ln_rev //missing if t+1 not observed
label var dln_rev "Log change in revenue (t to t+1)"

* (2) Investment: Log change in tangible fixed assets

gen ln_tfa = ln(tfa) if tfa>0
gen dln_tfa = F.ln_tfa - ln_tfa //missing if t+1 not observed
label var dln_tfa "Log change in tangible fixed assets (t to t+1)"

* (3) Profitability squeeze: EBIT margin, gross margin

gen ebit_t1 =  F.ebit_margin_
label var ebit_t1 "EBIT margin at t+1"

gen gross_margin_t1 =  F.gross_margin_
label var gross_margin_t1 "Gross margin at t+1"

*----------------------------
* 3. DOMESTIC CONCENTRATION
*----------------------------

gen ctry = substr(bvd_id_number,1,2)
keep if ctry=="TR"
drop ctry

* 3.1. Domestic sales (nominal)

local varr export_revenue extr_and_other_revenue

foreach var of local varr {
    replace `var' = "" if `var' == "NA"
    destring `var', replace
}

gen dom_sales_1 = operating_revenue_turnover_ - export_revenue
gen dom_sales = dom_sales_1 / (ppi/100)


* 3.2. Compute within sector x year domestic market shares

gen dom_pos = (dom_sales>0 & dom_sales!=.) // drop nonpositive domestic sales for share calculation
 
bys isic4 year: egen total_sales = total(dom_sales) if dom_pos
gen share_sales = dom_sales / total_sales if dom_pos


* 3.3. Rank firms by domestic sales within sector-year

bys isic4 year: egen rank_sales = rank(-dom_sales) if dom_pos, unique

// Sum of shares for top 20 firms 
gen top20_share = share_sales if rank_sales<=20 & dom_pos
bys isic4 year: egen CR20_dom = total(top20_share)

// Sum of shares for top 10 firms 
gen top10_share = share_sales if rank_sales<=10 & dom_pos
bys isic4 year: egen CR10_dom = total(top10_share)

// HHI
gen s2 = share_sales if dom_pos
bys isic4 year: egen HHI_dom = total(s2)

// Firm count 
bys isic4 year: egen N_dom = total(dom_pos)

save "$folder\Data\ORBIS\orbis_ppi.dta", replace







************************************
**** CONTROLS AND HETEROGENEITY ****
************************************
use "$folder\Data\Orbis\orbis_ppi.dta", clear


** 1. Firm age (years since first observation in panel)


** 2. Size measures
tsset firm_id year

bysort firm_id (year): egen assets = min(cond(!missing(total_assets), total_assets, .)) // Baseline assets (first non-missing)

gen lnSize = ln(total_assets) if assets>0
gen byte lnSize_miss = missing(lnSize)

* Build endogenous interaction terms
*gen Zout_lnA0   = Zout * lnA0
*gen Zout_miss   = Zout * lnA0_miss

* Instruments
*gen IV_lnA0     = IV * lnA0
*gen IV_miss     = IV * lnA0_miss

* 2SLS with two endogenous regressors: Zout and Zout_lnA0 (and optionally Zout_miss)
*ivreghdfe Y_lead ///
    (Zout Zout_lnA0 Zout_miss = IV IV_lnA0 IV_miss) ///
    Zin lnA0 lnA0_miss  ///
    X1 X2 X3, ///
    absorb(nace4 year) vce(cluster nace4)

	
** 3. Financial fragility mechanisms	
* 3.1. Leverage (lagged)

gen leverage = (loans + long_term_debt) / total_assets if total_assets>0

tsset firm_id year
gen l_leverage = L.leverage

bysort nace2 year: egen leverage_med_jt = median(l_leverage)

gen byte high_leverage = (l_leverage > leverage_med_jt) if !missing(l_leverage, leverage_med_jt) // create only when both lagged leverage and median leverage exist


*// Does import shock tighten liquidity  and working capital management?

* 3.2. Current ratio and Liquidity ratio

tsset firm_id year

gen curr_ratio = current_assets / current_liabilities if current_liabilities>0
gen curr_ratio_lag = L.curr_ratio 
label var curr_ratio_lag "Current ratio (t-1)"


gen liq_ratio_lag = L.liquidity_ratio_x_
label var liq_ratio_lag  "Liquidity ratio (t-1)"

* 3.3. Working-capital to assets (lagged)


gen wc_to_assets = working_capital / total_assets if total_assets>0

tsset firm_id year
gen wc_to_assets_lag = L.wc_to_assets
label var wc_to_assets_lag "Working capital / assets (t-1)"


* 3.4. Interest coverage/interest burden


gen int_burden = interest_paid / operating_revenue_turnover_ if interest_paid>=0 & operating_revenue_turnover_>0
tsset firm_id year
gen int_burden_lag = L.int_burden
gen icov_lag = L.interest_cover_x_

label var icov_lag "Interest coverage (t-1)"
label var int_burden_lag "Interest paid / revenue (t-1)"


* 3.5. Cash buffer


gen cash_to_assets = cash_cash_equivalent / total_assets 
tsset firm_id year
gen cash_to_assets_lag = L.cash_to_assets
label var cash_to_assets_lag "Cash & equivalents / assets (t-1)"

/* Quick sanity: how many usable obs for each constructed variable?

foreach y in dln_rev_t_t1 dln_tfa_t_t1 ebit_margin_t1 gross_margin_t1 ///
          icov_lag int_burden_lag curr_ratio_lag wc_to_assets_lag cash_to_assets_lag {
    quietly count if !missing(`y')
    di as txt "`y': " as res r(N) as txt " non-missing"
}

// Check missing data 
local vars tangible_fixed_assets total_assets working_capital net_current_assets current_ratio_x_ interest_cover_x_ ebit_margin_ operating_revenue_turnover_ cash_cash_equivalent shareholders_funds interest_paid gross_margin_ profit_margin_ estimated_operating_revenue liquidity_ratio_x_

di as txt "Variable   N   Missing   Missing%"
foreach v of local vars {
    quietly count
    local N = r(N)

    capture confirm string variable `v'
    if !_rc {
        quietly count if missing(`v') | inlist(lower(trim(`v')), "na","n/a","NA","")
    }
    else {
        quietly count if missing(`v')
    }
    local M = r(N)
    di as txt "`v'  " %9.0f `N' "  " %9.0f `M' "  " %6.2f (100*`M'/`N')
} */

***** Saving dataset
local idvars   bvd_id_number firm_id year nace4 nace3 nace2 nace_num manuf
local demo     age young agebin
local outcomes exit exit_lead dln_rev dln_tfa ebit_t1 gross_margin_t1
local size     lnSize lnSize_miss
local mech     l_leverage high_leverage curr_ratio_lag liq_ratio_lag wc_to_assets_lag ///
               icov_lag int_burden_lag cash_to_assets_lag

keep `idvars' `demo' `outcomes' `size' `mech' 

isid firm_id year, sort
compress
order bvd_id_number firm_id year nace4 manuf age young agebin, first


save "$folder\Data\Orbis\orbis_ppi.dta", replace

 

log close













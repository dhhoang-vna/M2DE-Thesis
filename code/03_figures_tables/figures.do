capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
clear mata
capture log close
clear


log using "$LOGS\3 figures.log", replace

global folder "$REPLICATION_ROOT"


*============================================================*
* 1. Context figure: Chinese import penetration, 2011--2019
*============================================================*

use "$DATA_DERIVED\BACI\IP.dta", clear

* Basic checks
describe
summarize IP year

* Keep relevant years
keep if inrange(year, 2011, 2019)

* Clean impossible plotting values
drop if missing(IP, year)
drop if IP < 0

* If IP is a ratio, values above 1 are suspicious but keep for audit
gen byte ip_above_05 = IP > 0.5 if !missing(IP)
gen byte ip_above_1  = IP > 1   if !missing(IP)

*------------------------------------------------------------*
* Audit 1: year-level diagnostics
*------------------------------------------------------------*

preserve
collapse ///
    (count) n_sectors = IP ///
    (mean)  mean_IP = IP ///
    (p25)   p25_IP = IP ///
    (p50)   median_IP = IP ///
    (p75)   p75_IP = IP ///
    (p90)   p90_IP = IP ///
    (max)   max_IP = IP ///
    (sum)   n_above_05 = ip_above_05 ///
            n_above_1  = ip_above_1, ///
    by(year)

export delimited using "$OUTPUT_TABLES\audit_china_ip_by_year.csv", replace
save "$DATA_DERIVED\BACI\china_ip_context_plotdata.dta", replace
restore

*------------------------------------------------------------*
* Audit 2: top sector-year observations
*------------------------------------------------------------*

preserve
gsort -IP
keep year isic4 IP
capture confirm variable imports_china
if !_rc keep year isic4 IP imports_china
capture confirm variable imports_world
if !_rc keep year isic4 IP imports_china imports_world
capture confirm variable exports_world
if !_rc keep year isic4 IP imports_china imports_world exports_world
capture confirm variable output
if !_rc keep year isic4 IP imports_china imports_world exports_world output

keep in 1/10
export delimited using "$OUTPUT_TABLES\audit_china_ip_top_sector_years.csv", replace
restore

*------------------------------------------------------------*
* Main collapsed plotting data
*------------------------------------------------------------*

collapse ///
    (mean) mean_IP = IP ///
    (p25)  p25_IP = IP ///
    (p50)  median_IP = IP ///
    (p75)  p75_IP = IP, ///
    by(year)

label variable mean_IP   "Mean"
label variable median_IP "Median"
label variable p25_IP    "p25"
label variable p75_IP    "p75"

*------------------------------------------------------------*
* Main figure: p25-p75 band + mean + median
*------------------------------------------------------------*

twoway ///
    (rarea p25_IP p75_IP year, sort color(gs13%70) lcolor(none)) ///
    (line mean_IP year, sort lcolor(black) lwidth(medthick)) ///
    (line median_IP year, sort lcolor(gs6) lpattern(dash) lwidth(medthick)), ///
    title("Chinese import penetration across Turkish manufacturing sectors", size(medsmall)) ///
    subtitle("ISIC4 sector-year distribution, 2011--2019", size(small)) ///
    ytitle("China import penetration", size(small)) ///
    xtitle("") ///
    xlabel(2011(1)2019, labsize(small)) ///
    ylabel(, angle(horizontal) labsize(small) grid) ///
    legend(order(2 "Mean" 3 "Median" 1 "p25--p75") ///
           rows(1) size(small) position(6)) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    scheme(s2mono)

graph export "$OUTPUT_FIGURES\fig_china_ip_context.pdf", as(pdf) replace
graph export "$OUTPUT_FIGURES\fig_china_ip_context.png", as(png) width(2400) replace
graph export "$OUTPUT_FIGURES\fig_china_ip_context.jpg", as(jpg) quality(100) replace


*============================================================*
* 2. Robustness figure excluding IP > 1, if such values exist
*============================================================*

use "$DATA_DERIVED\BACI\IP.dta", clear
keep if inrange(year, 2011, 2019)
drop if missing(IP, year)
drop if IP < 0
drop if IP > 1

collapse ///
    (mean) mean_IP = IP ///
    (p25)  p25_IP = IP ///
    (p50)  median_IP = IP ///
    (p75)  p75_IP = IP ///
    (p10)  p10_IP = IP ///
    (p90)  p90_IP = IP, ///
    by(year)

gen iqr_IP = p75_IP - p25_IP
list year mean_IP median_IP p25_IP p75_IP iqr_IP, sep(0)

twoway ///
    (rarea p25_IP p75_IP year, sort fcolor(gs12) lcolor(gs10) lwidth(vthin)) ///
    (line mean_IP year, sort lcolor(black) lpattern(solid) lwidth(medthick)) ///
    (line median_IP year, sort lcolor(gs6) lpattern(dash) lwidth(medthick)), ///
    ytitle("China import penetration", size(small)) ///
    xtitle("") ///
    xlabel(2011(1)2019, labsize(small)) ///
    ylabel(0(.02).10, angle(horizontal) labsize(small) grid format(%4.2f)) ///
    legend(order(2 "Mean" 3 "Median" 1 "p25-p75") ///
           rows(1) size(small) position(6) region(lcolor(none))) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    scheme(s2mono)

graph export "$OUTPUT_FIGURES\fig_china_ip_context_trimmed.pdf", as(pdf) replace
graph export "$OUTPUT_FIGURES\fig_china_ip_context_trimmed.png", as(png) width(2400) replace


list year p25_IP median_IP p75_IP mean_IP, sep(0)

*============================================================*
* 3. Distribution of change in import penetration, appendix only
*============================================================*

use "$DATA_DERIVED\data_ready_mec.dta", clear

keep if inrange(year, 2011, 2019)
drop if missing(change_IP, isic4, year)

* If firm-level data, first collapse to sector-year
collapse (mean) change_IP, by(isic4 year)

collapse ///
    (p10) p10_change_IP = change_IP ///
    (p50) p50_change_IP = change_IP ///
    (p90) p90_change_IP = change_IP, ///
    by(year)

twoway ///
    (line p10_change_IP year, sort lcolor(gs8) lpattern(dash)) ///
    (line p50_change_IP year, sort lcolor(black) lwidth(medthick)) ///
    (line p90_change_IP year, sort lcolor(gs8) lpattern(dash)), ///
    title("Distribution of changes in Chinese import penetration", size(medsmall)) ///
    subtitle("ISIC4 sector-year distribution, 2011--2019", size(small)) ///
    ytitle("Change in China import penetration", size(small)) ///
    xtitle("") ///
    xlabel(2011(1)2019, labsize(small)) ///
    ylabel(, angle(horizontal) labsize(small) grid) ///
    legend(order(1 "p10" 2 "Median" 3 "p90") rows(1) size(small) position(6)) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    scheme(s2mono)

graph export "$OUTPUT_FIGURES\change_IP_p10_90.pdf", as(pdf) replace
graph export "$OUTPUT_FIGURES\change_IP_p10_90.png", as(png) width(2400) replace
graph export "$OUTPUT_FIGURES\change_IP_p10_90.jpg", as(jpg) quality(100) replace

*--------------------------------
* Lorenz curve of market shares
*--------------------------------

use "$DATA_DERIVED\data_ready_mec.dta", clear
sort share_sales
gen firm = _n 
gen cum_firms = firm/_N
gen cum_sales = sum(share_sales)
replace cum_sales = cum_sales / cum_sales[_N]

twoway ///
(line cum_sales cum_firms, sort lwidth(medthick)) ///
(function y=x, range(0 1) lpattern(dash)), ///
xlabel(0(.2)1) ylabel(0(.2)1) ///
xtitle("Cumulative share of firms") ///
ytitle("Cumulative share of domestic sales")

graph export "$OUTPUT_FIGURES\lorenz_1.jpg", as(jpg) replace


*=======================
* Summary statistics
*=======================

*------- Main text

use "$DATA_DERIVED\data_ready.dta", clear
capture confirm variable exporter
if _rc gen byte exporter = (export_revenue>0) if !missing(export_revenue)

cap drop sample_main
gen sample_main = inrange(year, 2011, 2019)

* keep obs with baseline variables observed
replace sample_main = 0 if missing(dln_mu, exit, ebit_margin_, lnSize, leverage, liquidity_ratio_x_, age, exporter, change_IP, output_IV, Z_input, ls_pre_filled, HHI_dom)

* label
label variable dln_mu              "Markup adjustment (\$\Delta \ln \mu_{ijt}\$)"
label variable exit                "Exit"
label variable ebit_margin_        "EBIT margin"
label variable lnSize              "Log firm size"
label variable leverage            "Leverage"
label variable liquidity_ratio_x_  "Liquidity ratio"
label variable age                 "Firm age"
label variable exporter            "Exporter dummy"

label variable change_IP           "Change in Chinese import penetration (\$\Delta IP_{jt}\$)"
label variable output_IV           "Output-competition IV"
label variable Z_input             "Input-supply control"
label variable ls_pre_filled       "Pre-period labor share"
label variable HHI_dom                 "HHI"

* panel A: firm-level variables
eststo clear

estpost tabstat dln_mu exit ebit_margin_ lnSize leverage liquidity_ratio_x_ age exporter ///
	if sample_main == 1, statistics(n mean sd p50 min max) columns(statistics)
	
eststo mainA

* panel B: sector-year variables 
preserve 
keep if sample_main == 1
collapse (mean) change_IP output_IV Z_input ls_pre_filled HHI_dom, by(isic4 year)

estpost tabstat change_IP output_IV Z_input ls_pre_filled HHI_dom, statistics(n mean sd p50 min max) columns(statistics)

eststo mainB
restore

* export table 
esttab mainA mainB using "$OUTPUT_TABLES\stats_main.tex", ///
    cells("count(fmt(0)) mean(fmt(3)) sd(fmt(3)) p50(fmt(3)) min(fmt(3)) max(fmt(3))") ///
    mtitle("Panel A: Firm-level" "Panel B: Sector-level") ///
    nonumber noobs replace ///
    title("Summary Statistics")
	
	
*--------- Sample structure

* firm
cap drop tag_firm 
egen tag_firm = tag(firm_id) if sample_main == 1
count if tag_firm == 1
local n_firms = r(N)

* firm-year
count if sample_main == 1
local n_firmyear = r(N)

* sector-year
cap drop tag_sector
egen tag_sector = tag(isic4) if sample_main == 1
count if tag_sector == 1
local n_sectors = r(N)

display "Number of firms = `n_firms'"
display "Number of firm-years = `n_firmyear'"
display "Number of sectors = `n_sectors'"
display "Period covered = 2011--2019"


*===============
* First stage
*===============

use "$DATA_DERIVED\data_ready_robust.dta", clear
*----- first stage sample
cap drop sample_fs
gen sample_fs = inrange(year, 2011, 2019)
replace sample_fs = 0 if missing(change_IP, output_IV, Z_input, ls_pre_filled, post2016, isic4, year)

drop if missing(firm_id) | missing(year) | missing(isic4)
xtset firm_id year

capture confirm variable llnsize
if _rc gen llnsize = L.lnSize
capture confirm variable lleverage
if _rc gen lleverage = L.leverage
capture confirm variable lliquidity
if _rc gen lliquidity = L.liquidity_ratio_x_
capture confirm variable l_age
if _rc gen l_age = L.age
capture confirm variable l_exporter
if _rc gen l_exporter = L.exporter

replace sample_fs = 0 if missing(llnsize, lleverage, lliquidity, l_age, l_exporter, change_IP, output_IV, Z_input, ls_pre_filled, post2016, isic4, year)

* sector and observations
cap drop tag_sector_fs
egen tag_sector_fs = tag(isic4) if sample_fs == 1
count if tag_sector_fs == 1
local n_sectors = r(N)

count if sample_fs == 1
local n_obs = r(N)

* correlation output and input shocks
corr output_IV Z_input if sample_fs==1
matrix C = r(C)
local corr_oz = C[1,2]

display "Number of sectors = `n_sectors'"
display "Observations = `n_obs'"
display "Corr(output_IV, Z_input) = `corr_oz'"


*------- First stage regressions

eststo clear

* Column 1
reghdfe change_IP output_IV Z_input c.ls_pre_filled##i.post2016 ///
    if sample_fs == 1, absorb(isic4 year) vce(cluster isic4)
eststo fs1

test output_IV
local F_excl1 = r(F)

cap drop tag_sector_fs
egen tag_sector_fs = tag(isic4) if e(sample)
count if tag_sector_fs == 1
local n_sectors = r(N)

count if e(sample)
local n_obs = r(N)

corr output_IV Z_input if e(sample)
matrix C = r(C)
local corr_oz = C[1,2]

estadd scalar F_excl    = `F_excl1'   : fs1
estadd scalar N_sectors = `n_sectors' : fs1
estadd scalar Corr_OZ   = `corr_oz'   : fs1
estadd scalar N_obs     = `n_obs'     : fs1

* Column 2
reghdfe change_IP output_IV Z_input ///
    llnsize lleverage lliquidity l_age l_exporter ///
    c.ls_pre_filled##i.post2016 ///
    if sample_fs == 1, absorb(isic4 year) vce(cluster isic4)
eststo fs2

test output_IV
local F_excl2 = r(F)

cap drop tag_sector_fs
egen tag_sector_fs = tag(isic4) if e(sample)
count if tag_sector_fs == 1
local n_sectors2 = r(N)

count if e(sample)
local n_obs2 = r(N)

corr output_IV Z_input if e(sample)
matrix C = r(C)
local corr_oz2 = C[1,2]

estadd scalar F_excl    = `F_excl2'    : fs2
estadd scalar N_sectors = `n_sectors2' : fs2
estadd scalar Corr_OZ   = `corr_oz2'   : fs2
estadd scalar N_obs     = `n_obs2'     : fs2

* export table
estadd local LagCtrls "No"  : fs1
estadd local LagCtrls "Yes" : fs2
estadd local SectorFE "Yes" : fs1
estadd local SectorFE "Yes" : fs2
estadd local YearFE   "Yes" : fs1
estadd local YearFE   "Yes" : fs2

esttab fs1 fs2 using "$OUTPUT_TABLES\first_stage_diagnostics.tex", ///
    keep(output_IV Z_input) ///
    order(output_IV Z_input) ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    stats(LagCtrls SectorFE YearFE F_excl Corr_OZ N_sectors N, ///
        fmt(0 0 0 2 3 0 0) ///
        labels("Lagged firm controls" ///
               "Sector FE" ///
               "Year FE" ///
               "Excluded-instrument F-stat" ///
               "Corr.($Z^{Output}_{jt}, Z^{Input}_{jt}$)" ///
               "Number of sectors" ///
               "Observations")) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitle("Parsimonious" "Baseline") ///
    replace label nonumber ///
    title("First Stage and Identification Diagnostics")


*------------------------------------
* Number of firms over time
*------------------------------------
use "$DATA_DERIVED\data_ready_mec.dta", clear
keep if inrange(year, 2011, 2019)
bysort year firm_id: gen byte tag_firm_year = _n == 1
collapse (sum) n_firms = tag_firm_year, by(year)

twoway line n_firms year, sort ///
    ytitle("Number of firms") ///
    xtitle("Year") ///
    lwidth(medthick)

graph export "$OUTPUT_FIGURES\number_firms_over_time.jpg", as(jpg) replace

*------------------------------------
* Distribution of sector size
*------------------------------------
use "$DATA_DERIVED\data_ready_mec.dta", clear
keep if inrange(year, 2011, 2019)
bysort isic4 year firm_id: gen byte tag_firm_sector = _n == 1
bysort isic4 year: egen sector_size = total(tag_firm_sector)
bysort isic4 year: keep if _n == 1

histogram sector_size, discrete percent ///
    ytitle("Percent") ///
    xtitle("Number of firms in sector-year") ///
    fcolor(gs12) lcolor(black)

graph export "$OUTPUT_FIGURES\sector_size_distribution.jpg", as(jpg) replace




/***********************************************************************
CONTEXT FIGURES: LORENZ, CR4/HHI, AND CHINA-IP Ã— CONCENTRATION
***********************************************************************/

cap mkdir "$OUTPUT_FIGURES"
cap mkdir "$OUTPUT_TABLES"

set scheme s1color

/***********************************************************************
1. BEAUTIFIED LORENZ CURVE
Important: share_sales is usually a within-sector-year share.
So this Lorenz curve is a pooled distribution of firm-sector-year sales shares,
not literally the aggregate manufacturing-wide sales distribution.
***********************************************************************/

use "$DATA_DERIVED\data_ready_mec.dta", clear

keep if !missing(isic4, year, share_sales)
drop if share_sales < 0

* Normalize inside sector-year, in case shares do not sum exactly to 1
bys isic4 year: egen double tot_share_jt = total(share_sales)
drop if missing(tot_share_jt) | tot_share_jt <= 0
gen double sh_jt = share_sales / tot_share_jt

sort sh_jt
gen long firm_rank = _n
gen double cum_firms = firm_rank / _N
gen double cum_sales = sum(sh_jt)
replace cum_sales = cum_sales / cum_sales[_N]

* Gini coefficient from Lorenz curve
gen double L_lag = cond(_n == 1, 0, cum_sales[_n-1])
gen double F_lag = cond(_n == 1, 0, cum_firms[_n-1])
gen double trap2 = (cum_sales + L_lag) * (cum_firms - F_lag)
quietly summarize trap2, meanonly
local gini = 1 - r(sum)
local gini_txt : display %4.3f `gini'
local Nobs : display %12.0fc _N

twoway ///
    (line cum_sales cum_firms, sort lcolor(navy) lwidth(medthick)) ///
    (function y=x, range(0 1) lcolor(gs10) lpattern(dash) lwidth(medium)), ///
    xlabel(0(.2)1, labsize(small) grid glcolor(gs14)) ///
    ylabel(0(.2)1, labsize(small) grid glcolor(gs14)) ///
    xtitle("Cumulative share of firm-sector-year observations", size(medsmall)) ///
    ytitle("Cumulative share of within-sector domestic sales", size(medsmall)) ///
    legend(order(1 "Lorenz curve" 2 "45-degree equality line") ///
           pos(6) row(1) ring(1) size(small) region(lcolor(none))) ///
    graphregion(color(white)) ///
    plotregion(color(white) margin(zero))

graph export "$OUTPUT_FIGURES\lorenz_sales_share_journal.pdf", replace
graph export "$OUTPUT_FIGURES\lorenz_sales_share_journal.png", width(2400) replace


/***********************************************************************
Optional: true manufacturing-wide Lorenz using domestic sales, if dom_sales exists.
This is cleaner if you want the caption "domestic sales among firms".
***********************************************************************/

capture confirm variable dom_sales
if !_rc {

    use "$DATA_DERIVED\data_ready_mec.dta", clear
    keep if !missing(firm_id, dom_sales)
    keep if dom_sales > 0

    * Choose one benchmark year to avoid counting the same firm repeatedly.
    * Change 2011 if you prefer another pre-period year.
    keep if year == 2011

    collapse (sum) dom_sales, by(firm_id)

    sort dom_sales
    gen long firm_rank = _n
    gen double cum_firms = firm_rank / _N
    gen double cum_sales = sum(dom_sales)
    replace cum_sales = cum_sales / cum_sales[_N]

    gen double L_lag = cond(_n == 1, 0, cum_sales[_n-1])
    gen double F_lag = cond(_n == 1, 0, cum_firms[_n-1])
    gen double trap2 = (cum_sales + L_lag) * (cum_firms - F_lag)
    quietly summarize trap2, meanonly
    local gini = 1 - r(sum)
    local gini_txt : display %4.3f `gini'
    local Nobs : display %12.0fc _N

    twoway ///
        (line cum_sales cum_firms, sort lcolor(navy) lwidth(medthick)) ///
        (function y=x, range(0 1) lcolor(gs10) lpattern(dash) lwidth(medium)), ///
        xlabel(0(.2)1, labsize(small) grid glcolor(gs14)) ///
        ylabel(0(.2)1, labsize(small) grid glcolor(gs14)) ///
        xtitle("Cumulative share of firms", size(medsmall)) ///
        ytitle("Cumulative share of domestic sales", size(medsmall)) ///
        legend(order(1 "Lorenz curve" 2 "45-degree equality line") ///
               pos(6) row(1) ring(1) size(small) region(lcolor(none))) ///
        graphregion(color(white)) ///
        plotregion(color(white) margin(zero))

    graph export "$OUTPUT_FIGURES\lorenz_domestic_sales_2011.pdf", replace
    graph export "$OUTPUT_FIGURES\lorenz_domestic_sales_2011.png", width(2400) replace
}


/***********************************************************************
1. REBUILD SECTOR-YEAR CONCENTRATION WITH THIN-CELL FILTER
***********************************************************************/

use "$DATA_DERIVED\data_ready_mec.dta", clear

keep if !missing(isic4, year, share_sales)
drop if share_sales < 0

bys isic4 year: egen double tot_share_jt = total(share_sales)
drop if missing(tot_share_jt) | tot_share_jt <= 0

gen double sh_jt = share_sales / tot_share_jt

gsort isic4 year -sh_jt
by isic4 year: gen int rank_jt = _n

by isic4 year: egen double CR4 = total(cond(rank_jt <= 4, sh_jt, 0))
gen double sh2 = sh_jt^2
by isic4 year: egen double HHI = total(sh2)
by isic4 year: egen int n_firms_jt = count(sh_jt)

by isic4 year: keep if _n == 1
keep isic4 year CR4 HHI n_firms_jt

label var CR4 "Four-firm concentration ratio"
label var HHI "Herfindahl-Hirschman index"
label var n_firms_jt "Number of observed firms in sector-year"

tempfile concentration
save `concentration', replace


/***********************************************************************
2. CONCENTRATION SUMMARY: FILTER THIN CELLS
Main text version: require at least 10 observed firms per sector-year.
***********************************************************************/

use `concentration', clear

keep if n_firms_jt >= 10
keep if inrange(year, 2011, 2019)

foreach v in CR4 HHI {
    quietly summarize `v', detail
    scalar mean_`v' = r(mean)
    scalar p50_`v'  = r(p50)
    scalar p75_`v'  = r(p75)
    scalar p90_`v'  = r(p90)
}

clear
set obs 8

gen str5 measure = ""
gen byte stat_id = .
gen str8 stat = ""
gen double value = .

replace measure = "CR4" in 1/4
replace measure = "HHI" in 5/8

replace stat_id = 1 in 1
replace stat_id = 2 in 2
replace stat_id = 3 in 3
replace stat_id = 4 in 4
replace stat_id = 1 in 5
replace stat_id = 2 in 6
replace stat_id = 3 in 7
replace stat_id = 4 in 8

replace stat = "Mean"   if stat_id == 1
replace stat = "Median" if stat_id == 2
replace stat = "p75"    if stat_id == 3
replace stat = "p90"    if stat_id == 4

replace value = scalar(mean_CR4) in 1
replace value = scalar(p50_CR4)  in 2
replace value = scalar(p75_CR4)  in 3
replace value = scalar(p90_CR4)  in 4

replace value = scalar(mean_HHI) in 5
replace value = scalar(p50_HHI)  in 6
replace value = scalar(p75_HHI)  in 7
replace value = scalar(p90_HHI)  in 8

gen double x = stat_id + cond(measure == "CR4", -0.16, 0.16)
format value %4.3f

twoway ///
    (bar value x if measure == "CR4", ///
        barwidth(0.28) fcolor(navy*0.75) lcolor(navy)) ///
    (bar value x if measure == "HHI", ///
        barwidth(0.28) fcolor(maroon*0.65) lcolor(maroon)) ///
    (scatter value x if measure == "CR4", ///
        msymbol(none) mlabel(value) mlabpos(12) mlabsize(vsmall) mlabcolor(navy)) ///
    (scatter value x if measure == "HHI", ///
        msymbol(none) mlabel(value) mlabpos(12) mlabsize(vsmall) mlabcolor(maroon)), ///
    xlabel(1 "Mean" 2 "Median" 3 "p75" 4 "p90", labsize(small)) ///
    ylabel(0(.2)1, labsize(small) grid glcolor(gs14)) ///
    ytitle("Index value", size(medsmall)) ///
    xtitle("") ///
    legend(order(1 "CR4" 2 "HHI") pos(6) row(1) ring(1) size(small) region(lcolor(none))) ///
    graphregion(color(white)) plotregion(color(white))

graph export "$OUTPUT_FIGURES\concentration_summary_CR4_HHI_filtered.pdf", replace
graph export "$OUTPUT_FIGURES\concentration_summary_CR4_HHI_filtered.png", width(2400) replace

export delimited using "$OUTPUT_TABLES\concentration_summary_CR4_HHI_filtered.csv", replace


/***********************************************************************
3. CHINA IMPORT PENETRATION VARIABLE
***********************************************************************/

use "$DATA_DERIVED\data_ready_mec.dta", clear

local ipvar ""
foreach cand in china_ip China_IP chn_ip ip_china IP_china import_penetration ///
                china_import_penetration chn_import_pen IP {
    capture confirm variable `cand'
    if !_rc & "`ipvar'" == "" local ipvar "`cand'"
}

if "`ipvar'" == "" {
    di as error "No China import-penetration level variable detected."
    di as error "Manually set local ipvar to the correct variable name."
    exit 111
}

di as text "Using China IP variable: `ipvar'"

keep isic4 year `ipvar'
drop if missing(isic4, year, `ipvar')
bys isic4 year: keep if _n == 1

tempfile china_ip
save `china_ip', replace


/***********************************************************************
4. BETTER OVERLAY: CHINA IP PATHS BY PRE-PERIOD CONCENTRATION TERCILE
This is the clean graph for context.
***********************************************************************/

use `concentration', clear
merge 1:1 isic4 year using `china_ip', keep(match) nogen

* Keep usable sample
keep if inrange(year, 2011, 2019)

* Pre-period concentration: use 2011--2013
bys isic4: egen double CR4_pre = mean(cond(inrange(year, 2011, 2013) & n_firms_jt >= 10, CR4, .))
bys isic4: egen double HHI_pre = mean(cond(inrange(year, 2011, 2013) & n_firms_jt >= 10, HHI, .))

* CR4 terciles
xtile CR4_tercile = CR4_pre if !missing(CR4_pre), nq(3)
label define CR4terc 1 "Low pre-period CR4" 2 "Middle pre-period CR4" 3 "High pre-period CR4"
label values CR4_tercile CR4terc

preserve
    keep if !missing(CR4_tercile, `ipvar')

    collapse ///
        (mean) mean_ip=`ipvar' ///
        (p50)  med_ip=`ipvar', ///
        by(year CR4_tercile)

    twoway ///
        (line mean_ip year if CR4_tercile == 1, lcolor(navy) lwidth(medthick)) ///
        (line mean_ip year if CR4_tercile == 2, lcolor(maroon) lpattern(dash) lwidth(medthick)) ///
        (line mean_ip year if CR4_tercile == 3, lcolor(dkgreen) lpattern(shortdash) lwidth(medthick)), ///
        xlabel(2011(1)2019, labsize(small) grid glcolor(gs14)) ///
        ylabel(, labsize(small) grid glcolor(gs14)) ///
        ytitle("Mean China import penetration", size(medsmall)) ///
        xtitle("") ///
        title("Chinese import penetration by pre-period concentration", size(medium)) ///
        subtitle("Sectors grouped by 2011--2013 CR4 terciles", size(small)) ///
        legend(order(1 "Low CR4" 2 "Middle CR4" 3 "High CR4") ///
               pos(6) row(1) ring(1) size(small) region(lcolor(none))) ///
        graphregion(color(white)) plotregion(color(white))

    graph export "$OUTPUT_FIGURES\china_ip_by_pre_CR4_tercile.pdf", replace
    graph export "$OUTPUT_FIGURES\china_ip_by_pre_CR4_tercile.png", width(2400) replace
restore


/***********************************************************************
5. SAME OVERLAY USING HHI TERCILES
***********************************************************************/

xtile HHI_tercile = HHI_pre if !missing(HHI_pre), nq(3)
label define HHIterc 1 "Low pre-period HHI" 2 "Middle pre-period HHI" 3 "High pre-period HHI"
label values HHI_tercile HHIterc

preserve
    keep if !missing(HHI_tercile, `ipvar')

    collapse ///
        (mean) mean_ip=`ipvar' ///
        (p50)  med_ip=`ipvar', ///
        by(year HHI_tercile)

    twoway ///
        (line mean_ip year if HHI_tercile == 1, lcolor(navy) lwidth(medthick)) ///
        (line mean_ip year if HHI_tercile == 2, lcolor(maroon) lpattern(dash) lwidth(medthick)) ///
        (line mean_ip year if HHI_tercile == 3, lcolor(dkgreen) lpattern(shortdash) lwidth(medthick)), ///
        xlabel(2011(1)2019, labsize(small) grid glcolor(gs14)) ///
        ylabel(, labsize(small) grid glcolor(gs14)) ///
        ytitle("Mean China import penetration", size(medsmall)) ///
        xtitle("") ///
        title("Chinese import penetration by pre-period concentration", size(medium)) ///
        subtitle("Sectors grouped by 2011--2013 HHI terciles", size(small)) ///
        legend(order(1 "Low HHI" 2 "Middle HHI" 3 "High HHI") ///
               pos(6) row(1) ring(1) size(small) region(lcolor(none))) ///
        graphregion(color(white)) plotregion(color(white))

    graph export "$OUTPUT_FIGURES\china_ip_by_pre_HHI_tercile.pdf", replace
    graph export "$OUTPUT_FIGURES\china_ip_by_pre_HHI_tercile.png", width(2400) replace
restore
















 

log close
 
 
 
 
 
 
 
 
 
 
 
 
 



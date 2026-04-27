clear mata
capture log close
clear

log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\5.2_import_control", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

*==================================================================
*Import value by year*sector of Turkey from China (2000-2004)
*==================================================================

**** Year 2000
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2000_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_TR_2000.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\hs6_tr_2000.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_tr_2000.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_tr_2000.dta", replace

use "$folder\Data\BACI\CHN_TR_2000.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_tr_2000.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_TR_M_2000.dta", replace


**** Year 2001
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2001_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_TR_2001.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\hs6_tr_2001.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_tr_2001.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_tr_2001.dta", replace

use "$folder\Data\BACI\CHN_TR_2001.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_tr_2001.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_TR_M_2001.dta", replace


**** Year 2004
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2004_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_TR_2004.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\hs6_tr_2004.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_tr_2004.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_tr_2004.dta", replace

use "$folder\Data\BACI\CHN_TR_2004.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_tr_2004.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_TR_M_2004.dta", replace


**** Year 2002
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2002_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_TR_2002.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\hs6_tr_2002.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_tr_2002.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_tr_2002.dta", replace

use "$folder\Data\BACI\CHN_TR_2002.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_tr_2002.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_TR_M_2002.dta", replace


**** Year 2003
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2003_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_TR_2003.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\hs6_tr_2003.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_tr_2003.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_tr_2003.dta", replace

use "$folder\Data\BACI\CHN_TR_2003.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_tr_2003.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_TR_M_2003.dta", replace


*==================================================================
*Import value by year*sector of Turkey from the World (2000-2004)
*==================================================================

**** Year 2000
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2000_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\W_TR_2000.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\W_tr_2000.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_wtr_2000.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_wtr_2000.dta", replace

use "$folder\Data\BACI\W_TR_2000.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_wtr_2000.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\W_TR_M_2000.dta", replace


**** Year 2001
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2001_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\W_TR_2001.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\W_tr_2001.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_wtr_2001.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_wtr_2001.dta", replace

use "$folder\Data\BACI\W_TR_2001.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_wtr_2001.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\W_TR_M_2001.dta", replace


**** Year 2002
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2002_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\W_TR_2002.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\W_tr_2002.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_wtr_2002.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_wtr_2002.dta", replace

use "$folder\Data\BACI\W_TR_2002.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_wtr_2002.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\W_TR_M_2002.dta", replace


**** Year 2003
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2003_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\W_TR_2003.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\W_tr_2003.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_wtr_2003.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_wtr_2003.dta", replace

use "$folder\Data\BACI\W_TR_2003.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_wtr_2003.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\W_TR_M_2003.dta", replace


**** Year 2004
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2004_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if importer == 792 //TR

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\W_TR_2004.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "$folder\RawData\CEPII BACI HS96\W_tr_2004.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_wtr_2004.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_wtr_2004.dta", replace

use "$folder\Data\BACI\W_TR_2004.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_wtr_2004.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\W_TR_M_2004.dta", replace


**** Append 2000-2004 import value W-CHN-TR tables

clear
use "$folder\Data\BACI\CHN_TR_M_2000.dta", clear
forvalues y = 2000/2004 {
	append using "$folder\Data\BACI\CHN_TR_M_`y'.dta"
}
save "$folder\Data\BACI\CHN_TR_M_(2000-04).dta", replace

use "$folder\Data\BACI\W_TR_M_2000.dta", clear
forvalues y = 2000/2004 {
	append using "$folder\Data\BACI\W_TR_M_`y'.dta"
}
save "$folder\Data\BACI\W_TR_M_(2000-04).dta", replace

use "$folder\Data\BACI\W_TR_M_(2000-04).dta", clear
rename value_isic world
joinby isic4 year using "$folder\Data\BACI\CHN_TR_M_(2000-04).dta" 
save "$folder\Data\BACI\W_CHN_TR_M_(2000-04).dta", replace

gen CHN_share = value_isic/world

duplicates drop

collapse (mean) CHN_share, by(isic4)

save "$folder\Data\BACI\W_CHN_TR_M_(2000-04).dta", replace

*======================
* 2000-04 weight WIOD
*======================

**** (1) The average weight

import excel "$folder\RawData\WIOD\TUR_NIOT_nov16.xlsx", ///
    sheet("National IO-tables") firstrow clear

keep if inrange(Year, 2000, 2004)

keep if inlist(Origin, "Domestic", "Imports")
drop if inlist(Code,"II_fob","TXSP","EXP_adj","PURR","PURNR","VA","IntTTM","GO")

drop CONS_* GFCF INVEN EXP GO

ds Year Code Origin Description, not
local indcols `r(varlist)'
foreach v of local indcols {
    rename `v' x`v'
}

reshape long x, i(Year Code Origin) j(industry_j) string
rename Code input_k
rename x Zij

destring Zij, replace force
collapse (sum) Z_tot = Zij, by(Year input_k industry_j)

keep if substr(industry_j,1,1)=="C"

bys Year industry_j: egen denom = total(Z_tot)
gen w_jk = Z_tot / denom
drop if missing(w_jk) | denom==0 | Z_tot==0

replace input_k    = "C10_12" if input_k=="C10-C12"
replace input_k    = "C13_15" if input_k=="C13-C15"
replace input_k    = "C31_32" if input_k=="C31_C32"
replace industry_j = "C10_12" if industry_j=="C10-C12"
replace industry_j = "C13_15" if industry_j=="C13-C15"
replace industry_j = "C31_32" if industry_j=="C31_C32"

collapse (mean) w_jk, by(input_k industry_j)

save "$folder\Data\IV\IO_weight_avg0004.dta", replace


**** (2) Imported-input dependence on China

use "$folder\Data\BACI\W_CHN_TR_M_(2000-04).dta", clear

* isic4 may be string with leading zeros
capture confirm numeric variable isic4
if _rc {
    gen isic4_num = real(isic4)
}
else {
    gen isic4_num = isic4
}

gen div = floor(isic4_num/100)

* Build WIOD-style upstream sector code
gen input_k = "C" + string(div, "%02.0f")
replace input_k = "C10_12" if inlist(div,10,11,12)
replace input_k = "C13_15" if inlist(div,13,14,15)
replace input_k = "C31_32" if inlist(div,31,32)

* Keep manufacturing divisions only
keep if inrange(div,10,33)

collapse (mean) CHN_share, by(input_k)

* Standardize labels just in case
replace input_k = "C10_12" if input_k=="C10-C12"
replace input_k = "C13_15" if input_k=="C13-C15"
replace input_k = "C31_32" if input_k=="C31_C32"

save "$folder\Data\IV\CHN_share_inputk_2000_2004.dta", replace

**** (3) Compute
use "$folder\Data\IV\IO_weight_avg0004.dta", clear

* Standardize WIOD labels too
replace input_k    = "C10_12" if input_k=="C10-C12"
replace input_k    = "C13_15" if input_k=="C13-C15"
replace input_k    = "C31_32" if input_k=="C31_C32"

replace industry_j = "C10_12" if industry_j=="C10-C12"
replace industry_j = "C13_15" if industry_j=="C13-C15"
replace industry_j = "C31_32" if industry_j=="C31_C32"

merge m:1 input_k using "$folder\Data\IV\CHN_share_inputk_2000_2004.dta"

tab input_k _merge

* keep all WIOD rows; unmatched China-share sectors get zero exposure
replace CHN_share = 0 if missing(CHN_share)

drop _merge

gen contrib = w_jk * CHN_share
collapse (sum) H_china_dep = contrib, by(industry_j)

save "$folder\Data\IV\H_china_dep_2000_2004.dta", replace

**** (4) Merge
use "$folder\Data\data_ready.dta", clear

capture drop _merge
capture confirm numeric variable isic4
if _rc {
    destring isic4, replace
}

replace industry_j = "C10_12" if inlist(div,10,11,12)
replace industry_j = "C13_15" if inlist(div,13,14,15)
replace industry_j = "C31_32" if inlist(div,31,32)

merge m:1 industry_j using "$folder\Data\IV\H_china_dep_2000_2004.dta"

tab industry_j _merge

* keep all observations in main regression sample
drop if _merge==2
replace H_china_dep = 0 if missing(H_china_dep)
drop _merge

egen tagsec = tag(isic4)
tab div if tagsec
sum H_china_dep, detail
corr H_china_dep Z_input

save "$folder\Data\data_ready_mec.dta", replace


**** (5) Set up
use "$folder\Data\data_ready_mec.dta", clear
xtset firm_id year
sort firm_id year
global X_lag "lleverage lliquidity llnsize l_age l_exporter"

gen ip_china = change_IP * H_china_dep
gen iv_china = output_IV * H_china_dep
gen input_china = Z_input * H_china_dep
gen ln_dom_sales = ln(dom_sales) if dom_sales>0
gen dln_dom_sales = D.ln_dom_sales


**** (6) Regressions

//// Hetero in the input-supply channel
ivreghdfe dln_mu (change_IP = output_IV) Z_input input_china $X_lag ///
    c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar kpF = e(widstat)
est store mec21

//// Offsetting output competition?
ivreghdfe dln_mu (change_IP ip_china = output_IV iv_china) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar kpF = e(widstat)
est store mec22

//// Auxiliary outcomes 
// Revenue growth
ivreghdfe dln_rev (change_IP = output_IV) Z_input input_china $X_lag ///
    c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar kpF = e(widstat)
est store mec23

ivreghdfe dln_rev (change_IP ip_china = output_IV iv_china) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar kpF = e(widstat)
est store mec24

// Domestic sales growth
ivreghdfe dln_dom_sales (change_IP = output_IV) Z_input input_china $X_lag ///
    c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar kpF = e(widstat)
est store mec25

ivreghdfe dln_dom_sales (change_IP ip_china = output_IV iv_china) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar kpF = e(widstat)
est store mec26

//// Table
esttab mec21 mec22 mec23 mec24 mec25 mec26 using "$folder\Tables\mec2.tex", replace ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP Z_input ip_china input_china) ///
    stats(N kpF, labels("Observations" "KP rk Wald F")) ///
    title("Imported-input dependence heterogeneity")

log close
















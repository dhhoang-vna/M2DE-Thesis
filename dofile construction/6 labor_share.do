clear mata
capture log close
clear

log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\6 labor_intensity.log", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

*-------------------------
* 1. VA cost
*-------------------------

** 4-digit
import excel "$folder\RawData\personnel costs.xls", sheet("Sheet0") clear

drop in 1/4
drop E A

gen str4 nace4 = ""
replace nace4 = regexs(1) if regexm(B, "^([0-9]{2})\.([0-9]{2})") 
replace nace4 = regexs(1) + regexs(2) if regexm(B, "^([0-9]{2})\.([0-9]{2})")

replace nace4 = nace4[_n-1] if nace4 == "" & _n>1

rename C year
drop B
drop if missing(nace4)
rename C year

replace D = "" if regexm(D, "^\s*\(1\)\*?\s*$")

destring D, gen(VA_cost) force
drop D

save "$folder\Data\TurkStat\VA_cost_4.dta", replace

** 3-digit

import excel "$folder\RawData\personnel costs.xls", sheet("Sheet0") clear

drop in 1/4
drop E A

gen byte is3 = regexm(B, "^[0-9]{2}\.[0-9]\.\s*\(")
gen byte is4 = regexm(B, "^[0-9]{2}\.[0-9]{2}\.\s*\(") 

gen str3 nace3 = ""
replace nace3 = regexs(1) + regexs(2) if regexm(B, "^([0-9]{2})\.([0-9])\.\s*\(")

gen byte level = .
replace level = 3 if is3
replace level = 4 if is4
replace level = level[_n-1] if missing(level) & _n>1

keep if level == 3
replace nace3 = nace3[_n-1] if missing(nace3) & _n>1

save "$folder\Data\TurkStat\VA_cost_3.dta", replace

* 2-digit

import excel "$folder\RawData\personnel costs.xls", sheet("Sheet0") clear

drop in 1/4
drop E A

gen byte is2 = regexm(B, "^[0-9]{2}\.\s*\(")      
gen byte is3 = regexm(B, "^[0-9]{2}\.[0-9]\.\s*\(")
gen byte is4 = regexm(B, "^[0-9]{2}\.[0-9]{2}\.\s*\(") 

gen byte level = .
replace level = 2 if is2
replace level = 3 if is3
replace level = 4 if is4
replace level = level[_n-1] if missing(level) & _n>1

gen str2 nace2 = ""
replace nace2 = regexs(1) if regexm(B, "^([0-9]{2})\.\s*\(")

replace nace2 = nace2[_n-1] if missing(nace2) & _n>1

keep if level==2
drop if missing(nace2)

replace D = "" if regexm(D, "^\s*\(1\)\*?\s*$")
destring D, gen(VA_cost) force
drop D B is2 is3 is4 level

rename C year

collapse (sum) VA_cost, by(nace2 year)
isid nace2 year, sort

save "$folder\Data\TurkStat\VA_costs_2.dta", replace


*--------------------
* 2. VA factor costs
*--------------------

import excel "$folder\RawData\VA factor cost.xls", sheet("Sheet0") clear

drop in 1/4
drop E A

gen str4 nace4 = ""
replace nace4 = regexs(1) if regexm(B, "^([0-9]{2})\.([0-9]{2})") 
replace nace4 = regexs(1) + regexs(2) if regexm(B, "^([0-9]{2})\.([0-9]{2})")

replace nace4 = nace4[_n-1] if nace4 == "" & _n>1

rename C year
rename D value
drop B
drop if missing(nace4)

replace value = "" if regexm(value, "^\s*\(1\)\*?\s*$")

destring value, gen(personnel_costs) force
drop value

save "$folder\Data\TurkStat\personnel_costs_4.dta", replace

** 2-digit
import excel "$folder\RawData\VA factor cost.xls", sheet("Sheet0") clear

drop in 1/4
drop E A

gen byte is2 = regexm(B, "^[0-9]{2}\.\s*\(")      
gen byte is3 = regexm(B, "^[0-9]{2}\.[0-9]\.\s*\(")
gen byte is4 = regexm(B, "^[0-9]{2}\.[0-9]{2}\.\s*\(") 

gen byte level = .
replace level = 2 if is2
replace level = 3 if is3
replace level = 4 if is4
replace level = level[_n-1] if missing(level) & _n>1

gen str2 nace2 = ""
replace nace2 = regexs(1) if regexm(B, "^([0-9]{2})\.\s*\(")

replace nace2 = nace2[_n-1] if missing(nace2) & _n>1

keep if level==2
drop if missing(nace2)

replace D = "" if regexm(D, "^\s*\(1\)\*?\s*$")
destring D, gen(personnel_cost) force
drop D B is2 is3 is4 level

rename C year

collapse (sum) personnel_cost, by(nace2 year)
isid nace2 year, sort

save "$folder\Data\TurkStat\personnel_cost_2.dta", replace



*----------------------------
* 3. Labor share computation
*----------------------------

** 4-digit

use "$folder\Data\TurkStat\personnel_costs_4.dta", clear
collapse (sum) personnel_cost, by(nace4 year)

count if missing(nace4) | missing(year)
drop if missing(nace4) | missing(year)
isid nace4 year
save "$folder\Data\TurkStat\personnel_costs_4_unique.dta", replace

use "$folder\Data\TurkStat\VA_cost_4.dta", clear
collapse (sum) VA_cost, by(nace4 year)

count if missing(nace4) | missing(year)
drop if missing(nace4) | missing(year)
isid nace4 year

merge m:1 nace4 year using "$folder\Data\TurkStat\personnel_costs_4_unique.dta"

drop _merge

gen labor_share_tr_4 = personnel_costs / VA_cost if personnel_costs>0 & VA_cost>0

destring year, replace

bys nace4: egen ls4_pre = mean(labor_share_tr_4) if inrange(year, 2009, 2015) 


* Impute missing sectors by 3-digit or 2-digit pre-mean
gen nace3 = substr(nace4,1,3)
bys nace3: egen ls3_pre = mean(ls4_pre)

gen nace2 = substr(nace4,1,2)
bys nace2: egen ls2_pre = mean(ls4_pre)

gen ls_pre_filled = ls4_pre
replace ls_pre_filled = ls3_pre if missing(ls_pre_filled) & !missing(ls3_pre)
replace ls_pre_filled = ls2_pre if missing(ls_pre_filled) & !missing(ls2_pre)

gen byte ls_imputed = missing(ls4_pre) & !missing(ls_pre_filled)

rename nace2 nace2d
rename nace4 nace2 

merge m:1 nace2 using "$folder\Data\Concordance\isic4_nace2.dta"

keep if _merge==3 
drop _merge
rename nace2 nace4
rename nace2d nace2
destring isic4, replace

collapse (mean) VA_cost ls_pre_filled, by(isic4 year)

isid isic4 year

save "$folder\Data\TurkStat\labor_share_4.dta", replace






** 2-digit

merge m:1 year using "$folder\Data\TurkStat\VA_costs_2.dta"

gen labor_share_tr = personnel_cost / VA_cost if personnel_cost>0 & VA_cost>0

drop _merge

save "$folder\Data\TurkStat\labor_share_2.dta", replace

tab nace2 year







log close

*-------------------------------
* 4. Robustness (WIOD 2-digit)
*-------------------------------
import excel "$folder\RawData\WIOD\Socio_Economic_Accounts.xlsx", sheet("DATA") firstrow clear

keep if country == "TUR"
keep if variable == "COMP" | variable == "VA"

keep if substr(code,1,1)=="C"

rename E y2000
rename F y2001
rename G y2002
rename H y2003
rename I y2004
rename J y2005
rename K y2006
rename L y2007
rename M y2008
rename N y2009
rename O y2010
rename P y2011
rename Q y2012
rename R y2013
rename S y2014

reshape long y, i(country variable code) j(year)
rename y value
drop description

reshape wide value, i(country code year) j(variable) string
destring valueCOMP valueVA, replace

gen labor_share = valueCOMP / valueVA

keep if inrange(year, 2010, 2014)
bys country code: egen LS_pre = mean(labor_share)
keep code LS_pre

gen nace2 = substr(code, 2, 2)

drop code
drop if nace2 == "33"

save "$folder\Data\ORBIS\labor_share_pre_wiod.dta", replace






















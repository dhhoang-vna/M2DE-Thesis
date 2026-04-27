clear mata
capture log close
clear

*******************************
**** OUTPUT COMPETITION IV ****
*******************************

log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\4 bartik_instrument.log", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"


****************
**** SHARES ****
****************

* 1. Import value of China to Turkey in the baseline year by sector (2009)

cd "$folder\RawData\CEPII BACI HS96"

import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2009_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if importer == 792 //Turkey

save "$folder\Data\BACI\CHN_TR_2009.dta", replace

tostring product, gen(hs6) format(%06.0f)

preserve 
keep hs6
duplicates drop

export delimited using "hs6_2009.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_withshares_2009.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_withshares_2009.dta", replace

use "$folder\Data\BACI\CHN_TR_2009.dta", clear

tostring product, gen(hs6) format(%06.0f)

joinby hs6 using "$folder\Data\BACI\hs96_isic4_withshares_2009.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring value share, replace force

gen value_isic = value * share

collapse (sum) value_isic, by(year importer isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_TR_importvalue_2009.dta", replace

* 2. Import absorption by sectors in the baseline year 2009

use "$folder\Data\UNIDO\absorption.dta", replace
keep if year == "2009"
destring isic4, replace
drop year
save "$folder\Data\UNIDO\absorption_2009.dta", replace

* 3. Calculate the Shares
use "$folder\Data\BACI\CHN_TR_importvalue_2009.dta", clear
destring isic4, replace

merge m:1 isic4 using "$folder\Data\UNIDO\absorption_2009.dta"

gen shares = value_isic / Absorption 
drop if missing(shares)
drop _merge

drop importer value_isic Absorption
tostring year isic4, replace

save "$folder\Data\IV\IV_shares.dta", replace


****************
**** SHIFTS ****
****************

** 1. Import value by year*sector of high income economies (US, Japan, EU15, South Korea, Australia - CEPII BACI)

* Year 2010
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2010_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2010.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2010.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2010.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2010.dta", replace

use "$folder\Data\BACI\CHN_HI_2010.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2010.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2010.dta", replace

* Year 2011 
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2011_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2011.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2011.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2011.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2011.dta", replace

use "$folder\Data\BACI\CHN_HI_2011.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2011.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2011.dta", replace

* Year 2012 
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2012_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2012.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2012.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2012.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2012.dta", replace

use "$folder\Data\BACI\CHN_HI_2012.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2012.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2012.dta", replace

* Year 2013
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2013_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2013.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2013.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2013.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2013.dta", replace

use "$folder\Data\BACI\CHN_HI_2013.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2013.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2013.dta", replace

* Year 2014
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2014_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2014.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2014.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2014.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2014.dta", replace

use "$folder\Data\BACI\CHN_HI_2014.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2014.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2014.dta", replace

* Year 2015 
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2015_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2015.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2015.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2015.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2015.dta", replace

use "$folder\Data\BACI\CHN_HI_2015.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2015.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2015.dta", replace

* Year 2016 
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2016_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2016.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2016.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2016.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2016.dta", replace

use "$folder\Data\BACI\CHN_HI_2016.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2016.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2016.dta", replace

* Year 2017 
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2017_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2017.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2017.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2017.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2017.dta", replace

use "$folder\Data\BACI\CHN_HI_2017.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2017.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2017.dta", replace

* Year 2018
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2018_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2018.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2018.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2018.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2018.dta", replace

use "$folder\Data\BACI\CHN_HI_2018.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2018.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2018.dta", replace

* Year 2019 
import delimited "$folder\RawData\CEPII BACI HS96\BACI_HS96_Y2019_V202501.csv", clear 

rename t year
rename i exporter
rename j importer
rename k product
rename v value
rename q quantity

keep if exporter == 156 //China
keep if inlist(importer, 36, 40, 56, 208, 246, 250, 276, 300, 372, 380, 392, 410, 442, 528, 620, 724, 752, 826, 840)

tostring product, gen(hs6) format(%06.0f)

bysort year hs6: egen m_hi = total(value)
keep year hs6 m_hi
duplicates drop

save "$folder\Data\BACI\CHN_HI_2019.dta", replace

preserve 
keep hs6
duplicates drop

export delimited using "hs6_hi_2019.csv", replace

** Using R for HS-ISIC concordance using In Song Kim et al (2022) Github repo **

* Stata again
import delimited using "$folder\RawData\CEPII BACI HS96\hs96_isic4_hi_2019.csv", varnames(1) stringcols(1/2) clear

save "$folder\Data\BACI\hs96_isic4_hi_2019.dta", replace

use "$folder\Data\BACI\CHN_HI_2019.dta", clear

joinby hs6 using "$folder\Data\BACI\hs96_isic4_hi_2019.dta"

* Construct ISIC4 level import values - Chinese exports to Turkey by ISIC4 and year

destring m_hi share, replace force

gen value_isic = m_hi * share

collapse (sum) value_isic, by(year isic4)

drop if isic4 == "NA"

save "$folder\Data\BACI\CHN_HI_M_2019.dta", replace

* Append 2010-2019 import value tables

clear
use "$folder\Data\BACI\CHN_HI_M_2010.dta", clear

forvalues y = 2011/2019 {
	append using "$folder\Data\BACI\CHN_HI_M_`y'.dta"
}

save "$folder\Data\BACI\CHN_HI_M_(2010-19).dta", replace


** 2. Import value of high income economies from the world aggregated by year*sector (UNIDO)

import excel "$folder\RawData\UNIDO\HI Import W.xlsx", firstrow clear

keep Year CountryCode ActivityCode Value
gen import_w = Value / 1000
rename Year year
rename ActivityCode isic4
drop Value

bysort year isic4: egen import_W = total(import_w)
keep year isic4 import_W
duplicates drop

save "$folder\Data\UNIDO\W_HI_M_(2010-2019).dta", replace

** 3. Calculate the Shifts

use "$folder\Data\BACI\CHN_HI_M_(2010-19).dta", clear
tostring year, replace
merge m:1 isic4 year using "$folder\Data\UNIDO\W_HI_M_(2010-2019).dta"
drop if missing(import_W)
drop _merge
gen import_share = value_isic / import_W 
bys isic4 (year): gen dln_import_share = ln(import_share) - ln(import_share[_n-1]) if import_share>0 & import_share[_n-1]>0
drop if missing(dln_import_share)

keep year isic dln_import_share

save "$folder\Data\IV\IV_shifts.dta", replace


*************************
**** SHIFTS x SHARES ****
*************************

use "$folder\Data\IV\IV_shifts.dta", clear
merge m:1 isic4 using "$folder\Data\IV\IV_shares.dta"
drop _merge
gen output_IV = shares*dln_import_share
drop if missing(output_IV)

save "$folder\Data\IV\output_IV.dta", replace


***********************
**** INPUT CONTROL ****
***********************

** 1. WIOD database for the share of input from sector k used by sector j

import excel "$folder\RawData\WIOD\TUR_NIOT_nov16.xlsx", sheet(National IO-tables) firstrow clear

keep if Year == 2003 

* Keep only intermediate-flow rows (inputs k)
keep if inlist(Origin, "Domestic", "Imports")
drop if inlist(Code,"II_fob","TXSP","EXP_adj","PURR","PURNR","VA","IntTTM","GO")

* Drop final demand/totals columns
drop CONS_* GFCF INVEN EXP GO

* Reshape to long: one cell per (Year, input_k=Code, industry_j=column)
ds Year Code Origin Description, not 
local indcols `r(varlist)'
foreach v of local indcols {
	rename `v' x`v'
}
reshape long x, i(Year Code Origin) j(industry_j) string
rename Code input_k
rename x Zij

* sum Domestic + Imports 
destring Zij, replace
collapse (sum) Z_tot = Zij, by(Year input_k industry_j)

* Denominator = total intermediate inputs of industry_j 
bys Year industry_j: egen denom = total(Z_tot)

* IO weight
gen w_jk = Z_tot / denom
drop if missing(w_jk) | denom==0
drop if Z_tot==0 
keep if substr(industry_j,1,1)=="C" // keep industry_j manufacturing only

gen div_j = real(substr(industry_j,2,2))
gen div_k = real(substr(input_k,2,2))

save "$folder\Data\IV\IO_weight.dta", replace


** 2. Input control
use "$folder\Data\IV\output_IV.dta", clear
destring isic4, replace

gen input_k = "C" + string(div, "%2.0f")
replace input_k = "C10-C12" if inlist(div,10,11,12)
replace input_k = "C13-C15"  if inlist(div,13,14,15)
replace input_k = "C31_C32" if inlist(div,31,32)

collapse (mean) Zk = output_IV, by(input_k year)

joinby input_k using "$folder\Data\IV\IO_weight.dta"

gen contrib = w_jk * Zk
collapse (sum) Z_input = contrib, by(industry_j year)

save "$folder\Data\IV\Z_input.dta", replace

* Attach Z_input back to 4-digit panel of output IV
use "$folder\Data\IV\output_IV.dta", clear
keep if inrange(year,2011,2019)
destring isic4, replace

replace industry_j = "C10C12" if inlist(div,10,11,12)
replace industry_j = "C13C15"  if inlist(div,13,14,15)
replace industry_j = "C31_C32" if inlist(div,31,32)

merge m:1 industry_j year using "$folder\Data\IV\Z_input.dta", keep(match master) nogen

save "$folder\Data\IV\output_IV.dta", replace

* What we have here is:
* - the input control uses only manufacturing input shocks 
* - all inputs (including agri/services/mining/etc.) are in the weight denominator
* - diagnostics: use manufacturing-input intensity for each industry_j, which is the sum of w_jk over C inputs. 

log close 


















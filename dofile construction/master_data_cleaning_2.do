clear mata
capture log close
clear all

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"
log using "$folder\Logs\master_data_cleaning_2.log", replace

do "$folder\dofile construction\1 orbis_data_2.do"
do "$folder\dofile construction\2 tfp_frontier_2.do"
do "$folder\dofile construction\3 import_penetration_IP_2.do"
do "$folder\dofile construction\4 bartik_instrument_2.do"
do "$folder\dofile construction\5 markup_estimation_2.do"
do "$folder\dofile construction\6 labor_share_2.do"
do "$folder\dofile construction\7 data_ready_2.do"

log close

clear mata
capture log close
clear

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

cd "$folder/RawData"   

do "$folder/dofile construction/1 orbis_data"   

do "$folder/dofile construction/2 TFP_frontier"    

do "$folder/dofile construction/3 import_penetration_IP"  

do "$folder/dofile construction/4 bartik_instruments" 
 
do "$folder/dofile construction/5 data_ready"  


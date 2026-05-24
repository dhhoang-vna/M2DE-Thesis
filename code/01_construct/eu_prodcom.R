source(file.path(Sys.getenv("REPLICATION_ROOT", unset = getwd()), "code", "00_setup", "paths.R"))

library(readxl)
library(tidyverse)

# Read the Excel file
raw <- read_excel(
  file.path(raw_data_dir, "ds-059358__custom_19563131_spreadsheet.xlsx"),
  sheet = "Data",
  col_names = FALSE
)

# Storage for clean data
clean_list <- list()

# Process the file
for (i in 1:nrow(raw)) {
  
  # Check for PRODUCT row
  cell_a <- as.character(raw[[i, 1]])
  
  if(!is.na(cell_a) && grepl("PRODUCT \\[PRODUCT\\]", cell_a, ignore.case = TRUE)) {
    
    # Product code and name are in column 3 (index 3)
    product_full <- as.character(raw[[i, 3]])
    
    # Extract product code from brackets [XXXXXXXX]
    product_code <- str_extract(product_full, "\\[([0-9]+)\\]")
    product_code <- gsub("\\[|\\]", "", product_code)
    
    if(is.na(product_code) || nchar(product_code) == 0) next
    
    # Next row: INDICATORS (i+1)
    if(i+1 > nrow(raw)) next
    indicator_cell <- as.character(raw[[i+1, 1]])
    
    if(!is.na(indicator_cell) && grepl("INDICATORS", indicator_cell, ignore.case = TRUE)) {
      
      indicator_name <- as.character(raw[[i+1, 3]])
      if(is.na(indicator_name)) next
      
      # Skip blank row at i+2
      # TIME row at i+3
      if(i+3 > nrow(raw)) next
      time_cell <- as.character(raw[[i+3, 1]])
      
      if(!is.na(time_cell) && grepl("TIME", time_cell, ignore.case = TRUE)) {
        
        # Years are in row i+3, starting from column 2 onward
        years_raw <- raw[i+3, 2:ncol(raw)] %>% unlist()
        
        # FREQ row at i+4 (skip)
        # REPORTER row at i+5 (skip header)
        # EU27 data at i+6
        if(i+6 > nrow(raw)) next
        
        values_raw <- raw[i+6, 2:ncol(raw)] %>% unlist()
        
        # Pair years with values
        for(j in seq_along(years_raw)) {
          yr <- years_raw[j]
          val <- values_raw[j]
          
          # Convert
          yr_int <- suppressWarnings(as.integer(yr))
          val_num <- suppressWarnings(as.numeric(val))
          
          # Only keep valid pairs in 2011-2019
          if(!is.na(yr_int) && !is.na(val_num) && yr_int >= 2011 && yr_int <= 2019) {
            clean_list[[length(clean_list) + 1]] <- data.frame(
              product = product_code,
              indicator = indicator_name,
              geo = "EU27_2020",
              year = yr_int,
              value = val_num,
              stringsAsFactors = FALSE
            )
          }
        }
      }
    }
  }
}

# Combine
final <- bind_rows(clean_list)

# Check
cat("Total rows extracted:", nrow(final), "\n")
cat("Unique products:", n_distinct(final$product), "\n")
cat("Unique indicators:", n_distinct(final$indicator), "\n")
cat("Years:", paste(sort(unique(final$year)), collapse = ", "), "\n")

# Save
write_csv(
  final,
  file.path(raw_data_dir, "prodcom_clean_long.csv")
)

# Preview
print(head(final, 50))






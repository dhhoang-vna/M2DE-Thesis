library(concordance)
library(dplyr)
library(readr)
library(purrr)

# Read HS6 list from csv
hs_tbl <- read_csv(
  "D:/1. M2 Development Economics/0. Thesis/Thesis/RawData/CEPII BACI HS96/hs6_tr_2000.csv",
  col_types = cols(hs6 = col_character())
)

hs_vec <- hs_tbl$hs6

# Apply Concordance HS1 to ISIC4
res_list <- concord_hs_isic(
  sourcevar   = hs_vec,
  origin      = "HS1",        # HS96
  destination = "ISIC4",
  dest.digit  = 4,
  all         = TRUE
)

# Turn list into a table
hs_isic <- map2_dfr(res_list, hs_vec, ~ {
  if (is.null(.x)) return(NULL)
  df <- as.data.frame(.x)
  df$hs6 <- .y
  df
})

# Clean names and keep essential columns
hs_isic <- hs_isic %>%
  rename(isic4 = match,
         share = weight) %>%
  select(hs6, isic4, share)

# Export
setwd("D:/1. M2 Development Economics/0. Thesis/Thesis/RawData/CEPII BACI HS96")
write_csv(hs_isic, "hs96_isic4_tr_2000.csv")


# Data Availability

This thesis uses restricted firm-level data, public or publicly obtainable
trade/industry/input-output data, and derived analysis files. The GitHub
package intentionally separates executable code and public-facing outputs from
non-redistributable inputs.

## Restricted Firm-Level Inputs

### ORBIS/AMADEUS

The Turkish manufacturing firm panel is proprietary and cannot be redistributed.
Replication from raw firm data requires licensed access to ORBIS/AMADEUS and
permission to use the extracted financial, classification, and ownership files.

Expected local placement:

```text
data/restricted_placeholder/raw/Orbis/
```

## Public or Publicly Obtainable Raw Inputs

These files are public or obtainable from their providers but can be bulky, so
they are not committed to GitHub.

| Source | Use | Expected folder |
|---|---|---|
| CEPII BACI HS96 | China import penetration, high-income export shifters, product granularity | `data/restricted_placeholder/raw/CEPII BACI HS96/` |
| UNIDO INDSTAT4/ISDB | Domestic output and apparent consumption denominators | `data/restricted_placeholder/raw/UNIDO/` |
| TURKSTAT PPI | Producer-price deflators | `data/restricted_placeholder/raw/TURKSTAT/` |
| WIOD national input-output tables | Input-supply exposure and labor-share measures | `data/restricted_placeholder/raw/WIOD/` |
| NACE/ISIC and HS/ISIC concordances | Firm-sector and trade-sector mapping | `data/restricted_placeholder/derived/Concordance/` |

## Derived Files Needed for the Focused M2DE Thesis Run

The focused thesis-results runner starts from derived Stata datasets. These are
not redistributed when built from restricted firm-level data.

```text
data/restricted_placeholder/derived/data_ready.dta
data/restricted_placeholder/derived/data_ready_mec.dta
data/restricted_placeholder/derived/data_ready_robust.dta
data/restricted_placeholder/derived/data_ready_H.dta
data/restricted_placeholder/derived/data_ready_mec_chn_gran.dta
data/restricted_placeholder/derived/BACI/IP.dta
data/restricted_placeholder/derived/BACI/demand_controls_isic4_year.dta
data/restricted_placeholder/derived/BACI/chinese_product_granularity_isic4.dta
data/restricted_placeholder/derived/BACI/IP_chinese_granularity.dta
data/restricted_placeholder/derived/BACI/hi_destination_sector_demand_growth.dta
data/restricted_placeholder/derived/IV/*.dta
data/restricted_placeholder/derived/UNIDO/apparent_consumption.dta
data/restricted_placeholder/raw/WIOD/TUR_NIOT_nov16.xlsx
```

## Included Public Outputs

The repository includes thesis-facing tables and figures under:

```text
output/tables/
output/figures/
```

These outputs are suitable for auditing the paper build. They do not make the
restricted microdata public.

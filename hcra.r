### HCRA Reform Report - ACS Data Analysis (Stage 1) ###
### David Lee, June 2026
###
### PURPOSE -------------------------------------------------------------------
### Build the Stage 1 core table requested in
### "ACS data analysis for report on reforming the Health Care Reform Act (HCRA)".
### The table shows the NUMBER of NYS-resident workers by:
###   (a) industry  (2-digit NAICS sectors + 3 special-interest detail industries)
###   (b) class of worker (Private vs. Government, with private detail), and
###   (c) type of health insurance coverage (the 7 IPUMS/ACS HI categories
###       + any-coverage, uninsured, and the Stage-2 target "Medicaid or uninsured").
###
### DATA ----------------------------------------------------------------------
### 2024 ACS 5-year PUMS, person records, New York (psam_p36.csv).
### Source: https://www2.census.gov/programs-surveys/acs/data/pums/2024/5-Year/csv_pny.zip
### Because we use the NY PUMS file and PUMA = place of RESIDENCE, the universe is
### already "NYS resident workers" (no place-of-work filter is applied).
###
### NOTE on variable names: this script uses the Census Bureau raw PUMS variables,
### which map one-to-one to the IPUMS HI variables in the request's PDF:
###   IPUMS HINSEMP  = HINS1 (employer/union)
###   IPUMS HINSPUR  = HINS2 (purchased directly)
###   IPUMS HINSCARE = HINS3 (Medicare)
###   IPUMS HINSCAID = HINS4 (Medicaid / other gov't assistance)
###   IPUMS HINSTRI  = HINS5 (TRICARE / other military)
###   IPUMS HINSVA   = HINS6 (VA)
###   IPUMS HINSIHS  = HINS7 (Indian Health Service)
### In the raw PUMS, HINS1-7 are coded 1 = covered, 2 = not covered.
### HICOV (coverage recode): 1 = has coverage, 2 = uninsured. Per Census, IHS-only
### is NOT counted as insured.
### -----------------------------------------------------------------------------

library(data.table)

### Run from the script's own folder (where psam_p36.csv lives).
### Paths below are relative to the current working directory.

## ---------------------------------------------------------------------------
## STEP 1.  Read only the columns we need (the full file is ~290 cols).
## ---------------------------------------------------------------------------
weightcols <- c("PWGTP", paste0("PWGTP", 1:80))
keepcols <- c("SERIALNO", "PUMA", "AGEP",
              "COW", "ESR", "INDP",
              "HINS1", "HINS2", "HINS3", "HINS4", "HINS5", "HINS6", "HINS7",
              "HICOV", weightcols)

dt <- fread("psam_p36.csv", select = keepcols, showProgress = FALSE)
cat("Rows read (all NY persons):", nrow(dt), "\n")

## ---------------------------------------------------------------------------
## STEP 2.  Define the universe: NYS-resident WORKERS.
##   ESR (employment status recode):
##     1 = civilian employed, at work
##     2 = civilian employed, with a job but not at work
##     3 = unemployed
##     4 = armed forces, at work
##     5 = armed forces, with a job but not at work
##     6 = not in labor force
##   Workers = ESR in {1,2,4,5}.  Industry (INDP) is the current/most-recent job.
##   INDP 9920 = "unemployed, last worked 5+ yrs ago or never" -> not a worker.
## ---------------------------------------------------------------------------
dt <- dt[ESR %in% c(1, 2, 4, 5) & !is.na(INDP) & INDP != 9920]
cat("Rows after restricting to NYS resident workers:", nrow(dt), "\n")

## ---------------------------------------------------------------------------
## STEP 3.  Map INDP -> industry sector (2-digit NAICS groupings from the PDF).
##   INDP is stored as an integer (leading zeros dropped), so 0170 -> 170, etc.
## ---------------------------------------------------------------------------
classify_sector <- function(indp) {
  fcase(
    indp >= 170  & indp <= 490 , "Agriculture, Forestry, Fishing & Hunting, and Mining",
    indp >= 570  & indp <= 690 , "Utilities",
    indp == 770                , "Construction",
    indp >= 1070 & indp <= 3990, "Manufacturing",
    indp >= 4070 & indp <= 4590, "Wholesale Trade",
    indp >= 4670 & indp <= 5791, "Retail Trade",
    indp >= 6070 & indp <= 6390, "Transportation & Warehousing",
    indp >= 6471 & indp <= 6781, "Information",
    indp >= 6871 & indp <= 6992, "Finance & Insurance",
    indp >= 7071 & indp <= 7190, "Real Estate and Rental & Leasing",
    indp >= 7270 & indp <= 7490, "Professional, Scientific & Technical Services",
    indp == 7570               , "Management of Companies & Enterprises",
    indp >= 7580 & indp <= 7790, "Administrative, Support & Waste Mgmt Services",
    indp >= 7860 & indp <= 7890, "Educational Services",
    indp >= 7970 & indp <= 8470, "Health Care & Social Assistance",
    indp >= 8561 & indp <= 8590, "Arts, Entertainment & Recreation",
    indp >= 8660 & indp <= 8690, "Accommodation & Food Services",
    indp >= 8770 & indp <= 9290, "Other Services, Except Public Administration",
    indp >= 9370 & indp <= 9590, "Public Administration",
    indp >= 9670 & indp <= 9870, "Military / Armed Forces",
    default = "Unclassified"
  )
}
dt[, sector := classify_sector(INDP)]

## Special-interest DETAIL industries (carved out within their parent sector).
dt[, detail := fcase(
  INDP == 5392               , "Warehouse clubs, supercenters & other general merch. retailers",
  INDP == 6390               , "Warehousing & storage",
  default = NA_character_
)]

## ---------------------------------------------------------------------------
## STEP 4.  Class of worker (separate GOVERNMENT from PRIVATE).
##   COW: 1 priv for-profit; 2 priv non-profit; 3 local gov; 4 state gov;
##        5 federal gov; 6 self-emp not inc.; 7 self-emp inc.; 8 unpaid family.
## ---------------------------------------------------------------------------
dt[, class := fcase(
  COW == 1            , "Private for-profit",
  COW == 2            , "Private non-profit",
  COW %in% c(3, 4, 5) , "Government",
  COW %in% c(6, 7)    , "Self-employed",
  default = "Unpaid family / other"
)]
## Coarse Private-vs-Government grouping (Private = everything except gov't).
dt[, sector_pubpriv := fifelse(COW %in% c(3, 4, 5), "Government", "Private")]

## ---------------------------------------------------------------------------
## STEP 5.  Health-insurance indicators (TRUE = worker has that coverage).
## ---------------------------------------------------------------------------
dt[, `:=`(
  emp       = HINS1 == 1,                 # employer / union  (HINSEMP)
  no_emp    = HINS1 == 2,                 # NOT covered by employer  (key policy var)
  dir       = HINS2 == 1,                 # direct purchase   (HINSPUR)
  medicare  = HINS3 == 1,                 # Medicare          (HINSCARE)
  medicaid  = HINS4 == 1,                 # Medicaid          (HINSCAID)
  tricare   = HINS5 == 1,                 # TRICARE/military  (HINSTRI)
  va        = HINS6 == 1,                 # VA                (HINSVA)
  ihs       = HINS7 == 1,                 # Indian Health Svc (HINSIHS)
  anycov    = HICOV == 1,                 # any coverage
  uninsured = HICOV == 2                  # uninsured
)]
dt[, total := TRUE]                        # every worker
dt[, medicaid_or_uninsured := (medicaid | uninsured)]   # Stage-2 target group

## measures, in the order they should appear as columns
measures <- c("total", "emp", "no_emp", "dir", "medicare", "medicaid",
              "tricare", "va", "ihs", "anycov", "uninsured",
              "medicaid_or_uninsured")
measure_labels <- c(
  total                 = "Total workers",
  emp                   = "Employer/union (HINSEMP)",
  no_emp                = "NO employer coverage",
  dir                   = "Direct purchase (HINSPUR)",
  medicare              = "Medicare (HINSCARE)",
  medicaid              = "Medicaid (HINSCAID)",
  tricare               = "TRICARE/military (HINSTRI)",
  va                    = "VA (HINSVA)",
  ihs                   = "Indian Health Svc (HINSIHS)",
  anycov                = "Any coverage",
  uninsured             = "Uninsured",
  medicaid_or_uninsured = "Medicaid or uninsured"
)

## ---------------------------------------------------------------------------
## STEP 6.  Weighted estimates + replicate-weight margins of error.
##   For a count, the replicate estimate is the sum of replicate weights over
##   the covered workers; SE = sqrt( (4/80) * sum_k (rep_k - est)^2 ).
##   MOE = 1.645 * SE  (90% confidence, Census standard).
## ---------------------------------------------------------------------------
estimate_se <- function(data, by, ind) {
  sub <- data[get(ind) == TRUE] # only workers with Medicaid
  if (nrow(sub) == 0L) return(NULL)
  s <- sub[, lapply(.SD, sum), by = by, .SDcols = weightcols]
  est <- s$PWGTP
  repmat <- as.matrix(s[, paste0("PWGTP", 1:80), with = FALSE])
  se <- sqrt((4 / 80) * rowSums((repmat - est)^2))
  out <- s[, ..by]
  out[, `:=`(measure = ind, estimate = est, moe = 1.645 * se)]
  out[]
}

## Build a long table of estimates for a given row-grouping (industry column).
## Produces one set of rows per class plus an "All workers" total per industry.
build_long <- function(data, industry_col) {
  res <- list()
  for (m in measures) {
    ## by class
    res[[paste0(m, "_byclass")]] <- estimate_se(data, c(industry_col, "class"), m)
    ## all workers (industry total)
    allw <- estimate_se(data, industry_col, m)
    if (!is.null(allw)) allw[, class := "All workers"]
    res[[paste0(m, "_all")]] <- allw
  }
  rbindlist(res, use.names = TRUE, fill = TRUE)
}

## Sector-level table (drop unclassified, which should be empty).
sector_long <- build_long(dt[sector != "Unclassified"], "sector")
setnames(sector_long, "sector", "industry")

## Special-interest detail table.
detail_long <- build_long(dt[!is.na(detail)], "detail")
setnames(detail_long, "detail", "industry")

## Statewide "All industries" total (handy denominator / sanity check).
total_long <- build_long(dt[, .SD, .SDcols = c("class", measures, weightcols)][, industry := "ALL INDUSTRIES (NYS workers)"][], "industry")

long <- rbindlist(list(total_long, sector_long, detail_long), use.names = TRUE, fill = TRUE)

## ---------------------------------------------------------------------------
## STEP 7.  Reshape to wide review tables (estimates and MOEs) and write CSVs.
## ---------------------------------------------------------------------------
long[, measure := factor(measure, levels = measures)]
long[, class := factor(class, levels = c("All workers", "Private for-profit",
        "Private non-profit", "Self-employed", "Unpaid family / other", "Government"))]

est_wide <- dcast(long, industry + class ~ measure, value.var = "estimate")
moe_wide <- dcast(long, industry + class ~ measure, value.var = "moe")

## nicer column names
setnames(est_wide, measures, unname(measure_labels[measures]), skip_absent = TRUE)
setnames(moe_wide, measures, unname(measure_labels[measures]), skip_absent = TRUE)

## order rows: industries in a sensible order, classes by the factor above
ind_order <- c("ALL INDUSTRIES (NYS workers)",
               unique(sector_long$industry),
               unique(detail_long$industry))
est_wide[, industry := factor(industry, levels = ind_order)]
moe_wide[, industry := factor(industry, levels = ind_order)]
setorder(est_wide, industry, class)
setorder(moe_wide, industry, class)

## round counts to whole workers
numcols <- names(est_wide)[sapply(est_wide, is.numeric)]
est_wide[, (numcols) := lapply(.SD, round), .SDcols = numcols]
moe_wide[, (numcols) := lapply(.SD, round), .SDcols = numcols]

fwrite(est_wide, "hcra_stage1_counts.csv")
fwrite(moe_wide, "hcra_stage1_moe.csv")
fwrite(long,      "hcra_stage1_tidy.csv")

## ---------------------------------------------------------------------------
## STEP 8.  Console summary.
## ---------------------------------------------------------------------------
cat("\n==== Stage 1 complete ====\n")
cat("Wrote: hcra_stage1_counts.csv  (estimates, wide)\n")
cat("       hcra_stage1_moe.csv     (margins of error, wide)\n")
cat("       hcra_stage1_tidy.csv    (long: industry x class x measure)\n\n")

## quick look: All-workers rows, key columns
show <- est_wide[class == "All workers",
  .(industry,
    `Total workers`,
    `Employer/union (HINSEMP)`,
    `NO employer coverage`,
    `Medicaid (HINSCAID)`,
    Uninsured,
    `Medicaid or uninsured`)]
show[, `% no employer cov` := round(100 * `NO employer coverage` / `Total workers`, 1)]
show[, `% Medicaid/uninsured` := round(100 * `Medicaid or uninsured` / `Total workers`, 1)]
cat("All-workers summary by industry (counts; % of industry workers):\n")
print(show, nrows = 60)

# HCRA Reform — ACS Data Analysis

Analysis supporting a report that argues for replacing New York's **Health Care Reform Act (HCRA)** tax on health insurance with broad-based business taxes. The goal is to identify the industries with large numbers and shares of workers **not covered by employer-provided health insurance** (i.e., on Medicaid or uninsured), and ultimately to describe those workers' location and demographics.

This repository covers **Stage 1**: a core table of NYS-resident workers by **industry**, **class of worker (government vs. private)**, and **type of health insurance coverage**.

---

## 1. Data

| | |
|---|---|
| **Source** | U.S. Census Bureau, **2024 ACS 5-year PUMS**, person records, New York |
| **File** | `psam_p36.csv` (from `csv_pny.zip`, ~639 MB unzipped) |
| **Download** | https://www2.census.gov/programs-surveys/acs/data/pums/2024/5-Year/csv_pny.zip |
| **Geography** | NY PUMS file; `PUMA` = place of **residence** → universe is **NYS residents** (no place-of-work filter, per the request) |
| **Weights** | `PWGTP` (person weight); `PWGTP1`–`PWGTP80` (replicate weights for margins of error) |

> The 5-year PUMS pools 2020–2024 survey responses, inflation/weighting handled by the Census Bureau. We use person-level records because the analysis is about workers, their industry, and their insurance.

---

## 2. How to reproduce

```r
# R 4.5+, with data.table installed
# 1. Download & unzip csv_pny.zip into this folder so psam_p36.csv is present
# 2. Run:
Rscript hcra.r
```

Outputs (written to this folder):

| File | Contents |
|---|---|
| `hcra_stage1_counts.csv` | **Main table** — worker counts (estimates), rows = industry × class, columns = coverage type |
| `hcra_stage1_moe.csv` | Margins of error matching every cell in the counts table |
| `hcra_stage1_tidy.csv` | Long/tidy form (industry × class × measure → estimate, moe) for pivoting — see the [measure legend](#36-measure-legend-the-measure-column) |

---

## 3. Methods

### 3.1 Universe: NYS-resident workers
Workers are defined by employment status recode **`ESR ∈ {1, 2, 4, 5}`** (civilian employed at work / with a job not at work; armed forces at work / with a job not at work). Records with no industry (`INDP` missing or `9920` = "unemployed, last worked 5+ years ago or never worked") are excluded.

- Unweighted records: **456,789**
- Weighted NYS workers: **≈ 9.54 million**

### 3.2 Industry (the rows)
`INDP` (Census industry code, stored as an integer with leading zeros dropped) is mapped to the **2-digit NAICS sectors** highlighted in the request. Three **special-interest detail industries** are also carved out (and reported as their own rows in addition to their parent sector):

| Detail industry | `INDP` code(s) |
|---|---|
| Warehouse clubs, supercenters & other general merchandise retailers | 5392 |
| Warehousing & storage | 6390 |
| Food services & drinking places | 8680 + 8690 |

### 3.3 Class of worker — government separated from private
`COW` (class of worker) is grouped so government is **separated from private**, as requested. Government here spans every sector (e.g., public schools, public hospitals, transit), not just Public Administration.

| Class | `COW` codes |
|---|---|
| Private for-profit | 1 |
| Private non-profit | 2 |
| Self-employed | 6, 7 |
| Unpaid family / other | 8 |
| **Government** (local + state + federal) | 3, 4, 5 |

Each industry also has an **"All workers"** row (sum across classes). Class rows sum exactly to the All-workers total.

### 3.4 Health-insurance coverage (the columns)
The script uses the raw Census PUMS `HINS1`–`HINS7` variables, which map **one-to-one** to the IPUMS HI variables in the request's PDF. In the raw PUMS, `HINS*` is coded **1 = covered, 2 = not covered**; `HICOV` is **1 = insured, 2 = uninsured**.

| Column | Raw var | IPUMS name | Meaning |
|---|---|---|---|
| Employer/union | `HINS1` | HINSEMP | Employer- or union-provided |
| Direct purchase | `HINS2` | HINSPUR | Purchased directly (incl. marketplace) |
| Medicare | `HINS3` | HINSCARE | |
| Medicaid | `HINS4` | HINSCAID | Medicaid / other gov't assistance |
| TRICARE/military | `HINS5` | HINSTRI | |
| VA | `HINS6` | HINSVA | |
| Indian Health Svc | `HINS7` | HINSIHS | Not counted as insured by Census |
| **Any coverage** | `HICOV==1` | HCOVANY | |
| **Uninsured** | `HICOV==2` | — | |
| **NO employer coverage** | `HINS1==2` | — | Key policy variable |
| **Medicaid or uninsured** | `HINS4==1` OR `HICOV==2` | — | Stage-2 target population |

> **Coverage categories overlap.** A worker can hold several types at once (e.g., a worker over 65 dual-eligible for Medicare and Medicaid), so the coverage columns **do not sum to the total**. Each column is an independent count of workers holding that coverage.

### 3.5 Margins of error
Margins of error use the **80 replicate weights** with the Census Bureau's Successive Differences Replication (SDR) formula:

```
SE  = sqrt( (4/80) * Σ_k (estimate_k − estimate)² )
MOE = 1.645 × SE          # 90% confidence (Census standard)
```

The `4/80` factor and the 90% (1.645) multiplier are the Census Bureau standard, documented in **["PUMS Accuracy of the Data (2024)"](https://www2.census.gov/programs-surveys/acs/tech_docs/pums/accuracy/2020_2024AccuracyPUMS.pdf)** (see the "Estimating Standard Errors with Replicate Weights" section); the same recipe is used in the project's training file. General ACS MOE methodology: [Census ACS PUMS documentation](https://www.census.gov/programs-surveys/acs/microdata/documentation.html) and the [ACS General Handbook, Ch. 8 (Measures of Error)](https://www.census.gov/content/dam/Census/library/publications/2020/acs/acs_general_handbook_2020_ch08.pdf).

Every estimate in `hcra_stage1_counts.csv` has a matching MOE in `hcra_stage1_moe.csv`. (Example: statewide total workers = 9,535,478 ± 18,039.)

### 3.6 Measure legend (the `measure` column)

`hcra_stage1_tidy.csv` is in **long format** — each row is one `industry × class × measure` combination with its `estimate` and `moe`. The `measure` column holds a short key naming **which weighted worker count the row reports**. These are the same 12 statistics that appear as the *columns* of the two wide files; the table below maps each key to its meaning, its source variable, and its wide-file column header.

| `measure` key | Meaning (count of workers who…) | Source | Wide-file column |
|---|---|---|---|
| `total` | all workers (the denominator) | universe | Total workers |
| `emp` | are covered by employer/union | `HINS1=1` (HINSEMP) | Employer/union (HINSEMP) |
| `no_emp` | are **not** covered by employer | `HINS1=2` | NO employer coverage |
| `dir` | have direct-purchase coverage | `HINS2=1` (HINSPUR) | Direct purchase (HINSPUR) |
| `medicare` | have Medicare | `HINS3=1` (HINSCARE) | Medicare (HINSCARE) |
| `medicaid` | have Medicaid / gov't assistance | `HINS4=1` (HINSCAID) | Medicaid (HINSCAID) |
| `tricare` | have TRICARE / military | `HINS5=1` (HINSTRI) | TRICARE/military (HINSTRI) |
| `va` | have VA coverage | `HINS6=1` (HINSVA) | VA (HINSVA) |
| `ihs` | have Indian Health Service | `HINS7=1` (HINSIHS) | Indian Health Svc (HINSIHS) |
| `anycov` | have any coverage | `HICOV=1` | Any coverage |
| `uninsured` | are uninsured | `HICOV=2` | Uninsured |
| `medicaid_or_uninsured` | are on Medicaid **or** uninsured (Stage-2 target) | `HINS4=1` OR `HICOV=2` | Medicaid or uninsured |

`total` is the denominator; the remaining measures **overlap** (a worker can appear in several) and do **not** sum to it — see §3.4.

---

## 4. Key findings (Stage 1)

Among all NYS-resident workers: **69.7% have employer/union coverage**, **30.3% have no employer coverage**, **16.1% are on Medicaid**, **5.9% are uninsured**, and **22.0% are on Medicaid or uninsured**.

The hypothesis holds — a handful of lower-wage, service- and goods-handling industries carry by far the highest shares of workers outside employer coverage. Industries ranked by **% Medicaid or uninsured** (the Stage-2 target group):

| Industry | Workers | % employer cov. | % no employer cov. | % Medicaid | % uninsured | **% Medicaid or uninsured** |
|---|--:|--:|--:|--:|--:|--:|
| **Food services & drinking places** ⭑ | 483,733 | 42.9 | 57.1 | 31.9 | 14.5 | **46.4** |
| Accommodation & Food Services | 547,643 | 45.3 | 54.7 | 30.9 | 13.7 | **44.6** |
| Agriculture, Forestry, Fishing & Hunting, and Mining | 53,696 | 46.7 | 53.3 | 19.9 | 18.6 | **38.5** |
| **Warehousing & storage** ⭑ | 26,980 | 57.3 | 42.7 | 26.2 | 11.2 | **37.4** |
| **Warehouse clubs, supercenters & general merch.** ⭑ | 108,831 | 57.7 | 42.3 | 28.6 | 7.2 | **35.8** |
| Administrative, Support & Waste Mgmt Services | 360,270 | 57.7 | 42.3 | 23.1 | 10.9 | **34.0** |
| Other Services, Except Public Administration | 445,004 | 54.9 | 45.1 | 24.3 | 8.8 | **33.1** |
| Construction | 540,811 | 59.0 | 41.0 | 16.2 | 15.9 | **32.1** |
| Transportation & Warehousing | 476,198 | 60.9 | 39.1 | 24.2 | 7.8 | **32.0** |
| Retail Trade | 879,183 | 59.3 | 40.7 | 24.3 | 7.2 | **31.5** |
| Arts, Entertainment & Recreation | 222,832 | 63.8 | 36.2 | 17.8 | 5.9 | **23.7** |
| Health Care & Social Assistance | 1,675,139 | 70.0 | 30.0 | 18.8 | 3.7 | **22.5** |
| **ALL INDUSTRIES (NYS workers)** | **9,535,478** | **69.7** | **30.3** | **16.1** | **5.9** | **22.0** |
| Wholesale Trade | 175,186 | 69.5 | 30.5 | 13.4 | 5.9 | 19.3 |
| Real Estate and Rental & Leasing | 197,783 | 67.2 | 32.8 | 13.8 | 5.0 | 18.8 |
| Manufacturing | 544,273 | 74.9 | 25.1 | 12.6 | 5.6 | 18.2 |
| Educational Services | 1,117,430 | 81.5 | 18.5 | 10.4 | 2.3 | 12.7 |
| Information | 249,395 | 79.6 | 20.4 | 9.4 | 3.2 | 12.6 |
| Professional, Scientific & Technical Services | 890,063 | 79.3 | 20.7 | 7.4 | 3.1 | 10.5 |
| Management of Companies & Enterprises | 11,039 | 87.4 | 12.6 | 6.3 | 2.6 | 8.9 |
| Utilities | 60,418 | 89.3 | 10.7 | 5.3 | 2.8 | 8.1 |
| Finance & Insurance | 561,187 | 86.8 | 13.2 | 5.4 | 2.2 | 7.6 |
| Public Administration | 453,330 | 89.5 | 10.5 | 5.9 | 1.6 | 7.5 |
| Military / Armed Forces | 25,395 | 37.1 | 62.9 | 3.5 | 0.8 | 4.3 |

⭑ = special-interest detail industry. Military shows low employer coverage because most are covered by **TRICARE** (HINSTRI), not because they are uninsured (only 0.8% uninsured).

**Takeaways for the report:**
- Coverage gaps are concentrated in **food service/accommodation, agriculture, warehousing & general-merchandise retail, admin/support services, construction, and transportation** — exactly the goods-handling and lower-wage service industries.
- The strongest employer coverage (and smallest gaps) is in **Public Administration, Finance & Insurance, Utilities, and Professional/Technical services** — i.e., the sectors least affected if HCRA's tax on health insurance were replaced.
- Within high-employment sectors, the **government vs. private split** matters: government workers (in `hcra_stage1_counts.csv`) consistently show much higher employer-coverage rates than their private counterparts in the same sector.

---

## 5. Note on HIMRKS (Subsidized Marketplace Coverage)

The request asked whether **HIMRKS** (subsidized marketplace coverage) is usable here.

- **HIMRKS is a CPS ASEC variable only — it is *not* in the ACS**, and therefore not in IPUMS-ACS either.
- In the ACS, subsidized-marketplace plans are folded into **direct purchase (`HINS2` / HINSPUR)**, undifferentiated from other non-group coverage. The ACS cannot isolate subsidized-marketplace enrollees.
- For NYS-specific subsidized enrollment — Qualified Health Plans **and the Essential Plan**, which is very large in New York — the authoritative source is **NY State of Health** open-enrollment reports (administrative counts), not survey microdata.

---

## 6. Stage 2 (next)

After review of the Stage 1 table, Stage 2 will profile the **geography and demographics of Medicaid-or-uninsured workers**, with industries aggregated into groups defined by these results. The `medicaid_or_uninsured` flag is already built in `hcra.r` and carried in `hcra_stage1_tidy.csv`.

---

## Files

| File | Description |
|---|---|
| `hcra.r` | Full analysis script |
| `hcra_stage1_counts.csv` | Worker counts (estimates) — main review table |
| `hcra_stage1_moe.csv` | Margins of error (90% CI) |
| `hcra_stage1_tidy.csv` | Long-form output for pivoting |
| `psam_p36.csv` | 2024 ACS 5-year PUMS person records, NY (input; not tracked) |
| `csv_pny.zip` | Original download (can be deleted after extraction) |

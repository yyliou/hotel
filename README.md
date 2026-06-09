# twhotelpanel

An R package that constructs a **hotel-by-month panel dataset** from the monthly
operating-statistics reports published by Taiwan's Tourism Administration
(交通部觀光署), series *Tourist Hotel Operating Statistics*
(觀光旅館營運統計). The package automates the full pipeline: it crawls the
official file listing, downloads the monthly workbooks, parses the per-hotel
operating tables, and assembles them into a single tidy panel suitable for
empirical analysis. The output is written as UTF-8 (BOM) CSV for direct use in
Excel, R, Stata, or Python.

Source listing: <https://admin.taiwan.net.tw/businessinfo/FilePage?a=10425>

---

## Installation

```r
# install.packages("remotes")
remotes::install_local("yyliou/twhotelpanel")
```

Dependencies:

```r
install.packages(c("httr2", "rvest", "xml2", "readxl", "dplyr", "tidyr",
                   "stringr", "purrr", "readr", "tibble", "rlang", "cli"))
```

R (>= 4.1) is required (the package uses the native `|>` pipe).

---

## Quick start

```r
library(twhotelpanel)

# 1. Enumerate the available reports (XLSX variants by default).
reports <- htp_list_reports()
head(reports)

# 2. Build the panel for a chosen period and write it to CSV.
panel <- htp_build_panel(
  start_ym = 202301,   # inclusive lower bound, YYYYMM
  end_ym   = 202512,   # inclusive upper bound, YYYYMM
  out_csv  = "tourist_hotel_panel.csv"
)

# Either bound may be omitted (NULL) to leave that side unrestricted.
```

Each row of the resulting panel corresponds to one hotel observed in one month.
Variables (after standardization):

| Variable | Definition |
|---|---|
| `year`, `month` | Calendar year (Gregorian) and month of the observation |
| `hotel_type` | `international` (國際觀光旅館) or `standard` (一般觀光旅館) |
| `region` | Administrative region, propagated from group-header rows |
| `hotel_name` | Name of the establishment |
| `rooms_available` | Number of guest rooms available |
| `rooms_occupied` | Number of rooms occupied |
| `occupancy_rate` | Room occupancy rate |
| `avg_room_rate` | Average daily room rate (NT$) |
| `room_revenue` | Room revenue |
| `fnb_revenue` | Food-and-beverage revenue |
| `other_revenue` | Other revenue |
| `total_revenue` | Total operating revenue |
| `guests` | Number of guests accommodated |
| `employees` | Number of employees |
| `sheet`, `source_file` | Provenance: originating worksheet and source filename |

---

## Calibrating the column mapping (please read)

The header wording of these government workbooks changes incrementally across
years, and the package was authored without direct network access to the source
site, so the column-to-variable assignment in `htp_parse_report()` is a
**best-effort, user-configurable heuristic** rather than a verified mapping.
Before relying on the panel, inspect the actual layout of one workbook and
adjust the mapping if necessary:

```r
# Download one file and examine its raw layout.
path   <- htp_download(reports$file_id[1])
layout <- htp_inspect(path)        # leading rows of each worksheet
layout[["國際觀光旅館"]]            # observe the actual header wording
attr(layout[[1]], "header_row")    # the inferred header-row index

# The column map: keys are output variables, values are header-matching regexes.
cm <- htp_default_colmap()
cm$avg_room_rate <- "平均房價|平均實收房價"   # adjust to the observed wording
cm$total_revenue <- "營業收入合計|總收入"

panel <- htp_build_panel(start_ym = 202401, colmap = cm)
```

The `hotel_sheets` argument of `htp_parse_report()` (which worksheets contain
per-hotel detail) can likewise be overridden; it defaults to the regex
`國際觀光旅館|一般觀光旅館|觀光旅館`.

---

## Function reference

- `htp_list_reports(formats = "XLSX")` — crawls all listing pages and returns,
  for each file, its `period`, `year`, `month`, `format`, `file_id`, and `url`.
- `htp_download(file_id, dest_dir = "htp_cache")` — downloads a file by id, with
  on-disk caching (existing files are not re-fetched).
- `htp_inspect(path)` — dumps the raw layout of each worksheet for calibration.
- `htp_parse_report(path, year, month, colmap =, hotel_sheets =)` — parses a
  single workbook into tidy hotel-month rows.
- `htp_build_panel(start_ym, end_ym, out_csv =)` — runs the complete pipeline.
- `roc_to_ad("115-06-09")` — converts a Republic-of-China (Minguo) date to the
  Gregorian calendar (115 → 2026).

---

## Design notes

- **Cumulative files** (e.g. `202401-12`, `202601-03`) are **excluded by
  default**; only single-month files (`period_type == "monthly"`) enter the
  panel, which prevents double counting of months.
- Network requests use a descriptive user agent, automatic retries, and a
  configurable `throttle` delay, and downloads are cached to limit load on the
  source server.
- Aggregate rows (subtotals, totals, and averages) are removed automatically, so
  only individual-hotel observations are retained.
- Output is written as UTF-8 with a byte-order mark, allowing Excel to open the
  CSV without character-encoding errors.

## Reproducibility and citation

The cache directory (`htp_cache/` by default) retains every downloaded source
file, so a constructed panel can be reproduced and audited against the original
workbooks. When using these data, cite the Tourism Administration, Ministry of
Transportation and Communications (Taiwan) as the source and observe the
applicable open-data and copyright terms.

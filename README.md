# twhotel 

## 1. Overview <img src="man/figures/logo.png" align="right" height="139" alt="twhotel hex logo" />

`twhotel` builds a **hotel-by-month panel dataset** from the Taiwan Tourism
Administration (交通部觀光署) monthly series *Tourist Hotel Operating Statistics*
(觀光旅館營運統計). The package crawls the official file listing, downloads the
monthly workbooks, parses the per-hotel **operations** and **guest** tables, and
combines them into one tidy panel ready for empirical analysis.

Source listing: <https://admin.taiwan.net.tw/businessinfo/FilePage?a=10425>

> [!WARNING]
> **Only data from June 2020 (`202006`) onward is stable.** Earlier reports use
> inconsistent workbook layouts, so values before `202006` may be incomplete or
> misaligned. For reliable panel analysis set `start_ym = 202006` (or later).

```r
# install.packages("remotes")
remotes::install_github("yyliou/hotel")
```

Requires R (>= 4.1, for the native `|>` pipe). Imports `httr2`, `rvest`,
`readxl`, `dplyr`, `stringr`, `tibble`, `readr`, `cli`. The `man/*.Rd` help
pages are not checked in; run `roxygen2::roxygenise()` (or `devtools::document()`)
once to build them.

## 2. Functions

| Function | Purpose |
|---|---|
| `htp_build_panel()` | Main function: the full pipeline — list → download → parse → bind → CSV. |
| `htp_list_reports()` | Enumerate every downloadable report (period, format, id, url). |
| `htp_download()` | Fetch one report by id, with on-disk caching. |
| `htp_parse_report()` | Parse one workbook into tidy hotel-month rows. |
| `htp_inspect()` | Dump a workbook's raw layout (for calibration). |
| `roc_to_ad()` | Convert a Republic-of-China (Minguo) year/date to the Gregorian calendar. |

## 3. Arguments

**`htp_build_panel(start_ym, end_ym, out_csv, cache_dir, formats, reports, overwrite, throttle, verbose)`**

| Argument | Description | Default |
|---|---|---|
| `start_ym`, `end_ym` | Inclusive period bounds as `YYYYMM` integers (e.g. `202301`). `NULL` leaves that side open. | `NULL` |
| `out_csv` | Path to write the panel (UTF-8 with BOM). `NULL` to skip. | `"tourist_hotel_panel.csv"` |
| `cache_dir` | Directory for downloaded source files. | `"htp_cache"` |
| `formats` | File format to download/parse. | `"XLSX"` |
| `reports` | Optional pre-fetched `htp_list_reports()` tibble. | `NULL` |
| `overwrite` | Re-download cached files. | `FALSE` |
| `throttle` | Seconds between network requests. | `0.5` |
| `verbose` | Progress messages via `cli`. | `TRUE` |

**Other functions.** `htp_list_reports(formats = "XLSX", max_pages = NULL,
throttle = 0.5, verbose = TRUE)`; `htp_download(file_id, dest_dir = "htp_cache",
ext = "xlsx", overwrite = FALSE, throttle = 0.5)`; `htp_parse_report(path, year =
NULL, month = NULL, guests = TRUE, verbose = TRUE)` — set `guests = FALSE` for
operations columns only; `htp_inspect(path, n = 25)`; `roc_to_ad(x, full =
FALSE)`.

Only **single-month** files are used; cumulative range files (e.g. `202401-12`)
are skipped so months are never double-counted.

## 4. Output codebook

`htp_build_panel()` / `htp_parse_report()` return one row per hotel per month.

**Identity** — `year`, `month`, `region` (地區), `hotel_type` (`international`
國際 / `standard` 一般), `hotel_name`, `hotel_name_en`, `source_file`.

**Operations** — `rooms_available` (房間數), `rooms_occupied` (客房住用數),
`occupancy_rate` (住用率, a fraction), `avg_room_rate` (平均房價), `room_revenue`
(房租收入), `fnb_revenue` (餐飲收入), `other_revenue` (= total − room − F&B),
`total_revenue` (總營業收入).

**Employees by department** — `emp_room_*`, `emp_fnb_*`, `emp_admin_*`,
`emp_other_*` (each suffixed `_m` 男 / `_f` 女 / `_total` 人數) plus `emp_m`,
`emp_f`, `employees` (員工合計).

**Guests** (when `guests = TRUE`) — `guests_fit` (個別), `guests_group` (團體),
`guests_total`, plus 28 nationalities/regions: `guests_domestic` (本國),
`guests_china`, `guests_japan`, `guests_korea`, `guests_hk_macao`,
`guests_singapore`, `guests_malaysia`, `guests_thailand`, `guests_indonesia`,
`guests_vietnam`, `guests_philippines`, `guests_brunei`, `guests_myanmar`,
`guests_laos`, `guests_cambodia`, `guests_india`, `guests_middle_east`,
`guests_russia`, `guests_usa`, `guests_canada`, `guests_latin_america`,
`guests_uk`, `guests_europe_other`, `guests_anz`, `guests_africa`,
`guests_other`.

`htp_list_reports()` returns `title`, `period` (e.g. `"202512"` or a range
`"202501-12"`), `period_type` (`"monthly"`/`"cumulative"`), `year`, `month`,
`format`, `file_id`, `url`. ROC-year titles (e.g. `104年12月`) are converted to
the Gregorian calendar automatically.

## 5. Examples

```r
library(twhotel)

# List available reports (XLSX by default):
reports <- htp_list_reports()
head(reports[, c("period", "year", "month", "file_id")])

# Build the panel for 2023-01 .. 2025-12 and write a CSV:
panel <- htp_build_panel(
  start_ym = 202301,
  end_ym   = 202512,
  out_csv  = "tourist_hotel_panel.csv"
)

# Inspect a workbook's raw layout (for calibration):
path <- htp_download(reports$file_id[1])
lay  <- htp_inspect(path)
lay[[1]]
```

Downloads are cached under `htp_cache/`, so re-runs are fast and reproducible.
The CSV is written as UTF-8 with a byte-order mark, so Excel opens it without
mojibake.

## 6. Notes

- The parser targets the current workbook layout (a single `Sheet1` with a
  region-summary table, per-region operations blocks, then a per-hotel guest
  section). Hotel type comes from the `*` prefix the source uses for 一般
  (standard) hotels; region is recovered by matching each block's `總計`
  total-revenue to the region summary's `小計`. If a future file changes shape,
  use `htp_inspect()` to recalibrate.
- Region totals reconcile with the report's own grand totals, and each hotel's
  `guests_total` equals FIT + group equals the sum across nationalities — these
  identities were checked against a real monthly file.
- A monthly report yields roughly 116 hotels (≈ 71 international + 45 standard);
  the figure grows as new hotels open.

## 7. Data source & citation

Data source: Tourism Administration, MOTC (Taiwan), *Tourist Hotel Operating
Statistics* (觀光旅館營運統計),
<https://admin.taiwan.net.tw/businessinfo/FilePage?a=10425>. Please observe the
provider's open-data / copyright terms when redistributing.

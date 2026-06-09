# twhotel <img src="man/figures/logo.png" align="right" height="138" alt="twhotel hex logo" />

Build a **hotel-by-month panel dataset** from the Taiwan Tourism Administration
(交通部觀光署) monthly series *Tourist Hotel Operating Statistics*
(觀光旅館營運統計). The package crawls the official file listing, downloads the
monthly workbooks, parses the per-hotel **operations** and **guest** tables, and
combines them into one tidy panel — ready for empirical / panel analysis.

Source listing: <https://admin.taiwan.net.tw/businessinfo/FilePage?a=10425>

> [!WARNING]
> **Only data from June 2020 (`202006`) onward is stable.** Earlier reports use
> inconsistent workbook layouts and reporting conventions, so values before
> `202006` may be incomplete or misaligned. For reliable panel analysis, set
> `start_ym = 202006` (or later) and treat anything earlier as provisional.

The package gives you five functions:

| Function              | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `htp_list_reports()`  | 月報清單 — enumerate every downloadable report (period, format, id, url)   |
| `htp_download()`      | 下載 — fetch one report by id, with on-disk caching                       |
| `htp_inspect()`       | 檢視版面 — dump a workbook's raw layout (for calibration)                  |
| `htp_parse_report()`  | 解析單檔 — parse one workbook into tidy hotel-month rows                    |
| `htp_build_panel()`   | 組 panel — the full pipeline: list → download → parse → bind → CSV        |

## Install

```r
# install.packages("remotes")
remotes::install_github("yyliou/hotel")
```

Imports `httr2`, `rvest`, `readxl`, `dplyr`, `stringr`, `tibble`, `readr`, `cli`.
R (>= 4.1) is required (the package uses the native `|>` pipe).

The functions carry roxygen comments but the `man/*.Rd` help pages aren't checked
in. To build them (and pass `R CMD check`), run once:

```r
# install.packages("roxygen2")
roxygen2::roxygenise()    # or devtools::document()
```

## 1. List available reports

```r
library(twhotel)

reports <- htp_list_reports()          # XLSX variants by default
head(reports[, c("period", "year", "month", "file_id")])
```

Returns one row per downloadable file with `period` (e.g. `"202512"` or a range
like `"202501-12"`), `period_type` (`"monthly"` / `"cumulative"`), `year`,
`month`, `format`, `file_id`, and `url`. Titles in older Republic-of-China year
form (e.g. `104年12月`) are converted to the Gregorian calendar automatically.

## 2. Build the panel

```r
panel <- htp_build_panel(
  start_ym = 202301,    # inclusive lower bound, YYYYMM
  end_ym   = 202512,    # inclusive upper bound, YYYYMM
  out_csv  = "tourist_hotel_panel.csv"
)
```

Either bound may be omitted (`NULL`) to leave that side open. Only **single-month**
files are used; cumulative range files (e.g. `202401-12`) are skipped so months
are never double-counted. Downloads are cached under `htp_cache/`, so re-runs are
fast and the panel stays reproducible against the original workbooks. The CSV is
written as UTF-8 with a byte-order mark, so Excel opens it without mojibake.

Each row is one hotel in one month. Columns:

**Identity** — `year`, `month`, `region` (地區), `hotel_type`
(`international` 國際 / `standard` 一般), `hotel_name`, `hotel_name_en`.

**Operations** — `rooms_available` (房間數), `rooms_occupied` (客房住用數),
`occupancy_rate` (住用率, a fraction), `avg_room_rate` (平均房價),
`room_revenue` (房租收入), `fnb_revenue` (餐飲收入),
`other_revenue` (= total − room − F&B), `total_revenue` (總營業收入).

**Employees by department** — `emp_room_*`, `emp_fnb_*`, `emp_admin_*`,
`emp_other_*` (each `_m` 男 / `_f` 女 / `_total` 人數) and `emp_m` / `emp_f` /
`employees` (員工合計).

**Guests** — `guests_fit` (個別), `guests_group` (團體), `guests_total`, plus 28
nationalities/regions: `guests_domestic` (本國), `guests_china`, `guests_japan`,
`guests_korea`, `guests_hk_macao`, `guests_singapore`, `guests_malaysia`,
`guests_thailand`, `guests_indonesia`, `guests_vietnam`, `guests_philippines`,
`guests_brunei`, `guests_myanmar`, `guests_laos`, `guests_cambodia`,
`guests_india`, `guests_middle_east`, `guests_russia`, `guests_usa`,
`guests_canada`, `guests_latin_america`, `guests_uk`, `guests_europe_other`,
`guests_anz`, `guests_africa`, `guests_other`.

Pass `htp_parse_report(..., guests = FALSE)` (or use it directly) if you only
want the operations columns.

## 3. Calibrating / inspecting

The parser targets the current workbook layout (a single `Sheet1` containing a
region-summary table, then per-region blocks of individual hotels for operations,
then a second per-hotel section for guests by nationality). If a future file
changes shape, inspect it and adjust:

```r
path <- htp_download(reports$file_id[1])
lay  <- htp_inspect(path)        # leading rows of each worksheet
lay[[1]]
```

The hotel type comes from the `*` prefix the source uses for 一般 (standard)
hotels; region is recovered by matching each block's `總計` total-revenue to the
region summary's `小計`.

## Notes

- Region totals reconcile with the report's own grand totals, and each hotel's
  `guests_total` equals FIT + group equals the sum across nationalities — these
  identities were checked against a real monthly file.
- A monthly report yields roughly 116 hotels (≈ 71 international + 45 standard);
  the figure grows as new hotels open.
- Data source & terms: Tourism Administration, MOTC (Taiwan). Please observe the
  provider's open-data / copyright terms when redistributing.

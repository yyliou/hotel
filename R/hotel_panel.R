# =============================================================================
# hotel_panel.R  —  standalone script version (no package install needed)
#
# Usage:
#   source("hotel_panel.R")        # defines the functions in your environment
#   reports <- htp_list_reports()  # then call them directly
#
# Edit + re-source freely while debugging. This is the same logic as the
# package, flattened to top-level functions.
# =============================================================================

library(httr2)
library(rvest)
library(xml2)
library(readxl)
library(dplyr)
library(stringr)
library(tibble)
library(readr)
library(cli)

# --- constants ---------------------------------------------------------------
.htp_base    <- "https://admin.taiwan.net.tw"
.htp_listing <- "https://admin.taiwan.net.tw/businessinfo/FilePage?a=10425"
.htp_attfile <- "https://admin.taiwan.net.tw/fapi/AttFile?type=AttFile&id=%s"
.htp_ua      <- "twhotelpanel R script (contact: yuyou.liou@gmail.com)"

# --- helpers -----------------------------------------------------------------

roc_to_ad <- function(x, full = FALSE) {
  x <- as.character(x)
  parts <- str_match(x, "^\\s*(\\d{1,3})(?:-(\\d{1,2})-(\\d{1,2}))?")
  ad_year <- suppressWarnings(as.integer(parts[, 2])) + 1911L
  if (!full) return(ad_year)
  ifelse(is.na(parts[, 3]), as.character(ad_year),
         sprintf("%04d-%02d-%02d", ad_year,
                 as.integer(parts[, 3]), as.integer(parts[, 4])))
}

# Type-stable period parser. ALWAYS returns character period/period_type and
# integer year/month, so per-page tibbles can be row-bound even when nothing
# matches. Handles Western single (202512), Western range (202501-12), and
# ROC single month (104年12月).
.htp_period_from_title <- function(x) {
  x <- as.character(x)
  n <- length(x)
  period      <- rep(NA_character_, n)
  period_type <- rep(NA_character_, n)
  year        <- rep(NA_integer_, n)
  month       <- rep(NA_integer_, n)

  m <- str_match(x, "(\\d{4})(\\d{2})-(\\d{2,6})")            # 1) Western range
  hit <- !is.na(m[, 1])
  period[hit] <- m[hit, 1]; period_type[hit] <- "cumulative"

  todo <- is.na(period)                                       # 2) Western month
  m <- str_match(x, "(?<!\\d)(\\d{4})(\\d{2})(?!\\d|-)")
  hit <- todo & !is.na(m[, 1])
  period[hit] <- paste0(m[hit, 2], m[hit, 3]); period_type[hit] <- "monthly"
  year[hit]  <- suppressWarnings(as.integer(m[hit, 2]))
  month[hit] <- suppressWarnings(as.integer(m[hit, 3]))

  todo <- is.na(period)                                       # 3) ROC month
  m <- str_match(x, "(\\d{2,3})\\s*年\\s*(\\d{1,2})\\s*月")
  hit <- todo & !is.na(m[, 1])
  ry <- suppressWarnings(as.integer(m[hit, 2])) + 1911L
  rmo <- suppressWarnings(as.integer(m[hit, 3]))
  period[hit] <- sprintf("%04d%02d", ry, rmo); period_type[hit] <- "monthly"
  year[hit] <- ry; month[hit] <- rmo

  tibble(period = period, period_type = period_type, year = year, month = month)
}

.htp_as_num <- function(x) {
  if (is.numeric(x)) return(x)
  x <- as.character(x)
  x <- str_replace_all(x, "[,，%\\s]", "")
  x <- str_replace_all(x, "[–—−]", "-")
  x[x %in% c("", "-", "–", "NA", "N/A", "...", "…")] <- NA
  suppressWarnings(as.numeric(x))
}

.htp_clean_str <- function(x) {
  x <- as.character(x)
  x <- str_replace_all(x, "　", " ")
  x <- str_squish(x)
  x[x == ""] <- NA
  x
}

.htp_is_summary_row <- function(name) {
  str_detect(as.character(name),
             "合計|小計|總計|總和|平均|小結|全國|Total|total")
}

.htp_write_csv_bom <- function(df, path) {
  con <- file(path, open = "wb", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  writeBin(charToRaw(enc2utf8(format_csv(df))), con)
  invisible(path)
}

# --- listing -----------------------------------------------------------------

.htp_fetch_listing_page <- function(p) {
  url <- sprintf("%s&P=%d", .htp_listing, p)
  resp <- request(url) |>
    req_user_agent(.htp_ua) |> req_retry(max_tries = 4) |>
    req_timeout(60) |> req_perform()
  read_html(resp_body_string(resp))
}

.htp_detect_total_pages <- function(html) {
  hrefs <- html |> html_elements("a") |> html_attr("href")
  hrefs <- hrefs[!is.na(hrefs)]
  ps <- suppressWarnings(as.integer(str_match(hrefs, "[?&]P=(\\d+)")[, 2]))
  ps <- ps[!is.na(ps)]
  if (!length(ps)) 1L else max(ps)
}

.htp_parse_listing_page <- function(html) {
  links <- html |> html_elements("a")
  href  <- html_attr(links, "href")
  title <- html_attr(links, "title")
  keep  <- !is.na(href) & str_detect(href, "fapi/AttFile")
  href  <- href[keep]; title <- title[keep]

  if (!length(href)) {
    return(tibble(title = character(), period = character(),
                  period_type = character(), year = integer(),
                  month = integer(), format = character(),
                  file_id = character(), url = character(),
                  updated = character()))
  }

  file_id <- str_match(href, "id=(\\d+)")[, 2]
  url <- ifelse(str_detect(href, "^https?://"), href, paste0(.htp_base, href))

  report_title <- .htp_clean_str(str_replace(title, "\\s*檔案格式.*$", ""))
  format <- toupper(str_match(title, "檔案格式[:：]\\s*([A-Za-z]+)")[, 2])

  pp <- .htp_period_from_title(report_title)

  tibble(title = report_title, period = pp$period,
         period_type = pp$period_type, year = pp$year, month = pp$month,
         format = format, file_id = file_id, url = url,
         updated = NA_character_) |>
    filter(!is.na(file_id))
}

htp_list_reports <- function(formats = "XLSX", max_pages = NULL,
                             throttle = 0.5, verbose = TRUE) {
  formats <- toupper(formats)
  first <- .htp_fetch_listing_page(1L)
  total_pages <- .htp_detect_total_pages(first)
  if (!is.null(max_pages)) total_pages <- min(total_pages, max_pages)
  if (verbose) cli_inform("Listing has {total_pages} page(s).")

  pages <- vector("list", total_pages)
  pages[[1]] <- .htp_parse_listing_page(first)
  if (total_pages >= 2) for (p in 2:total_pages) {
    if (verbose) cli_inform("Fetching listing page {p}/{total_pages} ...")
    Sys.sleep(throttle)
    pages[[p]] <- .htp_parse_listing_page(.htp_fetch_listing_page(p))
  }

  out <- bind_rows(pages) |> distinct(file_id, .keep_all = TRUE)
  if (!is.null(formats) && length(formats)) out <- filter(out, format %in% formats)
  arrange(out, desc(period), format)
}

# --- download ----------------------------------------------------------------

htp_download <- function(file_id, dest_dir = "htp_cache", ext = "xlsx",
                         overwrite = FALSE, throttle = 0.5) {
  file_id <- as.character(file_id)
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
  path <- file.path(dest_dir, sprintf("attfile_%s.%s", file_id, ext))
  if (file.exists(path) && !overwrite && file.info(path)$size > 0) return(invisible(path))
  Sys.sleep(throttle)
  resp <- request(sprintf(.htp_attfile, file_id)) |>
    req_user_agent(.htp_ua) |> req_retry(max_tries = 4) |>
    req_timeout(120) |> req_perform()
  writeBin(resp_body_raw(resp), path)
  path
}

# --- parsing -----------------------------------------------------------------

# Ordered (output_name = header-substring) maps. Order matters: more specific
# keys must come BEFORE less specific ones (e.g. 歐洲其他地區 before 其他地區),
# because each column is assigned to the first matching, not-yet-used key.
# Parentheses/whitespace are stripped from headers before matching, so the
# department headers "客房部(男) Room Dep." match the key "客房部男".

# OPERATIONS section: occupancy/revenue + employees by department.
.htp_ops_pairs <- function() c(
  rooms_available = "客房數",      # available rooms (distinct from 客房住用數)
  rooms_occupied  = "客房住用數",   # rooms occupied
  occupancy_rate  = "住用率",       # occupancy rate (a fraction)
  avg_room_rate   = "平均房價",     # average room rate (NT$)
  room_revenue    = "房租收入",
  fnb_revenue     = "餐飲收入",
  total_revenue   = "總營業收入",
  emp_room_m      = "客房部男",  emp_room_f  = "客房部女",  emp_room_total  = "客房部人數",
  emp_fnb_m       = "餐飲部男",  emp_fnb_f   = "餐飲部女",  emp_fnb_total   = "餐飲部人數",
  emp_admin_m     = "管理部男",  emp_admin_f = "管理部女",  emp_admin_total = "管理部人數",
  emp_other_m     = "其他部門男", emp_other_f = "其他部門女", emp_other_total = "其他部門人數",
  emp_m           = "員工合計男", emp_f       = "員工合計女", employees       = "員工合計人數"
)

# GUESTS section: by booking type (FIT / group) and by nationality.
.htp_guest_pairs <- function() c(
  guests_fit = "FIT類別", guests_group = "GROUP類別", guests_total = "類別合計",
  guests_domestic = "本國", guests_china = "中國大陸", guests_japan = "日本",
  guests_korea = "南韓", guests_hk_macao = "港澳", guests_singapore = "新加坡",
  guests_malaysia = "馬來西亞", guests_thailand = "泰國", guests_indonesia = "印尼",
  guests_vietnam = "越南", guests_philippines = "菲律賓", guests_brunei = "汶萊",
  guests_myanmar = "緬甸", guests_laos = "寮國", guests_cambodia = "柬埔寨",
  guests_india = "印度", guests_middle_east = "中東", guests_russia = "俄羅斯",
  guests_usa = "美國", guests_canada = "加拿大", guests_latin_america = "中南美洲",
  guests_uk = "英國", guests_europe_other = "歐洲其他地區", guests_anz = "紐澳",
  guests_africa = "非洲", guests_other = "其他地區"
)

# Map each output name to a column index by scanning the header row left->right
# and assigning each column to the first matching, not-yet-used keyword.
.htp_map_cols <- function(raw, hr, pairs) {
  nc <- ncol(raw)
  cols <- setNames(rep(NA_integer_, length(pairs)), names(pairs))
  used <- character(0)
  hdr <- gsub("[（）()[:space:]]", "",
              as.character(unlist(raw[hr, ], use.names = FALSE)))
  for (cc in seq_len(nc)) {
    h <- hdr[cc]
    if (is.na(h) || !nzchar(h)) next
    for (k in names(pairs)) {
      if (k %in% used) next
      if (str_detect(h, fixed(pairs[[k]]))) { cols[[k]] <- cc; used <- c(used, k); break }
    }
  }
  cols
}

# Row indices of the hotel rows in the block starting at header row `hr`
# (stops at the 總計 row, the next block header, or end of sheet).
.htp_block_rows <- function(cA, hr, nr) {
  i <- hr + 1L; idx <- integer(0); trow <- NA_integer_
  while (i <= nr) {
    a <- cA[i]
    if (!is.na(a) && str_detect(a, "總計")) { trow <- i; break }
    if (!is.na(a) && str_detect(a, "旅館名稱|彙整")) break
    if (!is.na(a) && nzchar(str_squish(a))) idx <- c(idx, i)
    i <- i + 1L
  }
  list(idx = idx, total_row = trow)
}

# Split a raw col-A name cell into clean Chinese name, English name, and type.
# Names beginning with "*" are 一般 (standard) tourist hotels.
.htp_split_name <- function(raw_name) {
  cn <- str_squish(str_replace(raw_name, "[\r\n].*$", ""))
  en <- str_squish(str_replace(raw_name, "^[^\r\n]*[\r\n]", ""))
  en[en == cn] <- NA_character_
  htype <- ifelse(str_detect(cn, "^\\*"), "standard", "international")
  cn <- str_squish(str_replace(cn, "^\\*", ""))
  list(cn = cn, en = en, htype = htype)
}

.htp_read_sheet_text <- function(path, sheet, max_rows = Inf) {
  df <- suppressWarnings(suppressMessages(
    read_excel(path, sheet = sheet, col_names = FALSE,
               col_types = "text", .name_repair = "minimal")))
  if (is.finite(max_rows)) df <- head(df, max_rows)
  df
}

.htp_flatten <- function(df) apply(df, 1, function(r) paste(r[!is.na(r)], collapse = " "))

.htp_guess_header_row <- function(raw) {
  rows <- .htp_flatten(raw)
  idx <- which(str_detect(rows, "旅館名稱") & str_detect(rows, "總營業收入"))
  if (length(idx)) return(idx[1])
  idx <- which(str_detect(rows, "旅館名稱|地區名稱"))
  if (length(idx)) return(idx[1])
  NA_integer_
}

htp_inspect <- function(path, n = 25) {
  sheets <- excel_sheets(path)
  out <- lapply(sheets, function(s) {
    raw <- .htp_read_sheet_text(path, s)
    top <- head(raw, n)
    attr(top, "header_row") <- .htp_guess_header_row(raw)
    top
  })
  setNames(out, sheets)
}

# Helper: numeric value(s) at row(s) i, column index j (NA-safe).
.htp_cellnum <- function(raw, i, j) {
  if (is.na(j) || j < 1L || j > ncol(raw)) return(rep(NA_real_, length(i)))
  .htp_as_num(as.character(raw[[j]][i]))
}

# Parse the per-hotel OPERATIONS section (occupancy / revenue / employees).
#
# Workbook structure (single sheet "Sheet1"):
#   1. a region-summary table: 地區名稱(col A) x {國際 / 一般 / 小計}(col D);
#   2. repeating PER-REGION blocks of individual hotels:
#        title row -> "旅館名稱Hotel Name" header -> hotel rows -> "總計" row;
#   3. a SECOND per-hotel section (guests by nationality), parsed separately.
# Operations headers contain BOTH "旅館名稱" and "總營業收入". Region is
# recovered by matching each block's "總計" total-revenue to the region
# summary's "小計" total-revenue.
.htp_parse_operations <- function(raw) {
  nr <- nrow(raw)
  if (nr < 2L) return(NULL)
  cA <- as.character(raw[[1]])
  flat <- .htp_flatten(raw)

  hdr_rows <- which(str_detect(cA, "旅館名稱") & str_detect(flat, "總營業收入"))
  if (!length(hdr_rows)) return(NULL)

  cols <- .htp_map_cols(raw, hdr_rows[1], .htp_ops_pairs())
  tcol <- cols[["total_revenue"]]
  if (is.na(tcol)) return(NULL)

  # Region lookup: any row containing 小計 -> region is its col A; key by total.
  has_subtotal <- vapply(seq_len(nr),
    function(i) any(grepl("小計", as.character(unlist(raw[i, ], use.names = FALSE)))),
    logical(1))
  reg_keys <- character(0); reg_vals <- character(0)
  for (i in which(has_subtotal)) {
    a <- .htp_clean_str(cA[i])
    if (is.na(a) || str_detect(a, "類別|Kind|小計|總計")) next
    tot <- .htp_cellnum(raw, i, tcol)
    if (!is.na(tot)) { reg_keys <- c(reg_keys, sprintf("%.0f", tot)); reg_vals <- c(reg_vals, a) }
  }
  region_lookup <- setNames(reg_vals, reg_keys)

  metric_keys <- setdiff(names(cols), character(0))   # all ops columns
  out <- list()
  for (hr in hdr_rows) {
    blk <- .htp_block_rows(cA, hr, nr); idx <- blk$idx
    if (!length(idx)) next
    region <- NA_character_
    if (!is.na(blk$total_row)) {
      tot <- .htp_cellnum(raw, blk$total_row, tcol)
      if (!is.na(tot)) region <- unname(region_lookup[sprintf("%.0f", tot)])
    }
    nm <- .htp_split_name(cA[idx])
    vals <- lapply(metric_keys, function(k) .htp_cellnum(raw, idx, cols[[k]]))
    names(vals) <- metric_keys
    df <- tibble(region = region, hotel_type = nm$htype,
                 hotel_name = nm$cn, hotel_name_en = nm$en)
    for (k in metric_keys) df[[k]] <- vals[[k]]
    df$other_revenue <- df$total_revenue -
      coalesce(df$room_revenue, 0) - coalesce(df$fnb_revenue, 0)
    out[[length(out) + 1L]] <- df
  }
  if (!length(out)) return(NULL)
  res <- bind_rows(out)
  res[!is.na(res$hotel_name) & !str_detect(res$hotel_name, "總計|小計|合計"), , drop = FALSE]
}

# Parse the per-hotel GUESTS section (by booking type and nationality).
# Headers contain "旅館名稱" and "本國" (Domestic) but NOT "總營業收入".
# Returns one row per hotel keyed by cleaned hotel_name (for joining to ops).
.htp_parse_guests <- function(raw) {
  nr <- nrow(raw)
  if (nr < 2L) return(NULL)
  cA <- as.character(raw[[1]])
  flat <- .htp_flatten(raw)

  hdr_rows <- which(str_detect(cA, "旅館名稱") & str_detect(flat, "本國") &
                      !str_detect(flat, "總營業收入"))
  if (!length(hdr_rows)) return(NULL)

  cols <- .htp_map_cols(raw, hdr_rows[1], .htp_guest_pairs())
  gkeys <- names(cols)
  out <- list()
  for (hr in hdr_rows) {
    idx <- .htp_block_rows(cA, hr, nr)$idx
    if (!length(idx)) next
    nm <- .htp_split_name(cA[idx])
    df <- tibble(hotel_name = nm$cn)
    for (k in gkeys) df[[k]] <- .htp_cellnum(raw, idx, cols[[k]])
    out[[length(out) + 1L]] <- df
  }
  if (!length(out)) return(NULL)
  res <- bind_rows(out)
  res <- res[!is.na(res$hotel_name) & !str_detect(res$hotel_name, "總計|小計|合計"), , drop = FALSE]
  distinct(res, hotel_name, .keep_all = TRUE)
}

.htp_empty_panel <- function() tibble(
  year = integer(), month = integer(), region = character(),
  hotel_type = character(), hotel_name = character(), hotel_name_en = character(),
  rooms_available = numeric(), rooms_occupied = numeric(),
  occupancy_rate = numeric(), avg_room_rate = numeric(),
  room_revenue = numeric(), fnb_revenue = numeric(),
  other_revenue = numeric(), total_revenue = numeric(),
  employees = numeric(), source_file = character())

htp_parse_report <- function(path, year = NULL, month = NULL,
                             guests = TRUE, verbose = TRUE) {
  if (is.null(year) || is.null(month)) {
    tok <- str_match(basename(path), "(\\d{4})(\\d{2})")
    if (is.null(year))  year  <- suppressWarnings(as.integer(tok[, 2]))
    if (is.null(month)) month <- suppressWarnings(as.integer(tok[, 3]))
  }
  sheets <- excel_sheets(path)
  parts <- lapply(sheets, function(s) {
    raw <- tryCatch(.htp_read_sheet_text(path, s), error = function(e) NULL)
    if (is.null(raw)) return(NULL)
    o <- tryCatch(.htp_parse_operations(raw),
                  error = function(e) { if (verbose) cli_warn("Ops parse failed ({s}): {conditionMessage(e)}"); NULL })
    g <- if (isTRUE(guests)) tryCatch(.htp_parse_guests(raw), error = function(e) NULL) else NULL
    list(ops = o, guests = g)
  })
  ops <- bind_rows(lapply(parts, `[[`, "ops"))
  if (!nrow(ops)) {
    if (verbose) cli_warn("No hotel rows parsed from {basename(path)}.")
    return(.htp_empty_panel())
  }
  if (isTRUE(guests)) {
    gst <- bind_rows(lapply(parts, `[[`, "guests"))
    if (nrow(gst)) ops <- left_join(ops, distinct(gst, hotel_name, .keep_all = TRUE),
                                    by = "hotel_name")
  }
  ops$year <- as.integer(year); ops$month <- as.integer(month)
  ops$source_file <- basename(path)
  relocate(ops, year, month, region, hotel_type, hotel_name)
}

# --- pipeline ----------------------------------------------------------------

htp_build_panel <- function(start_ym = NULL, end_ym = NULL,
                            out_csv = "tourist_hotel_panel.csv",
                            cache_dir = "htp_cache", formats = "XLSX",
                            reports = NULL,
                            overwrite = FALSE, throttle = 0.5, verbose = TRUE) {
  if (is.null(reports))
    reports <- htp_list_reports(formats = formats, throttle = throttle, verbose = verbose)
  sel <- filter(reports, period_type == "monthly")
  sel$ym <- sel$year * 100L + sel$month
  if (!is.null(start_ym)) sel <- filter(sel, ym >= start_ym)
  if (!is.null(end_ym))   sel <- filter(sel, ym <= end_ym)
  sel <- arrange(sel, ym)
  if (!nrow(sel)) { cli_warn("No monthly reports matched the requested range."); return(.htp_empty_panel()) }
  if (verbose) cli_inform("Building panel from {nrow(sel)} report(s): {min(sel$ym)}-{max(sel$ym)}.")

  ext <- tolower(sel$format[1]); parts <- vector("list", nrow(sel))
  for (i in seq_len(nrow(sel))) {
    r <- sel[i, ]
    if (verbose) cli_inform("[{i}/{nrow(sel)}] {r$period} (id {r$file_id}) ...")
    path <- tryCatch(htp_download(r$file_id, cache_dir, ext, overwrite, throttle),
                     error = function(e) { cli_warn("Download failed: {conditionMessage(e)}"); NA_character_ })
    if (is.na(path)) next
    parts[[i]] <- tryCatch(
      htp_parse_report(path, r$year, r$month, verbose = verbose),
      error = function(e) { cli_warn("Parse failed for {r$period}: {conditionMessage(e)}"); NULL })
  }
  panel <- bind_rows(parts)
  if (!nrow(panel)) { cli_warn("No hotel rows parsed for any month in range."); return(.htp_empty_panel()) }
  panel <- arrange(panel, year, month, hotel_type, hotel_name)
  if (!is.null(out_csv) && nrow(panel)) {
    .htp_write_csv_bom(panel, out_csv)
    if (verbose) cli_inform("Wrote {nrow(panel)} rows to {out_csv}.")
  }
  panel
}

cli_inform("hotel_panel.R loaded. Try: reports <- htp_list_reports()")

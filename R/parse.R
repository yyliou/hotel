#' Default column map (raw Chinese header -> standardized variable)
#'
#' Each element is a regular expression matched (case-insensitively) against the
#' (possibly multi-row) header text of a column. The first column whose header
#' matches a pattern is assigned that standardized name. Override this and pass
#' your own to \code{htp_parse_report(colmap = ...)} if the real files differ.
#'
#' NOTE: These reports are published as government spreadsheets whose exact
#' header wording shifts over time. Run \code{htp_inspect()} on one file to see
#' the actual headers, then tweak this map. The keys below are the output
#' column names; the values are header-matching patterns.
#'
#' @return A named list of regex patterns.
#' @export
htp_default_colmap <- function() {
  list(
    hotel_name      = "旅館名稱|旅館名|^名稱$|飯店名稱|旅館$",
    rooms_available = "房間數|客房數|房數",
    rooms_occupied  = "住用(房間|客房)數|出租房間數|售出房間",
    occupancy_rate  = "住用率|客房住用率|出租率",
    avg_room_rate   = "平均房價|平均房租|平均實收房價|平均單價",
    room_revenue    = "客房收入|房租收入|住宿收入",
    fnb_revenue     = "餐飲收入|餐飲部",
    other_revenue   = "其他?收入|店租及其他|其它收入|附帶收入",
    total_revenue   = "營業收入合計|總營業收入|營業總收入|收入合計|總收入|營業收入",
    guests          = "住用人數|住客人?數|旅客人數|住宿人數",
    employees       = "員工人數|從業員工|員工數|職工人數"
  )
}

#' Inspect the raw layout of a downloaded report
#'
#' Reads every sheet as plain text and returns the top rows plus a guess at the
#' header row. Use this to calibrate \code{\link{htp_default_colmap}} and the
#' \code{hotel_sheets} pattern for the real files.
#'
#' @param path Path to an .xlsx/.ods file.
#' @param n Number of leading rows to return per sheet.
#' @return A named list (one element per sheet) of character tibbles, with the
#'   guessed header-row index stored in attribute \code{"header_row"}.
#' @export
htp_inspect <- function(path, n = 25) {
  sheets <- readxl::excel_sheets(path)
  out <- lapply(sheets, function(s) {
    raw <- .htp_read_sheet_text(path, s)
    hr <- .htp_guess_header_row(raw)
    top <- utils::head(raw, n)
    attr(top, "header_row") <- hr
    top
  })
  setNames(out, sheets)
}

#' Parse one monthly report into tidy hotel-by-month rows
#'
#' @param path Path to the downloaded .xlsx (or .ods) file.
#' @param year,month Integer period to stamp on every row. If \code{NULL},
#'   inferred from the file name token when possible.
#' @param hotel_sheets Regex selecting which sheets hold per-hotel operation
#'   tables. Default matches the international / standard tourist-hotel sheets.
#'   Pass \code{NULL} to attempt every sheet.
#' @param colmap A named list of header patterns; see \code{htp_default_colmap}.
#' @param region_from_group If TRUE, rows that carry a name but no numeric data
#'   are treated as region group headers and propagated to a \code{region}
#'   column.
#' @param verbose Emit progress / warnings.
#'
#' @return A tibble, one row per hotel-month, with standardized metric columns.
#' @export
htp_parse_report <- function(path,
                             year = NULL,
                             month = NULL,
                             hotel_sheets = "國際觀光旅館|一般觀光旅館|觀光旅館",
                             colmap = htp_default_colmap(),
                             region_from_group = TRUE,
                             verbose = TRUE) {

  if (is.null(year) || is.null(month)) {
    tok <- stringr::str_match(basename(path), "(\\d{4})(\\d{2})")
    if (is.null(year))  year  <- suppressWarnings(as.integer(tok[, 2]))
    if (is.null(month)) month <- suppressWarnings(as.integer(tok[, 3]))
  }

  sheets <- readxl::excel_sheets(path)
  chosen <- sheets
  if (!is.null(hotel_sheets)) {
    # Match either the sheet name or its textual content.
    hits <- vapply(sheets, function(s) {
      if (stringr::str_detect(s, hotel_sheets)) return(TRUE)
      raw <- .htp_read_sheet_text(path, s, max_rows = 12)
      any(stringr::str_detect(.htp_flatten(raw), hotel_sheets), na.rm = TRUE)
    }, logical(1))
    chosen <- sheets[hits]
  }
  if (!length(chosen)) {
    if (verbose) cli::cli_warn("No per-hotel sheets matched in {.file {basename(path)}}.")
    return(.htp_empty_panel())
  }

  parts <- lapply(chosen, function(s) {
    tryCatch(
      .htp_parse_sheet(path, s, colmap, region_from_group),
      error = function(e) {
        if (verbose) cli::cli_warn("Sheet {.val {s}} skipped: {conditionMessage(e)}")
        NULL
      }
    )
  })
  res <- dplyr::bind_rows(parts)
  if (!nrow(res)) return(.htp_empty_panel())

  res$year  <- as.integer(year)
  res$month <- as.integer(month)
  res$source_file <- basename(path)

  dplyr::relocate(res, "year", "month", "hotel_type", "region", "hotel_name")
}

# --- sheet-level parsing -------------------------------------------------

.htp_read_sheet_text <- function(path, sheet, max_rows = Inf) {
  df <- suppressWarnings(suppressMessages(
    readxl::read_excel(path, sheet = sheet, col_names = FALSE,
                       col_types = "text", .name_repair = "minimal")
  ))
  if (is.finite(max_rows)) df <- utils::head(df, max_rows)
  df
}

.htp_flatten <- function(df) {
  apply(df, 1, function(r) paste(r[!is.na(r)], collapse = " "))
}

# Guess the header row: first row mentioning a hotel-name keyword AND a metric.
.htp_guess_header_row <- function(raw) {
  rows <- .htp_flatten(raw)
  name_kw   <- "旅館名稱|旅館名|名稱|飯店"
  metric_kw <- "房間數|住用率|平均房價|收入|人數|客房"
  idx <- which(stringr::str_detect(rows, name_kw) &
                 stringr::str_detect(rows, metric_kw))
  if (length(idx)) return(idx[1])
  # fallback: first row that mentions several metrics
  idx2 <- which(stringr::str_count(rows, metric_kw) >= 1 &
                  stringr::str_detect(rows, "房間數|客房"))
  if (length(idx2)) return(idx2[1])
  NA_integer_
}

.htp_parse_sheet <- function(path, sheet, colmap, region_from_group) {
  raw <- .htp_read_sheet_text(path, sheet)
  hr <- .htp_guess_header_row(raw)
  if (is.na(hr)) stop("could not locate a header row")

  # Build column labels by stacking the detected header row with the one above
  # (gov tables frequently use 2-row headers).
  top <- max(1L, hr - 1L)
  hdr_block <- raw[top:hr, , drop = FALSE]
  labels <- vapply(seq_len(ncol(hdr_block)), function(j) {
    cells <- hdr_block[[j]]
    cells <- cells[!is.na(cells)]
    .htp_clean_str(paste(cells, collapse = ""))
  }, character(1))

  # Detect hotel type from sheet name / header area.
  ctx <- paste(c(sheet, .htp_flatten(utils::head(raw, hr))), collapse = " ")
  hotel_type <- dplyr::case_when(
    stringr::str_detect(ctx, "國際觀光旅館") ~ "international",
    stringr::str_detect(ctx, "一般觀光旅館") ~ "standard",
    TRUE ~ NA_character_
  )

  # Map columns -> standardized names.
  col_for <- function(pattern) {
    j <- which(stringr::str_detect(labels, stringr::regex(pattern, ignore_case = TRUE)))
    if (length(j)) j[1] else NA_integer_
  }
  mapping <- vapply(colmap, col_for, integer(1))
  if (is.na(mapping[["hotel_name"]])) stop("no hotel-name column found")

  data <- raw[(hr + 1L):nrow(raw), , drop = FALSE]

  # Assemble the standardized data frame.
  get_col <- function(key, numeric = TRUE) {
    j <- mapping[[key]]
    if (is.na(j)) return(rep(NA_real_, nrow(data)))
    v <- data[[j]]
    if (numeric) .htp_as_num(v) else .htp_clean_str(v)
  }

  df <- tibble::tibble(
    hotel_name      = .htp_clean_str(data[[mapping[["hotel_name"]]]]),
    rooms_available = get_col("rooms_available"),
    rooms_occupied  = get_col("rooms_occupied"),
    occupancy_rate  = get_col("occupancy_rate"),
    avg_room_rate   = get_col("avg_room_rate"),
    room_revenue    = get_col("room_revenue"),
    fnb_revenue     = get_col("fnb_revenue"),
    other_revenue   = get_col("other_revenue"),
    total_revenue   = get_col("total_revenue"),
    guests          = get_col("guests"),
    employees       = get_col("employees")
  )

  metric_cols <- setdiff(names(df), "hotel_name")
  has_data <- rowSums(!is.na(df[metric_cols])) > 0

  # Region group headers: a name with no numeric data.
  df$region <- NA_character_
  if (isTRUE(region_from_group)) {
    is_group <- !is.na(df$hotel_name) & !has_data &
      !.htp_is_summary_row(df$hotel_name)
    current <- NA_character_
    region <- character(nrow(df))
    for (i in seq_len(nrow(df))) {
      if (is_group[i]) current <- df$hotel_name[i]
      region[i] <- current
    }
    df$region <- region
    df <- df[!is_group, , drop = FALSE]
    has_data <- has_data[!is_group]
  }

  # Keep genuine hotel rows: a name, some data, not a subtotal/total.
  keep <- !is.na(df$hotel_name) & has_data & !.htp_is_summary_row(df$hotel_name)
  df <- df[keep, , drop = FALSE]

  df$hotel_type <- hotel_type
  df$sheet <- sheet
  df
}

.htp_empty_panel <- function() {
  tibble::tibble(
    year = integer(), month = integer(), hotel_type = character(),
    region = character(), hotel_name = character(),
    rooms_available = numeric(), rooms_occupied = numeric(),
    occupancy_rate = numeric(), avg_room_rate = numeric(),
    room_revenue = numeric(), fnb_revenue = numeric(),
    other_revenue = numeric(), total_revenue = numeric(),
    guests = numeric(), employees = numeric(),
    sheet = character(), source_file = character()
  )
}

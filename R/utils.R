# Internal helpers --------------------------------------------------------

# Base URL pieces for the Tourism Administration admin site.
.htp_base    <- "https://admin.taiwan.net.tw"
.htp_listing <- "https://admin.taiwan.net.tw/businessinfo/FilePage?a=10425"
.htp_attfile <- "https://admin.taiwan.net.tw/fapi/AttFile?type=AttFile&id=%s"
.htp_ua      <- "twhotelpanel R package (https://github.com/; contact: yuyou.liou@gmail.com)"

#' Convert a Republic-of-China (Minguo) year to a Western (AD) year
#'
#' ROC year + 1911 = AD year. Accepts the dotted form used on the site
#' (e.g. "115-06-09") and returns the AD year as an integer, or the full
#' converted date string when `full = TRUE`.
#'
#' @param x Character vector of ROC dates like "115-06-09" or ROC years.
#' @param full If TRUE return "YYYY-MM-DD"; otherwise the AD year only.
#' @return Integer year (default) or character date.
#' @export
roc_to_ad <- function(x, full = FALSE) {
  x <- as.character(x)
  parts <- stringr::str_match(x, "^\\s*(\\d{1,3})(?:-(\\d{1,2})-(\\d{1,2}))?")
  roc_year <- suppressWarnings(as.integer(parts[, 2]))
  ad_year  <- roc_year + 1911L
  if (!full) return(ad_year)
  ifelse(
    is.na(parts[, 3]),
    as.character(ad_year),
    sprintf("%04d-%02d-%02d", ad_year,
            as.integer(parts[, 3]), as.integer(parts[, 4]))
  )
}

# Coerce messy numeric strings ("1,234", "85.3%", "-", "－", "") to numeric.
.htp_as_num <- function(x) {
  if (is.numeric(x)) return(x)
  x <- as.character(x)
  x <- stringr::str_replace_all(x, "[,，%\\s]", "")
  x <- stringr::str_replace_all(x, "[–—−]", "-") # dashes
  x[x %in% c("", "-", "–", "NA", "N/A", "...", "…")] <- NA
  suppressWarnings(as.numeric(x))
}

# Trim + collapse internal whitespace; treat fullwidth spaces too.
.htp_clean_str <- function(x) {
  x <- as.character(x)
  x <- stringr::str_replace_all(x, "　", " ")  # ideographic space
  x <- stringr::str_squish(x)
  x[x == ""] <- NA
  x
}

# Rows that are subtotals / totals / averages rather than individual hotels.
.htp_is_summary_row <- function(name) {
  name <- as.character(name)
  stringr::str_detect(
    name,
    "合計|小計|總計|總和|平均|小結|總計|全國|合　計|Total|total"
  )
}

# Write a data frame to CSV with a UTF-8 BOM so Excel opens it cleanly.
.htp_write_csv_bom <- function(df, path) {
  con <- file(path, open = "wb", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)            # UTF-8 BOM
  txt <- readr::format_csv(df)
  writeBin(charToRaw(enc2utf8(txt)), con)
  invisible(path)
}

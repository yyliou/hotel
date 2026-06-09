#' List all available monthly hotel-operation reports
#'
#' Crawls every page of the Tourism Administration listing
#' (\code{FilePage?a=10425&P=1..N}) and extracts one row per downloadable file
#' (a report can have ODS / XLSX / PDF variants).
#'
#' @param formats Which file formats to keep. Default \code{"XLSX"}.
#' @param max_pages Safety cap on number of listing pages to crawl.
#'   \code{NULL} (default) auto-detects the last page.
#' @param throttle Seconds to sleep between page requests (be polite).
#' @param verbose Print progress with \pkg{cli}.
#'
#' @return A tibble with columns:
#'   \describe{
#'     \item{title}{Original report title, e.g. "202512觀光旅館營運月報".}
#'     \item{period}{Period token, e.g. "202512" or "202501-12".}
#'     \item{period_type}{"monthly" (single YYYYMM) or "cumulative" (a range).}
#'     \item{year, month}{Integer AD year / month (NA for cumulative ranges).}
#'     \item{format}{File format (XLSX / ODS / PDF).}
#'     \item{file_id}{AttFile numeric id used to download.}
#'     \item{url}{Direct download URL.}
#'     \item{updated}{Update date, converted ROC -> AD ("YYYY-MM-DD").}
#'   }
#' @export
htp_list_reports <- function(formats = "XLSX",
                             max_pages = NULL,
                             throttle = 0.5,
                             verbose = TRUE) {
  formats <- toupper(formats)

  first <- .htp_fetch_listing_page(1L)
  total_pages <- .htp_detect_total_pages(first$html)
  if (!is.null(max_pages)) total_pages <- min(total_pages, max_pages)
  if (verbose) cli::cli_inform("Listing has {total_pages} page(s).")

  pages <- vector("list", total_pages)
  pages[[1]] <- .htp_parse_listing_page(first$html)

  if (total_pages >= 2) {
    for (p in 2:total_pages) {
      if (verbose) cli::cli_inform("Fetching listing page {p}/{total_pages} ...")
      Sys.sleep(throttle)
      pg <- .htp_fetch_listing_page(p)
      pages[[p]] <- .htp_parse_listing_page(pg$html)
    }
  }

  out <- dplyr::bind_rows(pages)
  out <- dplyr::distinct(out, .data$file_id, .keep_all = TRUE)

  if (!is.null(formats) && length(formats)) {
    out <- dplyr::filter(out, .data$format %in% formats)
  }
  out <- dplyr::arrange(out, dplyr::desc(.data$period), .data$format)
  out
}

# --- internals -----------------------------------------------------------

.htp_fetch_listing_page <- function(p) {
  url <- sprintf("%s&P=%d", .htp_listing, p)
  resp <- httr2::request(url) |>
    httr2::req_user_agent(.htp_ua) |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_timeout(60) |>
    httr2::req_perform()
  html <- rvest::read_html(httr2::resp_body_string(resp))
  list(html = html, url = url)
}

.htp_detect_total_pages <- function(html) {
  # Pagination links look like ...FilePage?a=10425&P=15 ; take the max P seen.
  hrefs <- html |>
    rvest::html_elements("a") |>
    rvest::html_attr("href")
  hrefs <- hrefs[!is.na(hrefs)]
  m <- stringr::str_match(hrefs, "[?&]P=(\\d+)")
  ps <- suppressWarnings(as.integer(m[, 2]))
  ps <- ps[!is.na(ps)]
  if (!length(ps)) return(1L)
  max(ps)
}

.htp_parse_listing_page <- function(html) {
  # Each downloadable variant is an <a> pointing at fapi/AttFile with a
  # descriptive title attribute, e.g.
  #   "202512觀光旅館營運月報 檔案格式：XLSX(另開視窗)"
  links <- html |> rvest::html_elements("a")
  href  <- rvest::html_attr(links, "href")
  title <- rvest::html_attr(links, "title")

  keep <- !is.na(href) & stringr::str_detect(href, "fapi/AttFile")
  href  <- href[keep]
  title <- title[keep]
  if (!length(href)) {
    return(tibble::tibble(
      title = character(), period = character(), period_type = character(),
      year = integer(), month = integer(), format = character(),
      file_id = character(), url = character(), updated = character()
    ))
  }

  file_id <- stringr::str_match(href, "id=(\\d+)")[, 2]
  url <- ifelse(
    stringr::str_detect(href, "^https?://"),
    href,
    paste0(.htp_base, href)
  )

  # Title -> report name + format
  report_title <- stringr::str_replace(title, "\\s*檔案格式.*$", "")
  report_title <- .htp_clean_str(report_title)
  format <- stringr::str_match(title, "檔案格式[:：]\\s*([A-Za-z]+)")[, 2]
  format <- toupper(format)

  # Period token: 6-digit month OR a range like 202501-12 / 202601-03
  period <- stringr::str_match(report_title, "(\\d{6}(?:-\\d{2,6})?)")[, 2]
  period_type <- ifelse(stringr::str_detect(period, "-"), "cumulative", "monthly")
  year  <- ifelse(period_type == "monthly",
                  suppressWarnings(as.integer(substr(period, 1, 4))), NA_integer_)
  month <- ifelse(period_type == "monthly",
                  suppressWarnings(as.integer(substr(period, 5, 6))), NA_integer_)

  tibble::tibble(
    title = report_title,
    period = period,
    period_type = period_type,
    year = year,
    month = month,
    format = format,
    file_id = file_id,
    url = url,
    updated = NA_character_
  ) |>
    dplyr::filter(!is.na(.data$period), !is.na(.data$file_id))
}

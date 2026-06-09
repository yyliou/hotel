#' Build the full hotel-by-month panel
#'
#' End-to-end pipeline: list reports -> filter by date range -> download ->
#' parse -> bind into one panel -> (optionally) write a UTF-8-BOM CSV.
#'
#' @param start_ym,end_ym Integer period bounds as \code{YYYYMM}
#'   (e.g. \code{202301}, \code{202512}). \code{NULL} means unbounded.
#' @param out_csv Path to write the panel as CSV (UTF-8 with BOM, opens cleanly
#'   in Excel). \code{NULL} to skip writing.
#' @param cache_dir Directory for downloaded source files.
#' @param formats File format to download / parse. Default \code{"XLSX"}.
#' @param include_cumulative Also include the cumulative range files
#'   (e.g. "202401-12"). Default FALSE to avoid double-counting months.
#' @param reports Optionally supply a pre-fetched \code{htp_list_reports()}
#'   tibble to avoid re-crawling.
#' @param colmap Column map passed to \code{htp_parse_report}.
#' @param overwrite Re-download cached files. Default FALSE.
#' @param throttle Seconds between network requests.
#' @param verbose Progress messages.
#'
#' @return A tibble: the combined panel (also written to \code{out_csv}).
#' @export
htp_build_panel <- function(start_ym = NULL,
                            end_ym = NULL,
                            out_csv = "tourist_hotel_panel.csv",
                            cache_dir = "htp_cache",
                            formats = "XLSX",
                            include_cumulative = FALSE,
                            reports = NULL,
                            colmap = htp_default_colmap(),
                            overwrite = FALSE,
                            throttle = 0.5,
                            verbose = TRUE) {

  if (is.null(reports)) {
    reports <- htp_list_reports(formats = formats, throttle = throttle,
                                verbose = verbose)
  }

  sel <- reports
  if (!isTRUE(include_cumulative)) {
    sel <- dplyr::filter(sel, .data$period_type == "monthly")
  } else {
    sel <- dplyr::filter(sel, .data$period_type == "monthly")
    # cumulative files have a different internal layout; left out of the panel
    # by default. (Documented in README.)
  }

  sel$ym <- sel$year * 100L + sel$month
  if (!is.null(start_ym)) sel <- dplyr::filter(sel, .data$ym >= start_ym)
  if (!is.null(end_ym))   sel <- dplyr::filter(sel, .data$ym <= end_ym)
  sel <- dplyr::arrange(sel, .data$ym)

  if (!nrow(sel)) {
    cli::cli_warn("No monthly reports matched the requested range.")
    return(.htp_empty_panel())
  }

  if (verbose) {
    cli::cli_inform("Building panel from {nrow(sel)} monthly report(s): {min(sel$ym)}-{max(sel$ym)}.")
  }

  ext <- tolower(sel$format[1])
  parts <- vector("list", nrow(sel))
  for (i in seq_len(nrow(sel))) {
    r <- sel[i, ]
    if (verbose) cli::cli_inform("[{i}/{nrow(sel)}] {r$period} (id {r$file_id}) ...")
    path <- tryCatch(
      htp_download(r$file_id, dest_dir = cache_dir, ext = ext,
                   overwrite = overwrite, throttle = throttle),
      error = function(e) { cli::cli_warn("Download failed: {conditionMessage(e)}"); NA_character_ }
    )
    if (is.na(path)) next
    parts[[i]] <- tryCatch(
      htp_parse_report(path, year = r$year, month = r$month,
                       colmap = colmap, verbose = verbose),
      error = function(e) { cli::cli_warn("Parse failed for {r$period}: {conditionMessage(e)}"); NULL }
    )
  }

  panel <- dplyr::bind_rows(parts)
  panel <- dplyr::arrange(panel, .data$year, .data$month,
                          .data$hotel_type, .data$hotel_name)

  if (!is.null(out_csv) && nrow(panel)) {
    .htp_write_csv_bom(panel, out_csv)
    if (verbose) cli::cli_inform("Wrote {nrow(panel)} rows to {.file {out_csv}}.")
  }

  panel
}

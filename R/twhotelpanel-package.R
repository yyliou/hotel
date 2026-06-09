#' twhotelpanel: Taiwan tourist-hotel monthly reports -> panel data
#'
#' Scrape, download, parse, and combine the Tourism Administration
#' "觀光旅館營運統計" monthly reports into a hotel-by-month panel.
#'
#' Main entry points:
#' \itemize{
#'   \item \code{\link{htp_list_reports}} - enumerate available files.
#'   \item \code{\link{htp_download}} - fetch one file by id.
#'   \item \code{\link{htp_inspect}} - examine a file's raw layout.
#'   \item \code{\link{htp_parse_report}} - parse one file to tidy rows.
#'   \item \code{\link{htp_build_panel}} - run the whole pipeline.
#' }
#'
#' @keywords internal
"_PACKAGE"

#' twhotel: Taiwan tourist-hotel monthly reports as a panel dataset
#'
#' Scrape, download, parse, and combine the Tourism Administration
#' "Tourist Hotel Operating Statistics" (觀光旅館營運統計) monthly reports into a
#' tidy hotel-by-month panel.
#'
#' Entry points: [htp_list_reports()], [htp_download()], [htp_inspect()],
#' [htp_parse_report()], [htp_build_panel()].
#'
#' @keywords internal
#' @import dplyr
#' @import stringr
#' @importFrom httr2 request req_user_agent req_retry req_timeout req_perform resp_body_string resp_body_raw
#' @importFrom rvest read_html html_elements html_attr
#' @importFrom readxl read_excel excel_sheets
#' @importFrom tibble tibble
#' @importFrom readr format_csv
#' @importFrom cli cli_inform cli_warn
#' @importFrom stats setNames
#' @importFrom utils head
"_PACKAGE"

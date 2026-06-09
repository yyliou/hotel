#' Download a report file by its AttFile id
#'
#' @param file_id The numeric AttFile id (from \code{htp_list_reports()}).
#' @param dest_dir Directory to save into (created if needed).
#' @param ext File extension to use for the saved file (default "xlsx").
#' @param overwrite Re-download even if a cached copy exists. Default FALSE.
#' @param throttle Seconds to sleep before the request (politeness).
#'
#' @return The local file path (invisibly on cache hit).
#' @export
htp_download <- function(file_id,
                         dest_dir = "htp_cache",
                         ext = "xlsx",
                         overwrite = FALSE,
                         throttle = 0.5) {
  file_id <- as.character(file_id)
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
  path <- file.path(dest_dir, sprintf("attfile_%s.%s", file_id, ext))

  if (file.exists(path) && !overwrite && file.info(path)$size > 0) {
    return(invisible(path))
  }

  Sys.sleep(throttle)
  url <- sprintf(.htp_attfile, file_id)
  resp <- httr2::request(url) |>
    httr2::req_user_agent(.htp_ua) |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_timeout(120) |>
    httr2::req_perform()

  writeBin(httr2::resp_body_raw(resp), path)
  path
}

test_that("roc_to_ad converts Minguo years", {
  expect_equal(roc_to_ad("115-06-09"), 2026L)
  expect_equal(roc_to_ad("114"), 2025L)
  expect_equal(roc_to_ad("115-06-09", full = TRUE), "2026-06-09")
})

test_that("period parser is type-stable and handles all title forms", {
  pp <- twhotel:::.htp_period_from_title(c(
    "202512觀光旅館營運月報",       # Western single month
    "202501-12觀光旅館營運月報",    # Western cumulative range
    "104年12月觀光旅館營運統計",    # ROC single month -> 2015-12
    "觀光旅館營運統計使用說明"      # no period -> NA (still character)
  ))
  expect_type(pp$period_type, "character")     # never logical -> bind_rows safe
  expect_equal(pp$period, c("202512", "202501-12", "201512", NA))
  expect_equal(pp$period_type, c("monthly", "cumulative", "monthly", NA))
  expect_equal(pp$year, c(2025L, NA, 2015L, NA))
})

test_that("messy numeric cells coerce correctly", {
  f <- twhotel:::.htp_as_num
  expect_equal(f(c("1,234", "85.3%", "-", "－", "")),
               c(1234, 85.3, NA, NA, NA))
})

test_that("ordered column mapping disambiguates 歐洲其他地區 vs 其他地區", {
  raw <- tibble::tibble(
    A = c("旅館名稱Hotel Name"),
    B = c("歐洲其他地區Europe"),
    C = c("其他地區Other"))
  cols <- twhotel:::.htp_map_cols(raw, 1,
            c(europe_other = "歐洲其他地區", other = "其他地區"))
  expect_equal(unname(cols[["europe_other"]]), 2L)
  expect_equal(unname(cols[["other"]]), 3L)
})

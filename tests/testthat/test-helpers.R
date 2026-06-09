test_that("roc_to_ad converts Minguo years", {
  expect_equal(roc_to_ad("115-06-09"), 2026L)
  expect_equal(roc_to_ad("114"), 2025L)
  expect_equal(roc_to_ad("115-06-09", full = TRUE), "2026-06-09")
})

test_that("numeric coercion handles messy cells", {
  f <- twhotelpanel:::.htp_as_num
  expect_equal(f(c("1,234", "85.3%", "-", "－", "")), c(1234, 85.3, NA, NA, NA))
})

test_that("period token parsing distinguishes monthly vs cumulative", {
  titles <- c("202512觀光旅館營運月報", "202401-12觀光旅館營運月報",
              "202601-03觀光旅館營運月報")
  period <- stringr::str_match(titles, "(\\d{6}(?:-\\d{2,6})?)")[, 2]
  ptype  <- ifelse(stringr::str_detect(period, "-"), "cumulative", "monthly")
  expect_equal(period, c("202512", "202401-12", "202601-03"))
  expect_equal(ptype, c("monthly", "cumulative", "cumulative"))
})

test_that("summary rows are detected", {
  f <- twhotelpanel:::.htp_is_summary_row
  expect_true(all(f(c("合計", "小計", "平均", "總計"))))
  expect_false(f("圓山大飯店"))
})

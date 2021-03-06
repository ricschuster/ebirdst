context("PPM functions")
context("compute_ppms")

test_that("ebirdst compute_ppms", {
  # expected

  # with st_extent
  ne_extent <- list(type = "rectangle",
                    lat.min = 42,
                    lat.max = 45,
                    lon.min = -88,
                    lon.max = -82,
                    t.min = 0.425,
                    t.max = 0.475)
  expect_error(cppms <- compute_ppms(sp_path, st_extent = ne_extent), NA)

  expect_equal(length(cppms), 3)
  expect_is(cppms, "list")
  expect_is(cppms$binary_stats, "data.frame")
  expect_is(cppms$occ_stats, "data.frame")
  expect_is(cppms$count_stats, "data.frame")
  expect_is(cppms$binary_stats$mc, "integer")
  expect_is(cppms$occ_stats$mc, "integer")
  expect_is(cppms$count_stats$mc, "integer")
  expect_equal(length(cppms$binary_stats$mc), 25)
  expect_equal(length(cppms$occ_stats$mc), 25)
  expect_equal(length(cppms$count_stats$mc), 25)

  # missing temporal info
  ne_extent <- list(type = "rectangle",
                    lat.min = 40,
                    lat.max = 47,
                    lon.min = -80,
                    lon.max = -70)
  expect_error(compute_ppms(sp_path, st_extent = ne_extent), NA)

  # reversed min max
  ne_extent <- list(type = "rectangle",
                    lat.min = 47,
                    lat.max = 40,
                    lon.min = -80,
                    lon.max = -70,
                    t.min = 0.425,
                    t.max = 0.475)
  expect_error(compute_ppms(sp_path, st_extent = ne_extent),
               "Minimum latitude is greater than maximum latitude")

  # missing a corner
  ne_extent <- list(type = "rectangle",
                    lat.min = 47,
                    lat.max = 40,
                    lon.min = -80,
                    t.min = 0.425,
                    t.max = 0.475)
  expect_error(compute_ppms(sp_path, st_extent = ne_extent),
               "Missing max longitude")

  # st_extent is not list
  ne_extent <- c(type = "rectangle",
                 lat.min = 40,
                 lat.max = 47,
                 lon.min = -80,
                 lon.max = -70,
                 t.min = 0.425,
                 t.max = 0.475)
  expect_error(compute_ppms(sp_path, st_extent = ne_extent),
               "st_extent argument must be a list")
})

context("plot_binary_by_time")

# plot binary by time
test_that("ebirdst plot_binary_by_time", {
  # with st_extent
  ne_extent <- list(type = "rectangle",
                    lat.min = 42,
                    lat.max = 45,
                    lon.min = -88,
                    lon.max = -82,
                    t.min = 0.425,
                    t.max = 0.475)

  # checking metrics
  expect_error(plot_binary_by_time(sp_path, metric = "Kappa",
                                   st_extent = ne_extent), NA)
  expect_error(plot_binary_by_time(sp_path, metric = "AUC",
                                   st_extent = ne_extent), NA)
  expect_error(plot_binary_by_time(sp_path, metric = "Sensitivity",
                                   st_extent = ne_extent), NA)
  expect_error(plot_binary_by_time(sp_path, metric = "Specificity",
                                   st_extent = ne_extent), NA)

  # wrong metric
  expect_error(plot_binary_by_time(sp_path, metric = "WrongMetric",
                                   st_extent = ne_extent),
               "Predictive performance metric must be one of")

  # n_time_periods
  expect_error(plot_binary_by_time(path = sp_path,
                                   metric = "Kappa",
                                   st_extent = ne_extent,
                                   n_time_periods = 1),
               "n_time_periods argument must be more than 1")
})

context("plot_all_ppms")

test_that("ebirdst plot_all_ppms", {
  ne_extent <- list(type = "rectangle",
                    lat.min = 42,
                    lat.max = 45,
                    lon.min = -88,
                    lon.max = -82,
                    t.min = 0.425,
                    t.max = 0.475)

  # expected
  expect_error(plot_all_ppms(path = sp_path, st_extent = ne_extent), NA)

  # missing temporal info
  ne_extent <- list(type = "rectangle",
                    lat.min = 40,
                    lat.max = 47,
                    lon.min = -80,
                    lon.max = -70)
  expect_error(plot_all_ppms(path = sp_path, st_extent = ne_extent),
               "Must provide temporal limits")

  # reversed min max
  ne_extent <- list(type = "rectangle",
                    lat.min = 47,
                    lat.max = 40,
                    lon.min = -80,
                    lon.max = -70,
                    t.min = 0.425,
                    t.max = 0.475)
  expect_error(plot_all_ppms(path = sp_path, st_extent = ne_extent),
               "Minimum latitude is greater than maximum latitude")

  # missing a corner
  ne_extent <- list(type = "rectangle",
                    lat.min = 47,
                    lat.max = 40,
                    lon.min = -80,
                    t.min = 0.425,
                    t.max = 0.475)
  expect_error(plot_all_ppms(path = sp_path, st_extent = ne_extent),
               "Missing max longitude")

  # st_extent is not list
  ne_extent <- c(type = "rectangle",
                 lat.min = 40,
                 lat.max = 47,
                 lon.min = -80,
                 lon.max = -70,
                 t.min = 0.425,
                 t.max = 0.475)
  expect_error(plot_all_ppms(path = sp_path, st_extent = ne_extent),
               "st_extent argument must be a list")

  # broken path

  ne_extent <- list(type = "rectangle",
                    lat.min = 40,
                    lat.max = 47,
                    lon.min = -80,
                    lon.max = -70,
                    t.min = 0.425,
                    t.max = 0.475)
  expect_error(plot_all_ppms(path = '~/some/messed/up/path/that/does/not/exist',
                             st_extent = ne_extent),
               "file does not exist")
})

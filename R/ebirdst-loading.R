#' Download eBird Status and Trends Data
#'
#' Download an eBird Status and Trends data package for a single species, or for
#' an example species, to a specified path. The example data consist of the
#' results for Yellow-bellied Sapsucker subset to Michigan and are much smaller
#' than the full dataset making these data quicker to download and process.
#'
#' @param species character; a single six-letter species code (e.g. rufhum).
#'   The full list of valid codes is can be viewed in the [runs_w_names] data
#'   frame included in this package. To download the example dataset, use
#'   "example_data".
#' @param path character; directory to download the data to. All downloaded
#'   files will be placed in a sub-directory of this directory named according
#'   to the unique run ID associated with this species.
#'
#' @return Path to the run-specific root of the downloaded files.
#' @export
#' @examples
#' \dontrun{
#'   dl_dir <- tempdir()
#'   download_data("example_data", path = dl_dir)
#' }
download_data <- function(species, path) {
  stopifnot(is.character(species), length(species) == 1)
  stopifnot(is.character(path), length(path) == 1, dir.exists(path))
  species <- tolower(species)

  # example data or a real run
  if (species == "example_data") {
    bucket_url <- "https://clo-is-da-example-data.s3.amazonaws.com/"
    run <- "yebsap-ERD2016-EBIRD_SCIENCE-20180729-7c8cec83"
  } else {
    row_id <- which(ebirdst::runs_w_names$SPECIES_CODE == species)
    if (length(row_id) != 1) {
      stop(sprintf("species = %s does not uniquely identify a species."))
    }
    # presumably this url will change
    bucket_url <- "https://clo-is-da-example-data.s3.amazonaws.com/"
    run <- ebirdst::runs_w_names$RUN_NAME[row_id]
  }

  # get bucket contents
  s3_contents <- xml2::xml_ns_strip(xml2::read_xml(bucket_url))
  s3_contents <- xml2::xml_find_all(s3_contents, ".//Contents")
  if (length(s3_contents) == 0) {
    stop(sprintf("Files not found on AWS S3 for species = %s", species))
  }
  # store filename and size
  s3_files <- data.frame(
    file = xml2::xml_text(xml2::xml_find_all(s3_contents, ".//Key")),
    size = xml2::xml_text(xml2::xml_find_all(s3_contents, ".//Size")),
    stringsAsFactors = FALSE)
  s3_files$size <- as.numeric(s3_files$size)
  # filter to desired run/species
  s3_files[as.numeric(s3_files$size) > 0 & grepl(run, s3_files$file), ]
  if (nrow(s3_files) == 0) {
    stop(sprintf("Files not found on AWS S3 for species = %s", species))
  }

  # prepare downlaod paths
  s3_files$s3_path <- paste0(bucket_url, s3_files$file)
  s3_files$local_path <- file.path(path, s3_files$file)
  # create necessary directories
  dirs <- unique(dirname(s3_files$local_path))
  for (d in dirs) {
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
  }
  # download
  for(f in 1:nrow(s3_files)) {
    dl_response <- download.file(s3_files[f, ]$s3_path,
                                 s3_files[f, ]$local_path,
                                 quiet = TRUE)
    if (dl_response != 0) {
      stop("Error downloading files from AWS S3")
    }
  }

  return(invisible(normalizePath(paste0(path, "/", run))))
}

#' Projects st_extent lat/lon list to sinusoidal raster Extent
#'
#' Internal function that converts the st_extent list used throughout this
#' package from lat/lon corners to a raster Extent using the same
#' Sinusoidal projection as the eBird Status and Trends products.
#'
#' @param st_extent list; st_extent list with lat/lon coordinates.
#'
#' @return A raster Extent in Sinusoidal projection.
#'
#' @keywords internal
#'
#' @examples
#' # define st_extent list
#' ne_extent <- list(type = "rectangle",
#'                   lat.min = 40,
#'                   lat.max = 47,
#'                   lon.min = -80,
#'                   lon.max = -70,
#'                   t.min = 0.425,
#'                   t.max = 0.475)
#'
#' # convert
#' sinu_e <- get_sinu_ext(ne_extent)
#' sinu_e
get_sinu_ext <- function(st_extent) {
  if(!all(is.na(st_extent))) {
    if(!is.list(st_extent)) {
      stop("The st_extent argument must be a list object.")
    }

    if(!is.null(st_extent$lat.min) & !is.null(st_extent$lat.max)) {
      if(st_extent$lat.min > st_extent$lat.max) {
        stop("Minimum latitude is greater than maximum latitude")
      }
    } else {
      stop("Either lat.min or lat.max missing.")
    }

    if(!is.null(st_extent$lon.min) & !is.null(st_extent$lon.max)) {
      if(st_extent$lon.min > st_extent$lon.max) {
        stop("Minimum longitude is greater than maximum longitude")
      }
    } else {
      stop("Either lon.min or lon.max missing.")
    }
  }

  # projection information
  ll <- "+init=epsg:4326"
  sinu <- "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +a=6371007.181 +b=6371007.181 +units=m +no_defs"

  sp_ext <- raster::extent(st_extent$lon.min,
                           st_extent$lon.max,
                           st_extent$lat.min,
                           st_extent$lat.max)
  extllr <- raster::raster(ext = sp_ext)
  extllr[is.na(extllr)] <- 0
  raster::crs(extllr) <- ll

  extsinur <- raster::projectRaster(extllr, crs = sinu)

  return(raster::extent(extsinur))
}

#' Labels 52 week RasterStack with the dates for each band
#'
#' The raster package does not allow layer names to be saved with the bands of a
#' multi-band GeoTiff. Accordingly, all eBird Status and Trends products raster
#' results cover the entire 52 week temporal extent of analysis. For
#' convenience, this function labels the RasterStack once it has been loaded
#' with the dates for each band.
#'
#' @param raster_data RasterStack or RasterBrick; original eBird Status and
#' Trends product raster GeoTiff with 52 bands, one for each week.
#'
#' @return A RasterStack or Rasterbrick with names assigned for the dates in
#' the format of "XYYYY.MM.DD" per raster package constraints. The Raster*
#' objects do not allow the names to start with a number, nor are they allowed
#' to contain "-", so it is not possible to store the date in an ISO compliant
#' format.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' rs <- stack("/path to GeoTiff/")
#' rs
#'
#' rs_labeled <- label_raster_stack(raster_data)
#' rs_labeled
#' }
label_raster_stack <- function(raster_data) {
  # check raster_data is either RasterLayer or RasterStack or RasterBrick
  if(!(class(raster_data) %in% c("RasterStack", "RasterBrick"))) {
    stop("The raster_data object must be either RasterStack or RasterBrick.")
  }

  # check length
  if((raster::nlayers(raster_data) != 52)) {
    stop(paste0("The raster_data object must be full stack or brick of 52",
                " layers as originally provided."))
  }

  SRD_DATE_VEC <- seq(from = 0, to = 1, length = 52 + 1)
  SRD_DATE_VEC <- (SRD_DATE_VEC[1:52] + SRD_DATE_VEC[2:(52 + 1)]) / 2
  SRD_DATE_VEC <- round(SRD_DATE_VEC, digits = 4)

  year_seq <- 2015
  p_time <- strptime(x = paste(round(SRD_DATE_VEC * 366), year_seq), "%j %Y")
  date_names <- paste(formatC(p_time$mon + 1, width = 2, format = "d",
                              flag = "0"),
                      formatC(p_time$mday, width = 2, format = "d",
                              flag = "0"),
                      sep = "-")

  names(raster_data) <- paste(2016, date_names, sep = "-")

  return(raster_data)
}

#' Parses the names attached to a Raster* from label_raster_stack()
#'
#' The label_raster_stack() function labels the dates of the estimate rasters
#' in the format of "XYYYY.MM.DD", because of constraints in the `raster`
#' packge. This function converts that character vector into an ISO compliant
#' Date vector.
#'
#' @param raster RasterLayer, RasterStack, or RasterBrick; full or subser of
#' original eBird Status and Trends product raster GeoTiff.
#'
#' @return Date vector.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' rs <- stack("/path to GeoTiff/")
#' rs_labeled <- label_raster_stack(raster_data)
#' rs_dates <- parse_raster_dates(rs_labeled)
#' }
parse_raster_dates <- function(raster) {
  # check raster_data is either RasterLayer or RasterStack or RasterBrick
  if(!(class(raster) %in% c("RasterLayer", "RasterStack", "RasterBrick"))) {
    stop("raster must be one of RasterLayer, RasterStack, or RasterBrick")
  }

  # check for names
  if(all(is.na(names(raster))) == TRUE |
     all(is.null(names(raster))) == TRUE |
     length(names(raster)) == 0) {
    stop("No names on Raster object. Please call label_raster_stack() first.")
  }

  if(length(grep("X2016.", names(raster)[1])) == 0) {
    stop("raster names not in correct format. Please call label_raster_stack first.")
  }

  names <- as.Date(gsub("\\.", "-", gsub("X", "", names(raster))), "%Y-%m-%d")

  return(names)
}

#' Spatiotemporal subsetter for eBird Status and Trends products table
#'
#' Internal function that takes a data.frame or SpatialPointsDataFrame and
#' a st_extent list and returns a subset of the data object. Currently
#' designed to handle either a 'rectangle' as defined by a lat/lon bounding
#' box or a 'polygon' as defined by a SpatialPolygon* object. The function
#' will use temporal information if provided. The t.min and t.max objects in
#' the `st_extent` list are currently able to wrap time around the year
#' (e.g., t.min = 0.9 and t.max = 0.1 is acceptable).
#'
#' @param data data.frame or SpatialPointsDataFrame; originating from results.
#' @param st_extent list; st_extent list object
#'
#' @return Subset of input data as same type.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' # define species eBird Status and Trends product location and load pis
#' sp_path <- "path to species product"
#' pis <- load_pis(sp_path)
#'
#' # define st_extent list
#' ne_extent <- list(type = "rectangle",
#'                   lat.min = 40,
#'                   lat.max = 47,
#'                   lon.min = -80,
#'                   lon.max = -70,
#'                   t.min = 0.425,
#'                   t.max = 0.475)
#'
#' #subset pis with st_extent list
#' data_st_subset(data = pis, st_extent = ne_extent, use_time = TRUE)
#' }
data_st_subset <- function(data, st_extent) {
  # check st_extent object
  if(!all(is.na(st_extent))) {
    if(!is.list(st_extent)) {
      stop("The st_extent argument must be a list object.")
    }

    if(st_extent$type == "rectangle") {
      if(is.null(st_extent$lon.max)) {
        stop("Missing max longitude")
      } else if(is.null(st_extent$lon.min)) {
        stop("Missing min longitude")
      } else if(is.null(st_extent$lat.max)) {
        stop("Missing max latitude")
      } else if(is.null(st_extent$lat.min)) {
        stop("Missing min latitude")
      }

      if(!is.null(st_extent$lat.min) & !is.null(st_extent$lat.max)) {
        if(st_extent$lat.min > st_extent$lat.max) {
          stop("Minimum latitude is greater than maximum latitude")
        }

        if(st_extent$lat.max < st_extent$lat.min) {
          stop("Latitude maximum is less than latitude minimum.")
        }
      } else {
        stop("Either lat.min or lat.max missing.")
      }

      if(!is.null(st_extent$lon.min) & !is.null(st_extent$lon.max)) {
        if(st_extent$lon.min > st_extent$lon.max) {
          stop("Minimum longitude is greater than maximum longitude")
        }

        if(st_extent$lon.max < st_extent$lon.min) {
          stop("Longitude maximum is less than longitude minimum.")
        }
      } else {
        stop("Either lon.min or lon.max missing.")
      }
    } else if(st_extent$type == "polygon") {
      # check Polygons
      if(is.null(st_extent$polygon)) {
        stop("polygon data not present.")
      }
    } else {
      stop(paste("Spatiotemporal extent type not accepted. ",
                 "Use either 'rectangle' or 'polygon'.",
                 sep = ""))
    }
  } else {
    stop("st_extent object is empty.")
  }

  # check to see if the time parts of the extent parameter are there
  if(is.null(st_extent$t.min) | is.null(st_extent$t.max)) {
    warning("Temporal information missing or incomplete. This may be intentional.")
    use_time <- FALSE
  } else {
    use_time <- TRUE
  }

  if(st_extent$type == "rectangle") {
    if(use_time == TRUE) {
      if(st_extent$t.min > st_extent$t.max) {
        subset_data <- data[(data$date > st_extent$t.min |
                              data$date <= st_extent$t.max) &
                              data$lat > st_extent$lat.min &
                              data$lat <= st_extent$lat.max &
                              data$lon > st_extent$lon.min &
                              data$lon <= st_extent$lon.max, ]
      } else {
        subset_data <- data[data$date > st_extent$t.min &
                              data$date <= st_extent$t.max &
                              data$lat > st_extent$lat.min &
                              data$lat <= st_extent$lat.max &
                              data$lon > st_extent$lon.min &
                              data$lon <= st_extent$lon.max, ]
      }
    } else {
      subset_data <- data[data$lat > st_extent$lat.min &
                          data$lat <= st_extent$lat.max &
                          data$lon > st_extent$lon.min &
                          data$lon <= st_extent$lon.max, ]
    }
  } else if(st_extent$type == "polygon") {
    ll_epsg <- "+init=epsg:4326"
    ll <- "+proj=longlat +datum=NAD83 +no_defs +ellps=GRS80 +towgs84=0,0,0"

    # check Polygons
    if(is.null(st_extent$polygon)) {
      stop("polygon data not present.")
    }

    # cast data to SpatialPoints
    if(is.data.frame(data)) {
      sites <- sp::SpatialPointsDataFrame(coords = data[, c("lon", "lat")],
                                          data = data,
                                          proj4string = sp::CRS(ll_epsg))
    } else {
      sites <- data
    }

    # check prj
    if(!sp::identicalCRS(sites, st_extent$polygon)) {
      plygn <- sp::spTransform(st_extent$polygon,
                               sp::CRS(sp::proj4string(sites)))
    } else {
      plygn <- st_extent$polygon
    }

    # use for subset
    subset_data <- sites[!is.na(over(sites,
                                     methods::as(plygn,
                                                 "SpatialPolygons"))), ]

    if(is.data.frame(data)) {
      subset_data <- subset_data@data
    }

    if(use_time == TRUE) {
      if(st_extent$t.min > st_extent$t.max) {
        subset_data <- subset_data[(subset_data$date > st_extent$t.min |
                                      subset_data$date <= st_extent$t.max), ]
      } else {
        subset_data <- subset_data[subset_data$date > st_extent$t.min &
                                     subset_data$date <= st_extent$t.max, ]
      }
    }
  } else {
    stop(paste("Spatiotemporal extent type not accepted. ",
               "Use either 'rectangle' or 'polygon'.",
               sep = ""))
  }

  return(subset_data)
}

#' Spatiotemporal subsetter for eBird Status and Trends products raster
#'
#' Internal function that takes a RasterStack or RasterBrick and a st_extent
#' list and returns a spatiotemporal subset of the data object. Currently
#' designed to handle either a 'rectangle' as defined by a lat/lon bounding
#' box or a 'polygon' as defined by a SpatialPolygon* object. The function
#' will use temporal information if provided. The t.min and t.max objects in
#' the `st_extent` list are currently able to wrap time around the year
#' (e.g., t.min = 0.9 and t.max = 0.1 is acceptable). This function will also
#' returned a date labeled RasterStack or RasterBrick, so there is no need
#' to use the label_raster_stack() directly if subsetting.
#'
#' @param data RasterStack or RasterBrick; one of four GeoTiff files provided
#' with results
#' @param st_extent list; st_extent list object
#'
#' @return Subset of input data as same type, with layers labeled with dates
#' from label_raster_stack().
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' rs <- stack("/path to GeoTiff")
#' rs
#'
#' # define st_extent list
#' ne_extent <- list(type = "rectangle",
#'                   lat.min = 40,
#'                   lat.max = 47,
#'                   lon.min = -80,
#'                   lon.max = -70,
#'                   t.min = 0.5,
#'                   t.max = 0.6)
#'
#' # subset stack with extent
#' rs_sub <- raster_st_subset(rs, st_extent = ne_extent)
#' }
raster_st_subset <- function(raster_data, st_extent) {
  # check raster_data is either RasterLayer or RasterStack or RasterBrick
  if(!(class(raster_data) %in% c("RasterStack", "RasterBrick"))) {
    stop("raster_data object must be either RasterStack or RasterBrick")
  }

  # check st_extent object
  if(!all(is.na(st_extent))) {
    if(!is.list(st_extent)) {
      stop("The st_extent argument must be a list object.")
    }

    if(st_extent$type == "rectangle") {
      if(is.null(st_extent$lon.max)) {
        stop("Missing max longitude")
      } else if(is.null(st_extent$lon.min)) {
        stop("Missing min longitude")
      } else if(is.null(st_extent$lat.max)) {
        stop("Missing max latitude")
      } else if(is.null(st_extent$lat.min)) {
        stop("Missing min latitude")
      }

      if(!is.null(st_extent$lat.min) & !is.null(st_extent$lat.max)) {
        if(st_extent$lat.min > st_extent$lat.max) {
          stop("Minimum latitude is greater than maximum latitude")
        }

        if(st_extent$lat.max < st_extent$lat.min) {
          stop("Latitude maximum is less than latitude minimum.")
        }
      } else {
        stop("Either lat.min or lat.max missing.")
      }

      if(!is.null(st_extent$lon.min) & !is.null(st_extent$lon.max)) {
        if(st_extent$lon.min > st_extent$lon.max) {
          stop("Minimum longitude is greater than maximum longitude")
        }

        if(st_extent$lon.max < st_extent$lon.min) {
          stop("Longitude maximum is less than longitude minimum.")
        }
      } else {
        stop("Either lon.min or lon.max missing.")
      }
    } else if(st_extent$type == "polygon") {
      # check Polygons
      if(is.null(st_extent$polygon)) {
        stop("polygon data not present.")
      }
    } else {
      stop(paste("Spatiotemporal extent type not accepted. ",
                 "Use either 'rectangle' or 'polygon'.",
                 sep = ""))
    }
  } else {
    stop("st_extent object is empty.")
  }

  if(is.null(st_extent$t.min) | is.null(st_extent$t.max)) {
    warning("Temporal information missing or incomplete. This may be intentional.")
    use_time <- FALSE
  } else {
    use_time <- TRUE
  }

  # convert st_extent to sinu
  if(st_extent$type == "rectangle") {
    sinu_ext <- get_sinu_ext(st_extent)
  }

  # check length
  if((raster::nlayers(raster_data) != 52)) {
    stop(paste0("The raster_data object must be full stack or brick of 52",
                " layers as originally provided."))
  }

  # check names
  if(length(grep("X2016.", names(raster_data)[1])) == 0) {
    raster_data <- label_raster_stack(raster_data)
  }

  # subset stack for time
  if(use_time == TRUE) {
    SRD_DATE_VEC <- seq(from = 0, to= 1, length = 52 + 1)
    SRD_DATE_VEC <- (SRD_DATE_VEC[1:52] + SRD_DATE_VEC[2:(52 + 1)]) / 2
    SRD_DATE_VEC <- round(SRD_DATE_VEC, digits = 4)

    p_time <- strptime(x = paste(round(SRD_DATE_VEC * 366), 2015), "%j %Y")
    date_names <- paste(formatC(p_time$mon + 1, width = 2, format = "d",
                                flag = "0"),
                        formatC(p_time$mday, width = 2, format = "d",
                                flag = "0"),
                        sep = "-")

    # select from SRD_DATE_VEC where between st_extent$t.min and st_extent$t.max
    if(st_extent$t.min > st_extent$t.max) {
      # date wrapping case
      weeks <- c(which(date_names %in%
                         date_names[SRD_DATE_VEC >= st_extent$t.min]),
                 which(date_names %in%
                         date_names[SRD_DATE_VEC <= st_extent$t.max]))
    } else {
      weeks <- which(date_names %in%
                       date_names[SRD_DATE_VEC >= st_extent$t.min &
                                    SRD_DATE_VEC <= st_extent$t.max])
    }

    if(length(weeks) < 1) {
      stop("Time period in st_extent does not included any weeks of the year.")
    }

    raster_data <- raster_data[[weeks]]
  }

  # crop
  if(st_extent$type == "rectangle") {
    raster_data <- raster::crop(raster_data, sinu_ext)
  } else if(st_extent$type == "polygon") {
    ll_epsg <- "+init=epsg:4326"
    ll <- "+proj=longlat +datum=NAD83 +no_defs +ellps=GRS80 +towgs84=0,0,0"

    # check Polygons
    if(is.null(st_extent$polygon)) {
      stop("polygon data not present.")
    }

    # check prj
    if(!sp::identicalCRS(raster_data, st_extent$polygon)) {
      plygn <- sp::spTransform(st_extent$polygon,
                               sp::CRS(sp::proj4string(raster_data)))
    } else {
      plygn <- st_extent$polygon
    }

    raster_data <- raster::trim(raster::mask(raster::crop(raster_data,
                                                          raster::extent(plygn)),
                                             plygn),
                                values = NA)
  } else {
    stop(paste("Spatiotemporal extent type not accepted. ",
               "Use either 'rectangle' or 'polygon'.",
               sep = ""))
  }

  return(raster_data)
}

#' Config file loader
#'
#' Internal function used by load_summary(), load_pis(), and load_pds() to get
#' configuration variables from eBird Status and Trends products
#' (from *_config.RData).
#'
#' @param path character; Full path to the directory containing single species
#' eBird Status and Trends products.
#'
#' @return environment object containing all run parameters.
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#'
#' e <- load_config(sp_path)
#' }
load_config <- function(path) {
  e <- new.env()

  config_file_path <- list.files(paste(path, "/data", sep = ""),
                                 pattern = "*_config*")
  config_file <- paste(path, "/data/", config_file_path, sep = "")

  if(!file.exists(config_file)) {
    stop(paste("*_config.RData file does not exist in the /data directory. ",
               "Check your paths so that they look like this: ",
               "~/directory/<six_letter_code-ERD2016-PROD-date-uuid>/. ",
               "Make sure you do not change the file structure of the results.",
               sep = ""))
  }

  load(config_file, envir = e)
  rm(config_file)

  return(e)
}

#' Stixel summary file loader
#'
#' Internal function used by load_pis() and load_pds() to get the stixel
#' summary information (from summary.txt).
#'
#' @param path character; Full path to the directory containing single species
#' eBird Status and Trends products.
#'
#' @return data.frame containing stixel summary information about each stixel
#' centroid.
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#'
#' summaries <- load_summary(sp_path)
#' }
load_summary <- function(path) {
  e <- load_config(path)

  # define stixel summary fields
  train_covariate_means_names <- paste("train.cov.mean",
                                       e$PREDICTOR_LIST,
                                       sep = "_")
  srd_covariate_means_names <- paste("srd.cov.mean",
                                     e$PREDICTOR_LIST,
                                     sep = "_")
  summary_vec_name_vec <- c("srd.n",
                            "lon",
                            "lat",
                            "date",
                            "stixel_width",
                            "stixel_height",
                            "stixel_area",
                            "train.n",
                            "positive.ob_n",
                            "stixel_prevalence",
                            "mean_non_zero_count",
                            "binary_Kappa",
                            "binary_AUC",
                            "binary.deviance_model",
                            "binary.deviance_mean",
                            "binary.deviance_explained",
                            "pois.deviance_model",
                            "pois.deviance_mean",
                            "posi.deviance_explained",
                            "total_EFFORT_HRS",
                            "total_EFFORT_DISTANCE_KM",
                            "total_NUMBER_OBSERVERS",
                            "train_elevation_mean",
                            train_covariate_means_names, #k-covariate values
                            "train_covariate_entropy",
                            "srd_elevation_mean",
                            srd_covariate_means_names, #k-covariate values
                            "srd_covariate_entropy",
                            "max_time")

  stixel_path <- "/results/abund_preds/unpeeled_folds/"
  summary_file <- paste(path, stixel_path, "summary.txt", sep = "")

  if(!file.exists(summary_file)) {
    stop(paste("The file summary.txt does not exist at ",
               path, stixel_path, sep = ""))
  }

  summary_vec <- data.table::fread(summary_file, showProgress = FALSE)
  names(summary_vec)[3] <- "stixel.id"
  names(summary_vec)[4:ncol(summary_vec)] <- summary_vec_name_vec

  summary_nona <- summary_vec[!is.na(summary_vec$lon), ]
  rm(summary_vec, summary_file)

  return(summary_nona)
}

#' Load predictor importances for single species eBird Status and Trends products
#'
#' Loads the predictor importance data (from pi.txt), joins with stixel summary
#' data, sets the names from `load_config()`, and cleans up the data.frame.
#'
#' @param path character; Full path to the directory containing single species
#' eBird Status and Trends products.
#'
#' @return data.frame containing predictor importance values for each stixel,
#' as well as stixel summary information.
#'
#' @import data.table
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#'
#' pis <- load_pis(sp_path)
#' }
load_pis <- function(path) {
  # load config vars
  e <- load_config(path)

  # load pi.txt and set column names
  stixel_path <- "/results/abund_preds/unpeeled_folds/"
  pi_file <- paste(path, stixel_path, "pi.txt", sep = "")

  if(!file.exists(pi_file)) {
    stop(paste("The file pi.txt does not exist at",
               path, stixel_path, sep = ""))
  }

  pi_vec <- data.table::fread(pi_file, showProgress = FALSE)
  names(pi_vec)[4:ncol(pi_vec)] <- e$PI_VARS
  names(pi_vec)[3] <- "stixel.id"

  # get summary file
  summary_file <- load_summary(path)

  # merge pis with summary
  pi_summary <- merge(pi_vec, summary_file, by = c("stixel.id"))
  rm(pi_vec, summary_file)

  # return subset
  pi_summary[, c("V1.x", "V2.x", "V1.y", "V2.y") := NULL]
  pi_summary <- pi_summary[, 1:(length(e$PI_VARS) + 12)]

  return(as.data.frame(pi_summary))
}

#' Load partial dependencies for single species eBird Status and Trends products
#'
#' Loads the partial dependency data (from pd.txt), joins with stixel summary
#' data, sets the names from `load_config()`, and cleans up the data.frame.
#' This is one of the slower functions in the package, due to the size of the
#' pd.txt file (usually multiple GB).
#'
#' @param path character; Full path to the directory containing single species
#' eBird Status and Trends products.
#'
#' @return data.frame containing partial dependency values for each stixel,
#' as well as stixel summary information.
#'
#' @import data.table
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#'
#' pds <- load_pds(sp_path)
#' }
load_pds <- function(path) {
  # load config vars
  e <- load_config(path)

  # load pi.txt
  stixel_path <- "/results/abund_preds/unpeeled_folds/"
  pd_file <- paste(path, stixel_path, "/pd.txt", sep = "")

  if(!file.exists(pd_file)) {
    stop(paste("The file pd.txt does not exist at ",
               path, stixel_path, sep = ""))
  }

  # load pd.txt
  pd_vec <- data.table::fread(pd_file, showProgress = FALSE)
  names(pd_vec)[3] <- "stixel.id"

  # load summary file
  summary_file <- load_summary(path)

  # merge
  pd_summary <- merge(pd_vec, summary_file, by = c("stixel.id"), all.y = TRUE)
  rm(pd_vec, summary_file)

  # return a subset of the fields
  pd_summary[ ,c("V1.x", "V2.x", "V1.y", "V2.y") := NULL]
  pd_summary <- pd_summary[, 1:(length(e$PD_VARS) + 28)]

  return(as.data.frame(pd_summary))
}

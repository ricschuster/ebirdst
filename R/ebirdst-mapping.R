#' Calculates spatial extent of non-zero data from Raster* object for plotting
#'
#' After loading a RasterStack of results, there are lots of NA values
#' and plots of individual raster layers will display at the full extent of the
#' study extent. To show an ideal extent, this function trims away 0 and
#' NA values and checks to make sure it returns a reasonable extent for
#' plotting. The returned Extent object can then be used for plotting.
#'
#' @param x Raster* object; either full RasterStack or subset.
#' @param path character; Full path to directory containing the results
#' for a single species.
#'
#' @return raster Extent object
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#' raster_stack <- stack(sp_path)
#' plot_extent <- calc_full_extent(raster_stack, path)
#' raster::plot(raster_stack[[1]], ext = plot_extent)
#' }
calc_full_extent <- function(x, path) {

  if(!(class(x) %in% c("RasterLayer", "RasterStack", "RasterBrick"))) {
    stop("Input must be a Raster* object.")
  }

  # aggregate stack for speed, otherwise everything else takes too long
  stack <- raster::aggregate(x, fact = 3)

  # convert 0s to NAs, otherwise trimming is slow and the extent is too broad
  stack[stack == 0] <- NA

  # trim away 0s to get closest extent to positive values
  stack <- raster::trim(stack, values = NA)

  # save extent
  map_extent <- raster::extent(stack)

  # sometimes extent calculations get weird and you'll get a very broad
  # extent that goes further than you want, so check against the input
  input_raster_extent <- extent(x)

  # xmin too low
  if(map_extent[1] < input_raster_extent[1]) {
    map_extent[1] <- input_raster_extent[1]
  }

  # xmax too high
  if(map_extent[2] > input_raster_extent[2]) {
    map_extent[2] <- input_raster_extent[2]
  }

  # ymin too low
  if(map_extent[3] < input_raster_extent[3]) {
    map_extent[3] <- input_raster_extent[3]
  }

  # ymax too high
  if(map_extent[4] > input_raster_extent[4]) {
    map_extent[4] <- input_raster_extent[4]
  }

  return(map_extent)
}

#' Calculates bins (breaks) based on standard deviations of Box-Cox
#' power-transformed data for mapping
#'
#' Mapping species abundance across the full-annual cycle presents a challenge,
#' in that patterns of concentration and dispersion in abundance change
#' throughout the year, making it difficult to define color bins that suit all
#' seasons and accurately reflect the detail of abundance predictions. To
#' address this, we selected a method (described by Maciejewski et al. 2013)
#' that first selects an optimal power (the Box-Cox method) for normalizing
#' the data, then power transforms the entire year of non-zero data, constructs
#' bins with the power-transformed data using standard-deviations, and then
#' un-transforms the bins.
#'
#' @param x RasterStack or RasterBrick; original eBird Status and
#' Trends product raster GeoTiff with 52 bands, one for each week.
#'
#' @return A vector containing the break points of bins.
#'
#' @export
#'
#' @references Ross Maciejewski, Avin Pattah, Sungahn Ko, Ryan Hafen, William S. Cleveland, David S. Ebert.  Automated Box-Cox Transformations for Improved Visual Encoding. IEEE Transactions on Visualization and Computer Graphics, 19(1): 130-140, 2013.
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#' raster_stack <- stack(sp_path)
#' year_bins <- calc_bins(raster_stack)
#'
#' raster::plot(raster_stack[[1]], xaxt = 'n', yaxt = 'n', breaks = year_bins)
#' }
calc_bins <- function(x) {

  if(!(class(x) %in% c("RasterLayer", "RasterStack", "RasterBrick"))) {
    stop("Input must be a Raster* object.")
  }

  if(all(is.na(raster::maxValue(x))) & all(is.na(raster::minValue(x)))) {
    stop("Input Raster* object must have non-NA values.")
  }

  # get a vector of all the values in the stack
  zrv <- raster::getValues(x)
  vals_for_pt <- zrv[!is.na(zrv) & zrv > 0]

  # BoxCox transform
  pt <- car::powerTransform(vals_for_pt)
  this_power <- pt$lambda

  lzwk <- vals_for_pt ^ this_power
  rm(zrv)

  # setup the binning structure
  # calculate metrics
  maxl <- max(lzwk, na.rm = TRUE)
  minl <- min(lzwk, na.rm = TRUE)
  mdl <- mean(lzwk, na.rm = TRUE)
  sdl <- stats::sd(lzwk, na.rm = TRUE)
  rm(lzwk)

  # build a vector of bins
  log_sd <- c(mdl - (3.00 * sdl), mdl - (2.50 * sdl), mdl - (2.00 * sdl),
              mdl - (1.75 * sdl), mdl - (1.50 * sdl), mdl - (1.25 * sdl),
              mdl - (1.00 * sdl), mdl - (0.75 * sdl), mdl - (0.50 * sdl),
              mdl - (0.25 * sdl), mdl - (0.125 * sdl),
              mdl,
              mdl + (0.125 * sdl), mdl + (0.25 * sdl),
              mdl + (0.50 * sdl), mdl + (0.75 * sdl), mdl + (1.00 * sdl),
              mdl + (1.25 * sdl), mdl + (1.50 * sdl), mdl + (1.75 * sdl),
              mdl + (2.00 * sdl), mdl + (2.50 * sdl), mdl + (3.00 * sdl))

  # lots of checks for values outside of the upper and lower bounds

  # remove +3 SD break if it is greater than max
  if(maxl < mdl + (3.00 * sdl)) {
    log_sd <- log_sd[1:length(log_sd) - 1]
  }

  # add max if the max is greater than +3 SD break
  if(maxl > mdl + (3.00 * sdl) | maxl > log_sd[length(log_sd)]) {
    log_sd <- append(log_sd, maxl)
  }

  # remove the -3 SD break if it is less than the min
  if(minl > mdl - (3.00 * sdl)) {
    log_sd <- log_sd[2:length(log_sd)]
  }

  # add min if the min is less than -3 SD break
  if(minl < mdl - (3.00 * sdl) | minl < log_sd[1]) {
    log_sd <- append(log_sd, minl, after = 0)
  }

  if(log_sd[1] < 0) {
    log_sd[1] <- 0.01 ^ this_power
  }

  if(log_sd[1] ^ (1 / this_power) < 0.01) {
    log_sd[1] <- 0.01 ^ this_power
  }

  # untransform
  bins <- log_sd ^ (1 / this_power)
  rm(log_sd)

  # if transform power was negative, flip bins
  if(this_power < 0) {
    bins <- rev(bins)
  }

  return(list(bins = bins, power = this_power))
}

#' Map PI and PD centroid locations
#'
#' Creates a map showing the stixel centroid locations for PIs and/or PDs, with
#' an optional spatiotemporal subset using an `st_extent` list.
#'
#' @param pis data.frame; from `load_pis()`
#' @param pds data.frame; from `load_pds()`
#' @param st_extent list; Optional spatiotemporal filter using `st_extent` list.
#' @param plot_pis logical; Default is TRUE. Set to FALSE to hide the plotting
#' of PI stixel centroid locations.
#' @param plot_pds logical; Default is TRUE. Set to FALSE to hide the plotting
#' of PD stixel centroid locations.
#'
#' @return Plot showing locations of PIs and/or PDs.
#'
#' @export
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#' pis <- load_pis(sp_path)
#' pds <- load_pds(sp_path)
#'
#' ne_extent <- list(type = "rectangle",
#'                   lat.min = 40,
#'                   lat.max = 47,
#'                   lon.min = -80,
#'                   lon.max = -70,
#'                   t.min = 0.425,
#'                   t.max = 0.475)
#'
#' map_centroids(pis = pis, pds = pds, st_extent = ne_extent)
#' }
map_centroids <- function(pis,
                          pds,
                          st_extent = NA,
                          plot_pis = TRUE,
                          plot_pds = TRUE) {

  if(plot_pds == FALSE & plot_pis == FALSE) {
    stop("Plotting of both PIs and PDs set to FALSE. Nothing to plot!")
  }

  if(!all(is.na(st_extent))) {
    if(!is.list(st_extent)) {
      stop("The st_extent argument must be a list object.")
    }
  }

  # projection information
  ll <- "+init=epsg:4326"
  mollweide <- "+proj=moll +lon_0=-90 +x_0=0 +y_0=0 +ellps=WGS84"

  # initialize graphical parameters
  graphics::par(mfrow = c(1, 1), mar=c(0,0,0,0), bg = "black")

  # Plotting PDs
  if(plot_pds == TRUE) {
    tpds <- unique(pds[, c("lon", "lat", "date")])
    tpds_sp <- sp::SpatialPointsDataFrame(tpds[, c("lon", "lat")],
                                          tpds,
                                          proj4string = sp::CRS(ll))
    tpds_prj <- sp::spTransform(tpds_sp, sp::CRS(mollweide))
    rm(tpds)

    # start plot with all possible PDs
    suppressWarnings(raster::plot(tpds_prj, ext = raster::extent(tpds_prj),
                                  col = "#1b9377", cex = 0.01, pch = 16))

    suppressWarnings(sp::plot(ned_wh_co_moll, col = "#5a5a5a", add = TRUE))

    suppressWarnings(raster::plot(tpds_prj, ext = raster::extent(tpds_prj),
                                  col = "#1b9377", cex = 0.4, pch = 16,
                                  add = TRUE))

    if(!all(is.na(st_extent))) {
      tpds_sub <- data_st_subset(tpds_sp, st_extent)

      tpds_region <- sp::spTransform(tpds_sub, sp::CRS(mollweide))
      rm(tpds_sub)

      # plot PDs in st_extent
      suppressWarnings(raster::plot(tpds_region, ext = raster::extent(tpds_prj),
                                    col = "#b3e2cd", cex = 0.4, pch = 16,
                                    add = TRUE))
    }
    rm(tpds_sp)

    # xmin, xmax, ymin, ymax
    usr <- graphics::par("usr")
    xwidth <- usr[2] - usr[1]
    yheight <- usr[4] - usr[3]

    graphics::text(x = usr[1] + xwidth/8,
                   y = usr[3] + yheight/7,
                   paste("Available PDs: ", nrow(tpds_prj), sep = ""),
                   cex = 1,
                   col = "#1b9377")

    if(!all(is.na(st_extent))) {
      graphics::text(x = usr[1] + xwidth/8,
                     y = usr[3] + yheight/9,
                     paste("Selected PDs: ", nrow(tpds_region), sep = ""),
                     cex = 1,
                     col = "#b3e2cd")

      rm(tpds_region)
    }

    wh_extent <- raster::extent(tpds_prj)
    rm(tpds_prj)
  }

  # Plotting PIs
  if(plot_pis == TRUE) {
    tpis <- unique(pis[, c("lon", "lat", "date")])
    tpis_sp <- sp::SpatialPointsDataFrame(tpis[, c("lon", "lat")],
                                          tpis,
                                          proj4string = sp::CRS(ll))
    tpis_prj <- sp::spTransform(tpis_sp, mollweide)
    rm(tpis)

    if(plot_pds == FALSE) {
      wh_extent <- raster::extent(tpis_prj)

      # start plot with all possible PDs
      suppressWarnings(raster::plot(tpis_prj, ext = wh_extent, col = "#1b9377",
                                    cex = 0.01, pch = 16))

      suppressWarnings(sp::plot(ned_wh_co_moll, col = "#5a5a5a", add = TRUE))
    }

    # start plot with all possible PIs
    suppressWarnings(raster::plot(tpis_prj, ext = wh_extent, col = "#d95f02",
                                  cex = 0.4, pch = 16, add = TRUE))

    if(!all(is.na(st_extent))) {
      tpis_sub <- data_st_subset(tpis_sp, st_extent)

      tpis_region <- sp::spTransform(tpis_sub, sp::CRS(mollweide))

      # plot PIs in st_extent
      suppressWarnings(raster::plot(tpis_region, ext = wh_extent,
                                    col = "#fdcdac", cex = 0.4, pch = 16,
                                    add = TRUE))
    }
    rm(tpis_sp)

    # xmin, xmax, ymin, ymax
    usr <- suppressWarnings(graphics::par("usr"))
    xwidth <- usr[2] - usr[1]
    yheight <- usr[4] - usr[3]

    text(x = usr[1] + xwidth/8,
         y = usr[3] + yheight/12,
         paste("Available PIs: ", nrow(tpis_prj), sep = ""),
         cex = 1,
         col = "#d95f02")
    rm(tpis_prj)

    if(!all(is.na(st_extent))) {
      text(x = usr[1] + xwidth/8,
           y = usr[3] + yheight/17,
           paste("Selected PIs: ", nrow(tpis_region), sep = ""),
           cex = 1,
           col = "#fdcdac")
      rm(tpis_region)
    }
  }

  # plot reference data
  suppressWarnings(raster::plot(ned_wh_co_moll, ext = wh_extent, lwd = 0.25,
                                border = 'black', add = TRUE))

  suppressWarnings(raster::plot(ned_wh_st_moll, ext = wh_extent, lwd = 0.25,
                                border = 'black', add = TRUE))
}

#' Calculate and map effective extent of selected centroids
#'
#' The selection of stixel centroids for analysis of PIs and/or PDs yields an
#' effective footprint, or extent, showing the effective location of where the
#' information going into the analysis with PIs and/or PDs is based. While a
#' bounding box or polygon may be used to select a set of centroids, due to the
#' models being fit within large rectangular areas, the information from a set
#' of centroids often comes from the core of the selected area. This function
#' calculates where the highest proportion of information is coming from,
#' returns a raster and plots that raster, with the selected area and centroids
#' for reference. The legend shows, for each pixel, what percentage of the
#' selected stixels are contributing information, ranging from 0 to 1.
#'
#' @param st_extent list; st_extent list containing spatiotemporal filter
#' @param pis data.frame; from `load_pis()` Must supply either pis or pds.
#' @param pds data.frame; from `load_pds()` Must supply either pis or pds.
#' @param path character; Full path to directory containing the eBird Status
#' and Trends products for a single species.
#'
#' @return RasterLayer and plots the RasterLayer with centroid locations and
#' st_extent boundaries.
#'
#' @import sp
#' @export
#'
#' @examples
#' \dontrun{
#'
#' sp_path <- "path to species eBird Status and Trends products"
#' pis <- load_pis(sp_path)
#'
#' ne_extent <- list(type = "rectangle",
#'                   lat.min = 40,
#'                   lat.max = 47,
#'                   lon.min = -80,
#'                   lon.max = -70,
#'                   t.min = 0.425,
#'                   t.max = 0.475)
#'
#' eff_lay <- calc_effective_extent(st_extent = ne_extent, pis = pis)
#' }
calc_effective_extent <- function(st_extent,
                                  pis = NA,
                                  pds = NA,
                                  path) {

  if(is.null(nrow(pis)) & is.null(nrow(pds))) {
    stop("Both PIs and PDs are NA. Nothing to calculate.")
  }

  if(!is.null(nrow(pis)) & !is.null(nrow(pds))) {
    stop("Unable to calculate for both PIs and PDs, supply one or the other.")
  }

  if(all(is.na(st_extent))) {
    stop("Missing spatiotemporal extent.")
  } else {
    if(!is.list(st_extent)) {
      stop("The st_extent argument must be a list object.")
    }
  }

  if(is.null(st_extent$t.min) | is.null(st_extent$t.max)) {
    warning(paste("Without temporal limits (t.min, t.max) in st_extent, ",
                  "function will take considerably longer to run and is ",
                  "less informative.", sep = ""))
  }

  # projection info
  ll <- "+init=epsg:4326"
  mollweide <- "+proj=moll +lon_0=-90 +x_0=0 +y_0=0 +ellps=WGS84"

  # load template raster
  e <- load_config(path)
  template_raster <- raster::raster(paste(path, "/data/", e$RUN_NAME,
                                          "_srd_raster_template.tif", sep = ""))

  # set object based on whether using PIs or PDs
  if(!is.null(nrow(pis))) {
    stixels <- pis
  } else {
    stixels <- pds
  }
  rm(pis, pds)

  # subset, create spatial data, project
  tpis <- unique(stixels[, c("lon", "lat", "date", "stixel_width",
                             "stixel_height")])
  tpis_sp <- sp::SpatialPointsDataFrame(tpis[, c("lon","lat")],
                                        tpis,
                                        proj4string = sp::CRS(ll))
  rm(tpis)

  tpis_sub <- data_st_subset(tpis_sp, st_extent)
  rm(tpis_sp)

  # build stixels as polygons
  # create corners
  xPlus <- tpis_sub$lon + (tpis_sub$stixel_width/2)
  yPlus <- tpis_sub$lat + (tpis_sub$stixel_height/2)
  xMinus <- tpis_sub$lon - (tpis_sub$stixel_width/2)
  yMinus <- tpis_sub$lat - (tpis_sub$stixel_height/2)

  ID <- row.names(tpis_sub)

  square <- cbind(xMinus, yPlus, xPlus, yPlus, xPlus,
                  yMinus, xMinus, yMinus, xMinus, yPlus)

  polys <- sp::SpatialPolygons(mapply(function(poly, id) {
    xy <- matrix(poly, ncol = 2, byrow = TRUE)
    sp::Polygons(list(sp::Polygon(xy)), ID = id)
  }, split(square, row(square)), ID), proj4string = sp::CRS("+init=epsg:4326"))

  tdspolydf <- sp::SpatialPolygonsDataFrame(polys, tpis_sub@data)
  rm(xPlus, yPlus, xMinus, yMinus, ID, square, polys)

  # assign value
  tdspolydf$weight <- 1

  # project to template raster
  tdspolydf_prj <- sp::spTransform(tdspolydf,
                                   sp::CRS(
                                     sp::proj4string(template_raster)))
  rm(tdspolydf)

  # summarize...not sure how to do this step
  tpis_r <- raster::crop(raster::rasterize(tdspolydf_prj, template_raster,
                                           field = "weight", fun = sum),
                         raster::extent(tdspolydf_prj))

  tpis_per <- tpis_r / nrow(tpis_sub)
  rm(tpis_r)
  #tpis_per[tpis_per < 0.50] <- NA

  # plot
  tpis_per_prj <- raster::projectRaster(tpis_per, crs = mollweide)

  tdspolydf_moll <- sp::spTransform(tdspolydf_prj, mollweide)

  # project the selected points to mollweide
  tpis_sub_moll <- sp::spTransform(tpis_sub, mollweide)

  # convert st_extent to polygon and mollweide for plotting
  if(st_extent$type == "rectangle") {
    st_ext <- raster::extent(st_extent$lon.min,
                             st_extent$lon.max,
                             st_extent$lat.min,
                             st_extent$lat.max)
    st_extp <- as(st_ext, "SpatialPolygons")
    raster::projection(st_extp) <- sp::CRS(ll)
    st_extp_prj <- sp::spTransform(st_extp, sp::CRS(mollweide))
    rm(st_ext, st_extp)
  } else if(st_extent$type == "polygon") {
    st_extp_prj <- sp::spTransform(st_extent$polygon, sp::CRS(mollweide))
  } else {
    stop("Spatiotemporal extent type not accepted.")
  }

  graphics::par(mar = c(0, 0, 0, 2))

  tpis_per_prj[tpis_per_prj >= 1] <- 1

  raster::plot(tpis_per_prj,
               xaxt = 'n',
               yaxt = 'n',
               bty = 'n',
               breaks = c(0, seq(0.5, 1, by = 0.05)),
               ext = raster::extent(tdspolydf_moll),
               col = viridis::viridis(11),
               maxpixels = raster::ncell(tpis_per_prj),
               legend = TRUE)

  sp::plot(ned_wh_co_moll, add = TRUE, border = 'gray')
  sp::plot(ned_wh_st_moll, add = TRUE, border = 'gray')
  sp::plot(st_extp_prj, add = TRUE, border = 'red')
  sp::plot(tpis_sub_moll, add = TRUE, pch = 16, cex = 1 * graphics::par()$cex)

  return(tpis_per)
}

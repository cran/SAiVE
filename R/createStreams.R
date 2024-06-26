#' Create stream network from DEM
#'
#' @author Ghislain de Laplante (gdela069@uottawa.ca or ghislain.delaplante@yukon.ca)
#'
#' @description
#' `r lifecycle::badge("stable")`
#'
#' Creates a stream network from a provided DEM. In most cases it is advisable to first hydro-process the DEM (see [hydroProcess()]) to remove depressions which preclude continuous flow from one DEM cell to the next.
#'
#' @details
#' This function is essentially a convenient wrapper around three WhiteboxTools geospatial tools ([whitebox::wbt_d8_flow_accumulation()], [whitebox::wbt_d8_pointer()], and [whitebox::wbt_extract_streams()]) and some terra functions to convert rasters to vector files.
#'
#'
#' @param DEM The path to a digital elevation model file with .tif extension, or a terra spatRaster object. It is usually advisable to have already hydro-processed the DEM to remove artificial depressions. See [hydroProcess()].
#' @param threshold The accumulation threshold in DEM cells necessary to start defining a stream.
#' @param vector Output file specifications. NULL for no vector file at all; "env" for only a variable returned to the R environment; or, to return to environment and save to disk, "gpkg" for a geopackage file, "shp" for a shapefile.
#' @param save_path An optional path in which to save the newly created stream network. If left NULL will save it in the same directory as the provided DEM or, if the DEM is a terra object, return only terra objects.
#' @param n.cores The maximum number of cores to use. Leave NULL to use all cores minus 1.
#' @param force_update_wbt Whitebox Tools is by default only downloaded if it cannot be found on the computer, and no check are performed to ensure the local version is current. Set to TRUE if you know that there is a new version and you would like to use it.
#' @param silent_wbt Should Whitebox tools messages be suppressed? This function prints messages to the console already but these messages can be useful if you need to do some debugging.
#'
#' @return A raster representation of streams and, if requested, a vector representation of streams. Returned as terra objects and saved to disk if `save_path` is not null.
#' @export
#'
#' @examplesIf whitebox::check_whitebox_binary()
#'\donttest{
#'
#' hydroDEM <- hydroProcess(elev, 200, streams, n.cores = 2)
#' res <- createStreams(hydroDEM, 50, n.cores = 2)
#'
#' terra::plot(res$streams_derived)
#' }

createStreams <- function(DEM, threshold, vector = NULL, save_path = NULL,  n.cores = NULL, force_update_wbt = FALSE, silent_wbt = TRUE) {

  # Initial checks
  if (!is.null(vector)) {
    if (!(vector %in% c("env", "gpkg", "shp"))) {
      stop("Check your value for parameter 'vector'.")
    }
  }
  #change terra options to allow greater RAM fraction use
  old <- terra::terraOptions(print = FALSE)
  terra::terraOptions(memfrac = 0.9)
  on.exit(terra::terraOptions(memfrac = old$memfrac), add = TRUE)

  if (silent_wbt) {
    old_option <- whitebox::wbt_verbose()
    whitebox::wbt_verbose(FALSE)
    if (!is.null(old_option)) {
      if (old_option) {
        on.exit(options("whitebox.verbose_mode" = TRUE))
      }
    } else {
      on.exit(whitebox::wbt_verbose(TRUE), add = TRUE)
    }
  }

  #initial checks
  rlang::check_installed("whitebox", reason = "required to use function drainageBasins") #This is here because whitebox is not a 'depends' of this package; it is only necessary for this function and is therefore in "suggests"
  invisible(utils::capture.output(wbtCheck(force = force_update_wbt, silent = TRUE))) #Check whitebox binaries existence and version, install if necessary or if force_update_wbt = TRUE.

  # Change whitebox max core options to user request
  cores <- parallel::detectCores()
  if (!is.null(n.cores)) {
    if (cores < n.cores) {
      n.cores <- cores - 1
    }
    old.wbt.opts <- as.integer(Sys.getenv("R_WHITEBOX_MAX_PROCS", unset = NA))
    Sys.setenv("R_WHITEBOX_MAX_PROCS" = n.cores)
    on.exit(if (is.na(old.wbt.opts)) Sys.unsetenv("R_WHITEBOX_MAX_PROCS") else Sys.setenv("R_WHITEBOX_MAX_PROCS" = old.wbt.opts), add = TRUE)
  }

  if (inherits(DEM, "SpatRaster")) {
    temp_dir <- paste0(tempdir(), "/createStreams")
    suppressWarnings(dir.create(temp_dir))
    suppressWarnings(unlink(list.files(temp_dir, full.names = TRUE), recursive = TRUE, force = TRUE))
    terra::writeRaster(DEM, paste0(temp_dir, "/rast.tif"))
    dem_path <- paste0(temp_dir, "/rast.tif")
    directory <- temp_dir
  } else if (inherits(DEM, "character")) {
    directory <- if (is.null(save_path)) dirname(DEM) else save_path
    temp_dir <- paste0(tempdir(), "/createStreams")
    suppressWarnings(dir.create(temp_dir))
    suppressWarnings(unlink(list.files(temp_dir, full.names = TRUE), recursive = TRUE, force = TRUE))
    dem_path <- DEM
    DEM <- terra::rast(dem_path)
  } else {
    stop("Parameter DEM must be either a terra SpatRaster or a path to a raster.")
  }

  message("Calculating a flow accumulation raster...")
  whitebox::wbt_d8_flow_accumulation(input = dem_path,
                                     output = paste0(directory, "/D8fac.tif"))
  d8fac <- terra::rast(paste0(directory, "/D8fac.tif"))

  message("Calculating a flow directions raster...")
  whitebox::wbt_d8_pointer(dem = dem_path,
                           output = paste0(directory, "/D8pointer.tif"))
  d8pntr <- terra::rast(paste0(directory, "/D8pointer.tif"))

  # Make a raster of streams only from the DEM, with a threshold (in cells) for flow accumulation
  message("Creating a raster of streams based on the flow accumulation raster...")
  whitebox::wbt_extract_streams(flow_accum = paste0(directory, "/D8fac.tif"),
                                output = paste0(directory, "/streams_derived.tif"),
                                threshold = threshold)
  streams_derived <- terra::rast(paste0(directory, "/streams_derived.tif"))

  tryCatch({
    if (!is.null(vector)) {
      streams_vector <- terra::as.lines(streams_derived)
      if (vector == "shp" & !is.null(save_path)) {
        terra::writeVector(streams_vector, paste0(directory, "/streams_vector.shp"))
      } else if (vector == "gpkg" & !is.null(save_path)) {
        terra::writeVector(streams_vector, paste0(directory, "/streams_vector.gpkg"))
      }
    }
  }, error = function(e) {
    warning("Failed to vectorize the derived streams raster, likely because the raster was too large for function terra::as.lines()")
    vector <<- NULL
  })

  return(list(flow_accum = d8fac, flow_dir = d8pntr, streams_derived = streams_derived, streams_vector = if (exists("streams_vector")) streams_vector else NULL))
}


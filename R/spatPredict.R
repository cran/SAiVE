#' Predict spatial variables using machine learning
#'
#' @author Ghislain de Laplante (gdela069@uottawa.ca or ghislain.delaplante@yukon.ca)
#'
#' @description
#' `r lifecycle::badge("stable")`
#'
#' Function to facilitate the prediction of spatial variables using machine learning, including the selection of a particular model and/or model parameters from several user-defined options. Both classification and regression is supported, though please ensure that the models passed to the parameter `methods` are suitable.
#'
#' Note that you may need to acquiesce to installing supplementary packages, depending on the model types chosen and whether or not these have been run before; this function may not be 'set and forget'.
#'
#' It is possible to specify multiple machine learning methods (the `methods` parameter) as well as method-specific parameters (the `trainControl` parameter) if you wish to test multiple options and select the best one. To facilitate method selection, refer to function [modelMatch()]. If you are unsure of the best model to use, you can use the `fastCompare` parameter to quickly compare models and select the best one based on accuracy. If you wish to use a single model and/or trainControl object, you can pass a single string to `methods` and a single trainControl object to `trainControl`.
#'
#' Warning options are changed for this function only to show all warnings as they occur and reset back to their original state upon function completion (a test is done first to ensure it can be reset). This is to ensure that any warnings when running models are shown in sequence with the messages indicating the progress of the function, especially when running multiple models and/or trainControl options.
#'
#' @details
#' This function partly operates as a convenient means of passing various parameters to the [caret::train()] function, enabling the user to rapidly trial different model types and parameter sets. In addition, pre-processing of data can optionally be done using [VSURF::VSURF()] (parameter `thinFeatures`) which can decrease the time to run models by removing superfluous parameters.
#'
#' # Model testing, comparison, and reported metrics
#' After extracting raster values at *n* points from the `features` rasters the point values are split spatially into training and testing sets along a 70/30 split. This is accomplished by creating a grid (1000*1000) of polygons over the extent of the points and randomly assigning polygons to training or testing sets. Points within these polygons are then assigned to the corresponding set, ensuring that the training and testing sets are spatially independent.
#'
#' # Method for selecting the best model:
#' When specifying multiple model types in`methods`, each model type and `trainControl` pair (if `trainControl` is a list of length equal to `methods`) is run using [caret::train()]. To speed things up you can use `fastCompare` = TRUE. Models are then compared on their 'accuracy' metric as output by [caret::resamples()] when run on the testing partition, and the highest-performing model is selected. If `fastCompare` is TRUE, this model is then run on the complete data set provided in `outcome`. Model statistics are returned upon function completion, which allows the user to select their own 'best performing' model based on other criteriaif desired.
#'
#' # Balancing classes in outcome (dependent) variable
#' Models can be biased if they are given significantly more points in one outcome class vs others, and best practice is to even out the number of points in each class. If extracting point values from a vector or raster object and passing a points vector object to this function, a simple way to do that is by using the "strata" parameter if using [terra::spatSample()]. If working directly from points, [caret::downSample()] and [caret::upSample()] can be used. See [this link](https://topepo.github.io/caret/subsampling-for-class-imbalances.html) for more information. Note that if passing a polygons object to this function stratified random sampling will automatically be performed.
#'
#' # Classification or regression
#' Whether this function treats your inputs as a classification or regression problem depends on the class attached to the outcome variable. A class `factor` will be treated as a classification problem while all other classes will be treated as regression problems.
#'
#'
#' @param features Independent variables. Must be either a NAMED list of terra spatRasters or a multi-layer (stacked) spatRaster (c(rast1, rast2). All layers must all have the same cell size, alignment, extent, and crs. These rasters should include the training extent (that covered by the spatVector in `outcome`) as well as the desired extrapolation extent.
#' @param outcome Dependent variable, as a terra spatVector of points or polygons with a single attribute table column (of class integer, numeric or factor). The class of this column dictates whether the problem is approached as a classification or regression problem; see details. If specifying polygons, stratified random sampling will be done with `poly_sample` number of points per unique polygon value.
#' @param poly_sample If passing a polygon SpatVector to `outcome`, the number of points to generate from the polygons for each unique polygon value.
#' @param trainControl Parameters used to control training of the machine learning model, created with [caret::trainControl()]. Passed to the `trControl` parameter of [caret::train()]. If specifying multiple methods in `methods` you can use a single `trainControl` which will apply to all `methods`, or pass multiple variations to this argument as a list with names matching the names of `methods` (one element for each model specified in methods).
#' @param methods A string specifying one or more classification/regression methods(s) to use. Passed to the `method` parameter of [caret::train()]. If specifying more than one method they will all be passed to [caret::resamples()] to compare method performance. Then, if `predict = TRUE`, the method with the highest overall accuracy will be selected to predict the raster surface across the exent of `features`. A different `trainControl` parameter can be used for each method in `methods`.
#' @param fastCompare If specifying multiple methods in `methods` or one method with multiple `trainControl` objects, should the points in `outcome` be sub-sampled for the comparison step? The selected method will be trained on the full `outcome` data set after selection. This only applies if `methods` is length > 3, with behavior further modified by fastFraction.
#' @param fastFraction The fraction of points to use for the method comparison step (final training and testing is always done on the full data set) if `fastCompare` is TRUE and multiple methods . Default NULL ranges from 1 for 5000 or fewer points to 0.1 for 50 000 or more points. You can also set this to any value between 0 and 1 to override this behavior.
#' @param thinFeatures Should random forest selection using [VSURF::VSURF()] be used in an attempt to remove irrelevant variables?
#' @param predict TRUE will apply the trained model to the full extent of `features` and return a raster saved to `save_path`.
#' @param n.cores The maximum number of cores to use. Leave NULL to use all cores minus 1.
#' @param save_path The path (folder) to which you wish to save the predicted raster. Not used unless `predict = TRUE`.
#'
#' @return If passing only one method to the `method` argument: the outcome of the VSURF variable selection process (if `thinFeatures` is TRUE), the training and testing data.frames, the fitted model, model performance statistics, and the final predicted raster (if `predict` = TRUE).
#'
#' If passing multiple methods to the `method` argument: the outcome of the VSURF variable selection process (if `thinFeatures` is TRUE), the training and testing data.frames, character vectors for failed methods, methods which generated a warning, and what those errors and warnings were,  model performance comparison (if methods includes more than one method), the selected method, the trained model performance statistics, and the final predicted raster (if `predict` = TRUE).
#'
#' In either case, the predicted raster is written to disk if `save_path` is specified.
#'
#' @export
#' @examplesIf interactive()
#' # These examples can take a while to run!
#'
#' # Install packages underpinning examples
#' rlang::check_installed("ranger", reason = "required to run example.")
#' rlang::check_installed("Rborist", reason = "required to run example.")
#'
#' # Single model, single trainControl
#'
#' trainControl <- caret::trainControl(
#'                 method = "repeatedcv",
#'                 number = 2, # 2-fold Cross-validation
#'                 repeats = 2, # repeated 2 times
#'                 verboseIter = FALSE,
#'                 returnResamp = "final",
#'                 savePredictions = "all",
#'                 allowParallel = TRUE)
#'
#'  outcome <- permafrost_polygons
#'  outcome$Type <- as.factor(outcome$Type)
#'
#' result <- spatPredict(features = c(aspect, solrad, slope),
#'   outcome = outcome,
#'   poly_sample = 100,
#'   trainControl = trainControl,
#'   methods = "ranger",
#'   n.cores = 2,
#'   predict = TRUE)
#'
#' terra::plot(result$prediction)
#'
#'
#' # Multiple models, multiple trainControl
#'
#' trainControl <- list("ranger" = caret::trainControl(
#'                                   method = "repeatedcv",
#'                                   number = 2,
#'                                   repeats = 2,
#'                                   verboseIter = FALSE,
#'                                   returnResamp = "final",
#'                                   savePredictions = "all",
#'                                   allowParallel = TRUE),
#'                      "Rborist" = caret::trainControl(
#'                                    method = "boot",
#'                                    number = 2,
#'                                    repeats = 2,
#'                                    verboseIter = FALSE,
#'                                    returnResamp = "final",
#'                                    savePredictions = "all",
#'                                    allowParallel = TRUE)
#'                                    )
#'
#' result <- spatPredict(features = c(aspect, solrad, slope),
#'   outcome = outcome,
#'   poly_sample = 100,
#'   trainControl = trainControl,
#'   methods = c("ranger", "Rborist"),
#'   n.cores = 2,
#'   predict = TRUE)
#'
#' terra::plot(result$prediction)
#'

spatPredict <- function(features, outcome, poly_sample = 1000, trainControl, methods, fastCompare = TRUE, fastFraction = NULL, thinFeatures = TRUE, predict = FALSE, n.cores = NULL, save_path = NULL)
{

  # Initial setup #####################################################
  old_warn <- options("warn")
  # See if you can set option without modifying it. If not, don't modify it.
  try({
    options(warn = old_warn$warn) #If this succeeds then the option can be modified. If it fails the two lines below are not run and the option is not modified.
    options(warn = 1)
    on.exit(options(warn = old_warn$warn))
  })

  cores <- parallel::detectCores()
  if (!is.null(n.cores)) {
    if (cores < n.cores) {
      n.cores <- cores - 1
    }
  } else {
    n.cores <- cores - 1
  }

  if (!is.null(save_path)) {
    if (!dir.exists(save_path)) {
      stop("The specified directory does not exist. Please create it before pointing to it, or run the function without a save path.")
    }
  }

  results <- list() #This will hold model performance measures and a terra pointer to the created spatRaster


  # Parameter checks ##################################################

  if (!inherits(thinFeatures, "logical")) {
    stop("The parameter 'thinFeatures' must be a logical.")
  }
  if (!inherits(predict, "logical")) {
    stop("The parameter 'predict' must be a logical.")
  }
  if (!inherits(fastCompare, "logical")) {
    stop("The parameter 'fastCompare' must be a logical.")
  }
  if (!is.null(fastFraction)) {
    if (!is.numeric(fastFraction) | fastFraction < 0 | fastFraction > 1) {
      stop("The parameter 'fastFraction' must be a numeric value between 0 and 1.")
    }
  }
  #If multiple models and multiple trainControls passed as arguments, check that names of 'trainControl' list matches those of 'methods'
  if (length(methods) > 1) {
    if (!identical(names(trainControl), names(caret::trainControl()))) { #if this is true then multiple trainControls are passed or attempted to be passed to trainControl
      if (!all(names(trainControl) %in% methods)) { #names in both need to match
        stop("It looks like you are specifying multiple model types in 'methods' along with multiple versions of trainControl, but the names of both don't match. Please review the function help and try again.")
      } else {
        multi_trainControl <- TRUE
      }
    } else { #only one trainControl despite multiple model types passed to 'methods'
      multi_trainControl <- FALSE
    }
  } else {
    if (!identical(names(trainControl), names(caret::trainControl()))) {
      stop("It looks like you're specifying multiple trainControl objects under parameter trainControl, but only a single model in 'methods'. Please review your inputs.")
    } else {
      multi_trainControl <- FALSE
    }
  }

  if (is.null(names(features))) {
    stop("Looks like you're giving me an unnamed list for 'features'. Names please.")
  }
  if (!inherits(outcome, "SpatVector")) {
    stop("The parameter 'outcome' must be a terra SpatVector (points of polygons).")
  }
  if (ncol(as.data.frame(outcome)) != 1) {
    stop("Looks like the attribute table for the outcome does not contain exactly one column. See the help file and try again.")
  }

  outcome_class <- class(as.data.frame(outcome)[,1])

  if (!(outcome_class %in% c("factor", "numeric", "integer"))) {
    stop("The outcome variable should be factor, numeric, or integer class.")
  }


  if (inherits(features, "list")) {
    features <- terra::rast(features) #In case they were input as a list of raster objects and not a stacked spatRaster
  } else if (!inherits(features, "SpatRaster")) {
    stop("'features' must be specified as a stacked SpatRaster object (c(raster1, raster2)) or as a list of SpatRasters (list(raster1, raster2).")
  }
  # stop if names of 'features' are not unique
  if (length(unique(names(features))) != length(names(features))) {
    stop("The names of the features must be unique.")
  }

  # Projecting, making points, and extracting values from rasters ####################
  crs.identical <- sapply(features, function(x) terra::same.crs(x, features[[1]]))
  ext.identical <- sapply(features, function(x) terra::compareGeom(x, features[[1]]))
  if (FALSE %in% crs.identical) {
    stop("The features you specified do not have the same coordinate reference system. Please check and try again.")
  }
  if (FALSE %in% ext.identical) {
    stop("The features you specified do not have the exact same extents. Please check and try again.")
  }
  outcome <- terra::project(outcome, features[[1]]) #Make sure the points have the same crs as the features.

  if (terra::geomtype(outcome) == "polygons") {
    message("Sampling the polygons...")
    col_name <- names(outcome)[1]
    outcome <- terra::spatSample(outcome, size = poly_sample, strata = col_name)  # outcome is modified here to be a points SpatVector
  } else if (terra::geomtype(outcome) == "points") {
    #Nothing being done with points right now
  } else {
    stop("'outcome' can only be a terra SpatVector of points or polygons.")
  }

  message("Extracting raster values for each point in 'outcome'...")
  featureValues <- terra::extract(features, outcome, ID = FALSE) #get point values as a matrix
  TrainingData <- cbind(outcome, featureValues)

  TrainingDataFrame <- as.data.frame(TrainingData) #Create data.frame of TrainingData with type as factor as VSURF can't use the terra object
  #select columns with predictor variables. VSURF selects relevant variables based on random forest classification in a three step process. Step one (thresholding) eliminates irrelevant variables from the dataset, then steps 2 and 3 further refine the selection. Variables are then assigned a measure of relative importance that can be viewed.

  # Remove irrelevant features using VSURF ########################################
  if (thinFeatures) {
    message("Running VSURF algorithm to select only relevant variables...")
    tryCatch({
      res <- thinFeatures(TrainingDataFrame, names(TrainingDataFrame)[1], n.cores = n.cores)
      results$VSURF_outcome <- res$VSURF_outcome
      TrainingDataFrame <- TrainingDataFrame[ , names(res$subset_data)]
      TrainingData <- TrainingData[ , names(res$subset_data)]
    }, error = function(e) {
      warning("Failed to run VSURF algorithm to thin features. Proceeding to model training step with whole data set.")
      results$VSURF_outcome <<- "Failed to run."
      thinFeatures <<- FALSE
    })
  }

  # Split the data into a training and testing data set ###############
  # Create a grid to cover the convex hull of the sampled points
  outcome_ext <- terra::convHull(outcome) # Minimum convex hull around the points.
  grid <- terra::as.polygons(terra::rast(outcome_ext, nrow = 200, ncol = 200, crs = terra::crs(features[[1]]))) # This should be a dense enough grid to handle any dataset, no matter how spatially sparse. The computation isn't too heavy.

  # Retain grid squares only where there are points
  grid_clip <- terra::mask(grid, outcome) #Clip the features to the extent of the outcome
  grid_train <- sample(grid_clip, round(nrow(grid_clip) * 0.7))
  grid_test <- terra::subset(grid_clip, !terra::is.related(grid_clip, grid_train, relation = "covers"))

  # Extract points from the training and testing grids
  Training <- terra::intersect(grid_train, TrainingData)
  results$training <- Training
  Training <- as.data.frame(Training)
  Testing <- terra::intersect(grid_test, TrainingData)
  results$testing <- Testing
  Testing <- as.data.frame(Testing)


  #Train the model(s) using parallel computing ############################

  cluster <- parallel::makePSOCKcluster(n.cores)
  doParallel::registerDoParallel(cluster)
  on.exit(parallel::stopCluster(cluster), add = TRUE)

  if (length(methods) > 1) {
    results$failed_methods <- character()
    results$warned_methods <- character()
    results$error_messages <- character()
    results$warn_messages <- character()
    models <- list()
    if (length(methods) > 3 & fastCompare) {

      if (is.null(fastFraction)) {
        if (nrow(TrainingData) <= 5000) {
          fastFractionCalc <- 1
        } else if (nrow(TrainingData) >= 30000) {
          fastFractionCalc <- 0.1
        } else {
          fastFractionCalc <- 1 + (0.1 - 1) * (nrow(TrainingData) - 5000) / (27000)
        }
      }

      Training.sub <- Training[sample(nrow(Training), nrow(Training) * fastFractionCalc), ]
      Testing.sub <- Testing[sample(nrow(Testing), nrow(Testing) * fastFractionCalc), ]
      if (!identical(as.vector(unique(Training[,1]))[order(as.vector(unique(Training[,1])))], as.vector(unique(Training.sub[,1]))[order(as.vector(unique(Training.sub[,1])))])) { #Checks if every factor in Training is present in Training.sub, which is theoretically possible!
        Training.sub <- Training[sample(nrow(Training), 2500), ]
      }
      if (!identical(as.vector(unique(Testing[,1]))[order(as.vector(unique(Testing[,1])))], as.vector(unique(Testing.sub[,1]))[order(as.vector(unique(Testing.sub[,1])))])) { #Checks if every factor in Testing is present in Testing.sub, which is theoretically possible!
        Testing.sub <- Testing[sample(nrow(Testing), 1000), ]
      }
      message("Training multiple models (on down-sampled training data for speed)...")
      redo_best <- TRUE

      for (i in methods) {
        message(paste0("Working on model '", i, "'"))
        current_warnings <- character(0) # Initialize to store unique warnings for this iteration

        tryCatch({
          iter <- caret::train(x = Training.sub[,-1,], # Predictor variables
                               y = as.factor(Training.sub[,1]), # Outcome variable
                               method = i,
                               trControl = if (multi_trainControl) trainControl[[i]] else trainControl)

          if (inherits(iter, "train")) {
            models[[i]] <- iter
            message("Model training complete for ", i)
          } else {
            stop("Model training failed for ", i, ": output was not of class 'train'")
          }
        }, warning = function(w) {
          w_message <- conditionMessage(w)
          if (!w_message %in% current_warnings) {
            current_warnings <<- c(current_warnings, w_message) # Log unique warning
            warning_message <- paste0("Warning while running model ", i, ": ", w_message)
            warning(warning_message)
            results$warn_messages <<- c(results$warn_messages, warning_message)
            results$warned_methods <<- c(results$warned_methods, i)
          }
        }, error = function(e) {
          error_message <- paste0("Error in model ", i, ": ", conditionMessage(e))
          warning(error_message) # Log the error
          results$error_messages <<- c(results$error_messages, error_message)
          results$failed_methods <<- c(results$failed_methods, i)
        })
      }
    } else {
      redo_best <- FALSE
      message("Training multiple models and finding the best one...")
      for (i in methods) {
        message(paste0("Working on model '", i, "'"))
        current_warnings <- character(0) # Initialize to store unique warnings for this iteration

        tryCatch({
          iter <- caret::train(x = Training[,-1,], # Predictor variables
                               y = as.factor(Training[,1]), # Outcome variable
                               method = i,
                               trControl = if (multi_trainControl) trainControl[[i]] else trainControl)

          if (inherits(iter, "train")) {
            models[[i]] <- iter
            message("Model training complete for ", i)
          } else {
            stop("Model training failed for ", i, ": output was not of class 'train'")
          }
        }, warning = function(w) {
          w_message <- conditionMessage(w)
          if (!w_message %in% current_warnings) {
            current_warnings <<- c(current_warnings, w_message) # Log unique warning
            warning_message <- paste0("Warning while running model ", i, ": ", w_message)
            warning(warning_message)
            results$warn_messages <<- c(results$warn_messages, warning_message)
            results$warned_methods <<- c(results$warned_methods, i)
          }
        }, error = function(e) {
          error_message <- paste0("Error in model ", i, ": ", conditionMessage(e))
          warning(error_message) # Log the error
          results$error_messages <<- c(results$error_messages, error_message)
          results$failed_methods <<- c(results$failed_methods, i)
        })
      }
    }

    results$trained_models_performance <- list()
    for (i in 1:length(models)) {
      test <- stats::predict(models[[i]], newdata = Testing[,-1])
      results$trained_models_performance[[names(models[i])]] <- caret::confusionMatrix(data = test, as.factor(Testing[,1]))
    }

    accuracy <- numeric()
    for (i in 1:length(results$trained_models_performance)) {
      accuracy[[names(models)[i]]] <- results$trained_models_performance[[i]]$overall[1]
    }
    name <- names(which(accuracy == max(accuracy)))

    if (length(name) > 1) {
      message("Models ", name[1], " and ", name[2], " have the same accuracy. ", name[1], " will be selected to train and test on the full dataset.")
      name <- name[1]
    } else {
      message(paste0("Model selection and training complete. Selected model '", name, "' based on accuracy."))
    }
    model <- models[[name]]
    results$selected_method <- name


    if (redo_best) {
      message("Re-training the best model on the full training data set...")
      model <- caret::train(x = Training[,-1,], #predictor variables
                   y = as.factor(Training[,1]), #outcome variable
                   method = name,
                   trControl = if (multi_trainControl) trainControl[[name]] else trainControl)
       message("Model training complete. ")
    }
  } else { #There is only a single method specified and only one trainControl
    tryCatch({
      message("Training the model...")
      model <- caret::train(x = Training[,-1,], #predictor variables
                            y = as.factor(Training[,1]), #outcome variable
                            method = methods,
                            trControl = trainControl)
      message("Model training complete. ")
      results$selected_method <- methods
    }, error = function(e) {
      stop(paste0("Failed to run model ", methods, " with the dataset and parameters specified."))
    })
  }
  results$best_model <- model
  message("Model-specific hyperparameters were adjusted automatically; refer to returned object results$selected_model to see the result.")

  #Test the selected model and save statistics
  test <- stats::predict(model, newdata = Testing)
  results$selected_model_performance <- caret::confusionMatrix(data = test, as.factor(Testing[,1]))

  if (predict) {
    if (thinFeatures) {
      features <- terra::subset(features, names(TrainingDataFrame)[-1]) #remove layers from the raster stack using the pruned TrainingDataFrame (post-VSURF, if thinFeatures was set to TRUE)
    }
    message("Running the model on the full extent of 'features' and saving to disk...")
    tryCatch({
      results$prediction <- terra::predict(object = features, model = model, na.rm = TRUE, progress = 'text', filename = if (!is.null(save_path)) paste0(save_path, "/Prediction_", Sys.Date(), ".tif") else "", overwrite = TRUE, cores = n.cores)
    }, error = function(e) {
      warning("Failed to run the model on the full extent of 'features'. This could be a fault in either running the model or saving the results to disk. To avoid re-running this function from scratch refer to the function outputs for the selected model and apply it to your predictor variables.")
    })
  }

  message("Finished. Returning results.")
  return(results)
}

#' Create an inlabru model object from model components
#'
#' The [inlabru] syntax for model formulae is different from what
#' `INLA::inla` considers a valid.
#' In inla most of the effects are defined by adding an `f(...)` expression to the formula.
#' In [inlabru] the `f` is replaced by an arbitrary (exceptions: `const` and `offset`)
#' string that will determine the label of the effect. See Details for further information.
#'
#' @details
#' For instance
#'
#' `y ~ f(myspde, ...)`
#'
#' in INLA is equivalent to
#'
#' `y ~ myspde(...)`
#'
#' in inlabru.
#'
#' A disadvantage of the inla way is that there is no clear separation between the name of the covariate
#' and the label of the effect. Furthermore, for some models like SPDE it is much more natural to
#' use spatial coordinates as covariates rather than an index into the SPDE vertices. For this purpose
#' [inlabru] provides the new `main` agument. For convenience, the `main` argument can be used
#' like the first argument of the f function, e.g., and is the first argument of the component definition.
#'
#' `y ~ f(temperature, model = 'linear')`
#'
#' is equivalent to
#'
#' `y ~ temperature(temperature, model = 'linear')`
#' and
#' `y ~ temperature(main = temperature, model = 'linear')`
#' as well as
#' `y ~ temperature(model = 'linear')`
#' which sets `main = temperature`.
#'
#' On the other hand, map can also be a function mapping, e.g the [coordinates] function of the
#' [sp] package :
#'
#' `y ~ mySPDE(coordinates, ...)`
#'
#' This exctract the coordinates from the data object, and maps it to the latent
#' field via the information given in the `mapper`, which by default is
#' extracted from the `model` object, in the case of `spde` model
#' objects.
#'
#' Morevover, `main` can be any expression that evaluates within your data as an environment.
#' For instance, if your data has columns 'a' and 'b', you can create a fixed effect of 'sin(a+b)' by
#' setting `map` in the following way:
#'
#' `y ~ myEffect(sin(a+b))`
#'
#'
#' @export
#' @param components A [component_list] object
#' @param lhoods A list of one or more `lhood` objects
#' @return A [bru_model] object
#' @keywords internal

bru_model <- function(components, lhoods) {
  stopifnot(inherits(components, "component_list"))

  # Back up environment
  env <- environment(components)

  # Complete the component definitions based on data
  components <- component_list(components, lhoods)

  # Create joint formula that will be used by inla
  formula <- BRU_response ~ -1
  linear <- TRUE
  included <- character(0)
  for (lh in lhoods) {
    linear <- linear && lh[["linear"]]
    included <- union(
      included,
      parse_inclusion(
        names(components),
        include = lh[["include_components"]],
        exclude = lh[["exclude_components"]]
      )
    )
  }

  for (cmp in included) {
    if (linear ||
      !(components[[cmp]][["main"]][["type"]] %in% c("offset", "const"))) {
      formula <- update.formula(formula, components[[cmp]]$inla.formula)
    }
  }

  # Restore environment
  environment(formula) <- env

  # Make model
  mdl <- list(effects = components, formula = formula)
  class(mdl) <- c("bru_model", "list")
  return(mdl)
}


#' @export
#' @method summary bru_model
#' @param object Object to operate on
#' @param \dots Arguments passed on to other methods
#' @rdname bru_model
summary.bru_model <- function(object, ...) {
  result <- list(
    components =
      summary(object[["effects"]], ...)
  )
  class(result) <- c("summary_bru_model", "list")
  result
}

#' @export
#' @param x A `summary_bru_model` object to be printed
#' @rdname bru_model
print.summary_bru_model <- function(x, ...) {
  print(x[["components"]])
  invisible(x)
}




#' Evaluate or sample from a posterior result given a model and locations
#'
#' @export
#' @param model A [bru] model
#' @param state list of state lists, as generated by [evaluate_state()]
#' @param data A `list`, `data.frame`, or `Spatial*DataFrame`, with coordinates
#' and covariates needed to evaluate the predictor.
#' @param input Precomputed inputs list for the components
#' @param comp_simple Precomputed `comp_simple_list` for the components
#' @param predictor A formula or an expression to be evaluated given the
#' posterior or for each sample thereof. The default (`NULL`) returns a
#' `data.frame` containing the sampled effects. In case of a formula the right
#' hand side is used for evaluation.
#' @param format character; determines the storage format of predictor output.
#' Available options:
#' * `"auto"` If the first evaluated result is a vector or single-column matrix,
#'   the "matrix" format is used, otherwise "list".
#' * `"matrix"` A matrix where each column contains the evaluated predictor
#' expression for a state.
#' * `"list"` A list where each element contains the evaluated predictor
#' expression for a state.
#' @param n Number of samples to draw.
#' @param seed If seed != 0L, the random seed
#' @param num.threads Specification of desired number of threads for parallel
#' computations. Default NULL, leaves it up to INLA.
#' When seed != 0, overridden to "1:1"
#' @param include Character vector of component labels that are needed by the
#'   predictor expression; Default: NULL (include all components that are not
#'   explicitly excluded)
#' @param exclude Character vector of component labels that are not used by the
#'   predictor expression. The exclusion list is applied to the list
#'   as determined by the `include` parameter; Default: NULL (do not remove
#'   any components from the inclusion list)
#' @param \dots Additional arguments passed on to `inla.posterior.sample`
#' @details * `evaluate_model` is a wrapper to evaluate model state, A-matrices,
#' effects, and predictor, all in one call.
#'
#' @keywords internal
#' @rdname evaluate_model
evaluate_model <- function(model,
                           state,
                           data = NULL,
                           input = NULL,
                           comp_simple = NULL,
                           predictor = NULL,
                           format = NULL,
                           include = NULL,
                           exclude = NULL,
                           ...) {
  included <- parse_inclusion(names(model$effects), include, exclude)

  if (is.null(state)) {
    stop("Not enough information to evaluate model states.")
  }
  if (is.null(input) && !is.null(data)) {
    input <- input_eval(
      components = model$effects[included],
      data = data,
      inla_f = TRUE
    )
  }
  if (is.null(comp_simple) && !is.null(input)) {
    comp_simple <- evaluate_comp_simple(model$effects[included],
      input = input,
      inla_f = TRUE
    )
  }
  if (is.null(comp_simple)) {
    effects <- NULL
  } else {
    effects <- evaluate_effect_multi_state(
      comp_simple,
      state = state,
      input = input
    )
  }

  if (is.null(predictor)) {
    return(effects)
  }

  values <- evaluate_predictor(
    model,
    state = state,
    data = data,
    effects = effects,
    predictor = predictor,
    format = format
  )

  values
}


#' @details * `evaluate_state` evaluates model state properties or samples
#' @param result A `bru` object from [bru()] or [lgcp()]
#' @param property Property of the model components to obtain value from.
#' Default: "mode". Other options are "mean", "0.025quant", "0.975quant",
#' "sd" and "sample". In case of "sample" you will obtain samples from the
#' posterior (see `n` parameter). If `result` is `NULL`, all-zero vectors are
#' returned for each component.
#' @param internal_hyperpar logical; If `TRUE`, return hyperparameter properties
#' on the internal scale. Currently ignored when `property="sample"`.
#' Default is `FALSE`.
#' @export
#' @rdname evaluate_model
evaluate_state <- function(model,
                           result,
                           property = "mode",
                           n = 1,
                           seed = 0L,
                           num.threads = NULL,
                           internal_hyperpar = FALSE,
                           ...) {
  # Evaluate random states, or a single property
  if (property == "sample") {
    state <- inla.posterior.sample.structured(result,
      n = n, seed = seed,
      num.threads = num.threads,
      ...
    )
  } else if (is.null(result)) {
    state <- list(lapply(
      model[["effects"]],
      function(x) {
        rep(0.0, ibm_n(x[["mapper"]]))
      }
    ))
  } else {
    state <- list(extract_property(
      result = result,
      property = property,
      internal_hyperpar = internal_hyperpar
    ))
  }

  state
}




#' @export
#' @rdname evaluate_effect
evaluate_effect_single_state <- function(...) {
  UseMethod("evaluate_effect_single_state")
}
#' @export
#' @rdname evaluate_effect
evaluate_effect_multi_state <- function(...) {
  UseMethod("evaluate_effect_multi_state")
}

#' Evaluate a component effect
#'
#' Calculate latent component effects given some data and the state of the
#' component's internal random variables.
#'
#' @export
#' @keywords internal
#' @param component A `bru_component`, `comp_simple`, or `comp_simple_list`.
#' @param input Pre-evaluated component input
#' @param state Specification of one (for `evaluate_effect_single_state`) or several
#' (for `evaluate_effect_multi_State`) latent variable states:
#' * `evaluate_effect_single_state.bru_mapper`: A vector of the latent component state.
#' * `evaluate_effect_single_state.*_list`: list of named state vectors.
#' * `evaluate_effect_multi_state.*_list`: list of lists of named state vectors.
#' @param ... Optional additional parameters, e.g. `inla_f`. Normally unused.
#' @author Fabian E. Bachl \email{bachlfab@@gmail.com} and
#' Finn Lindgren \email{finn.lindgren@@gmail.com}
#' @rdname evaluate_effect

evaluate_effect_single_state.bru_mapper <- function(component, input, state,
                                                    ...) {
  values <- ibm_eval(component, input = input, state = state, ...)

  as.vector(as.matrix(values))
}

#' @return * `evaluate_effect_single_state.component_list`: A list of evaluated
#' component effect values
#' @export
#' @rdname evaluate_effect
#' @keywords internal
evaluate_effect_single_state.comp_simple_list <- function(components,
                                                          input,
                                                          state,
                                                          ...) {
  result <- list()
  for (label in names(components)) {
    result[[label]] <- evaluate_effect_single_state(
      components[[label]],
      input = input[[label]],
      state = state[[label]],
      ...
    )
  }
  result
}

#' @return * `evaluate_effect_multi.comp_simple_list`: A list of lists of
#' evaluated component effects, one list for each state
#' @export
#' @rdname evaluate_effect
#' @keywords internal
evaluate_effect_multi_state.comp_simple_list <- function(components, input, state, ...) {
  lapply(
    state,
    function(x) {
      evaluate_effect_single_state(
        components,
        input = input,
        state = x,
        ...
      )
    }
  )
}

#' @export
#' @rdname evaluate_effect
#' @keywords internal
evaluate_effect_single_state.component_list <- function(components, input, state, ...) {
  comp_simple <- evaluate_comp_simple(components, input = input, ...)
  evaluate_effect_single_state(comp_simple, input = input, state = state, ...)
}
#' @export
#' @rdname evaluate_effect
#' @keywords internal
evaluate_effect_multi_state.component_list <- function(components, input, state, ...) {
  comp_simple <- evaluate_comp_simple(components, input = input, ...)
  evaluate_effect_multi_state(comp_simple, input = input, state = state, ...)
}




#' Evaluate component effects or expressions
#'
#' Evaluate component effects or expressions, based on a bru model and one or
#' several states of the latent variables and hyperparameters.
#'
#' @param data A `list`, `data.frame`, or `Spatial*DataFrame`, with coordinates
#' and covariates needed to evaluate the model.
#' @param state A list where each element is a list of named latent state
#' information, as produced by [evaluate_state()]
#' @param effects A list where each element is list of named evaluated effects,
#' as computed by [evaluate_effect_multi_state.component_list()]
#' @param predictor Either a formula or expression
#' @param format character; determines the storage format of the output.
#' Available options:
#' * `"auto"` If the first evaluated result is a vector or single-column matrix,
#'   the "matrix" format is used, otherwise "list".
#' * `"matrix"` A matrix where each column contains the evaluated predictor
#' expression for a state.
#' * `"list"` A list where each column contains the evaluated predictor
#' expression for a state.
#' @param inla_f logical
#'
#' Default: "auto"
#' @details For each component, e.g. "name", the state values are available as
#' `name_latent`, and arbitrary evaluation can be done with `name_eval(...)`, see
#' [component_eval()].
#' @return A list or matrix is returned, as specified by `format`
#' @keywords internal
#' @rdname evaluate_predictor
evaluate_predictor <- function(model,
                               state,
                               data,
                               effects,
                               predictor,
                               format = "auto") {
  stopifnot(inherits(model, "bru_model"))
  format <- match.arg(format, c("auto", "matrix", "list"))
  pred.envir <- environment(predictor)
  if (inherits(predictor, "formula")) {
    predictor <- parse(text = as.character(predictor)[length(as.character(predictor))])
  }
  formula.envir <- environment(model$formula)
  enclos <-
    if (!is.null(pred.envir)) {
      pred.envir
    } else if (!is.null(formula.envir)) {
      formula.envir
    } else {
      parent.frame()
    }

  envir <- new.env(parent = enclos)
  # Find .data. first,
  # then data variables,
  # then pred.envir variables (via enclos),
  # then formula.envir (via enclos if pred.envir is NULL):
  #  for (nm in names(pred.envir)) {
  #    assign(nm, pred.envir[[nm]], envir = envir)
  #  }
  if (is.list(data)) {
    for (nm in names(data)) {
      assign(nm, data[[nm]], envir = envir)
    }
  } else {
    data_df <- as.data.frame(data)
    for (nm in names(data_df)) {
      assign(nm, data_df[[nm]], envir = envir)
    }
  }
  assign(".data.", data, envir = envir)

  # Rename component states from label to label_latent
  state_names <- as.list(expand_labels(
    names(state[[1]]),
    names(model$effects),
    suffix = "_latent"
  ))
  names(state_names) <- names(state[[1]])

  # Construct _eval function names
  eval_names <- as.list(expand_labels(
    intersect(names(state[[1]]), names(model$effects)),
    intersect(names(state[[1]]), names(model$effects)),
    suffix = "_eval"
  ))
  names(eval_names) <- intersect(names(state[[1]]), names(model$effects))

  eval_fun_factory <-
    function(.comp, .envir, .enclos) {
      .is_offset <- .comp$main$type %in% c("offset", "const")
      .is_iid <- .comp$main$type %in% c("iid")
      .mapper <- .comp$mapper
      .label <- paste0(.comp$label, "_latent")
      .iid_precision <- paste0("Precision_for_", .comp$label)
      .iid_cache <- list()
      .iid_cache_index <- NULL
      eval_fun <- function(main, group = NULL,
                           replicate = NULL,
                           weights = NULL,
                           .state = NULL) {
        if (is.null(group)) {
          group <- rep(1, NROW(main))
        }
        if (is.null(replicate)) {
          replicate <- rep(1, NROW(main))
        }
        if (!.is_offset && is.null(.state)) {
          .state <- eval(
            parse(text = .label),
            envir = .envir,
            enclos = .enclos
          )
        }
        .input <- list(
          mapper = list(
            main = main,
            group = group,
            replicate = replicate
          ),
          scale = weights
        )

        .values <- ibm_eval(
          .mapper,
          input = .input,
          state = .state
        )
        if (.is_iid) {
          # Check for known invalid output elements, based on the
          # initial mapper (subsequent mappers in the component pipe
          # are assumed to keep the same length and validity)
          not_ok <- ibm_invalid_output(
            .mapper[["mappers"]][[1]],
            input = .input[[1]],
            state = .state
          )
          if (any(not_ok)) {
            .cache_state_index <- eval(
              parse(text = ".cache_state_index"),
              envir = .envir,
              enclos = .enclos
            )
            if (!identical(.cache_state_index, .iid_cache_index)) {
              .iid_cache_index <<- .cache_state_index
              .iid_cache <<- list()
            }
            key <- as.character(main[not_ok])
            not_cached <- !(key %in% names(.iid_cache))
            if (any(not_cached)) {
              .prec <- eval(
                parse(text = .iid_precision),
                envir = .envir,
                enclos = .enclos
              )
              for (k in unique(key[not_cached])) {
                .iid_cache[k] <<- rnorm(1, mean = 0, sd = .prec^-0.5)
              }
            }
            .values[not_ok] <- vapply(
              key,
              function(k) .iid_cache[[k]],
              0.0
            )
          }
        }

        as.matrix(.values)
      }
      eval_fun
    }
  for (nm in names(eval_names)) {
    assign(eval_names[[nm]],
      eval_fun_factory(model$effects[[nm]], .envir = envir, .enclos = enclos),
      envir = envir
    )
  }

  # Remove problematic objects:
  problems <- c(".Random.seed")
  remove(list = intersect(names(envir), problems), envir = envir)

  n <- length(state)
  for (k in seq_len(n)) {
    # Keep track of the iteration index so the iid cache can be invalidated
    assign(".cache_state_index", k, envir = envir)

    for (nm in names(state[[k]])) {
      assign(state_names[[nm]], state[[k]][[nm]], envir = envir)
    }
    for (nm in names(effects[[k]])) {
      assign(nm, effects[[k]][[nm]], envir = envir)
    }

    result_ <- eval(predictor, envir = envir, enclos = enclos)
    if (k == 1) {
      if (identical(format, "auto")) {
        if ((is.vector(result_) && !is.list(result_)) ||
          (is.matrix(result_) && (NCOL(result_) == 1))) {
          format <- "matrix"
        } else {
          format <- "list"
        }
      }
      if (identical(format, "matrix")) {
        result <- matrix(0.0, NROW(result_), n)
        rownames(result) <- row.names(as.matrix(result_))
      } else if (identical(format, "list")) {
        result <- vector("list", n)
      }
    }
    if (identical(format, "list")) {
      result[[k]] <- result_
    } else {
      result[, k] <- result_
    }
  }

  result
}



#' Evaluate component values in predictor expressions
#'
#' In predictor expressions, `name_eval(...)` can be used to evaluate
#' the effect of a component called "name".
#'
#' @param main,group,replicate,weights Specification of where to evaluate a component.
#'   The four inputs are passed on to the joint `bru_mapper` for the component,
#'   as
#'  ```
#'  list(mapper = list(
#'         main = main,
#'         group = group,
#'         replicate = replicate),
#'       scale = weights)
#' ````
#' @param .state The internal component state. Normally supplied automatically
#' by the internal methods for evaluating inlabru predictor expressions.
#' @return A vector of values for a component
#' @aliases component_eval
#' @examples
#' \dontrun{
#' if (bru_safe_inla()) {
#'   mesh <- INLA::inla.mesh.2d(
#'     cbind(0, 0),
#'     offset = 2, max.edge = 0.25
#'   )
#'   spde <- INLA::inla.spde2.pcmatern(mesh,
#'     prior.range = c(0.1, 0.01),
#'     prior.sigma = c(2, 0.01)
#'   )
#'   data <- sp::SpatialPointsDataFrame(
#'     matrix(runif(10), 5, 2),
#'     data = data.frame(z = rnorm(5))
#'   )
#'   fit <- bru(z ~ -1 + field(coordinates, model = spde),
#'     family = "gaussian", data = data
#'   )
#'   pred <- predict(
#'     fit,
#'     data = data.frame(x = 0.5, y = 0.5),
#'     formula = ~ field_eval(cbind(x, y))
#'   )
#' }
#' }
component_eval <- function(main,
                           group = NULL,
                           replicate = NULL,
                           weights = NULL,
                           .state = NULL) {
  stop(paste0(
    "In your predictor expression, use 'mylabel_eval(...)' instead of\n",
    "'component_eval(...)'.  See ?component_eval for more information."
  ))
}





#' Compute all component linearisations
#'
#' Computes individual `bru_mapper_taylor` objects for included components
#' for each model likelihood
#'
#' @param model A `bru_model` object
#' @param input A list of named lists of component inputs
#' @param state A named list of component states
#' @param inla_f Controls the input data interpretations
#' @return A list (class 'comp_simple') of named lists (class 'comp_simple_list')
#' of `bru_mapper_taylor` objects,
#' one for each included component
#' @rdname evaluate_comp_lin
evaluate_comp_lin <- function(model, input, state, inla_f = FALSE) {
  stopifnot(inherits(model, "bru_model"))
  mappers <-
    lapply(
      input,
      function(inp) {
        included <- parse_inclusion(
          names(model[["effects"]]),
          names(inp),
          NULL
        )

        mappers <- comp_lin_eval(
          model[["effects"]][included],
          input = inp[included],
          state = state[included],
          inla_f = inla_f
        )

        class(mappers) <- c("comp_simple_list", class(mappers))
        mappers
      }
    )

  class(mappers) <- c("comp_simple_list_list", class(mappers))
  mappers
}

#' Compute simplified component mappings
#'
#' Computes individual `bru_mapper_taylor` objects for included linear components
#' for each model likelihood, and keeps non-linear mappers intact.
#'
#' @param model A `bru_model` object
#' @param input A list of named lists of component inputs
#' @param inla_f Controls the input data interpretations
#' @return A list (class 'comp_simple_list_list') of named lists (class 'comp_simple_list')
#' of `bru_mapper` objects,
#' one for each included component
#' @export
#' @keywords internal
#' @rdname evaluate_comp_simple
evaluate_comp_simple <- function(...) {
  UseMethod("evaluate_comp_simple")
}

#' @export
#' @rdname evaluate_comp_simple
evaluate_comp_simple.component_list <- function(components, input,
                                                inla_f = FALSE, ...) {
  are_linear <- vapply(
    components,
    function(x) ibm_is_linear(x[["mapper"]]),
    TRUE
  )
  the_linear <- names(components)[are_linear]
  the_nonlinear <- names(components)[!are_linear]

  if (any(are_linear)) {
    mappers <- comp_lin_eval(
      components[the_linear],
      input = input[the_linear],
      state = NULL,
      inla_f = inla_f
    )
  } else {
    mappers <- list()
  }

  if (any(!are_linear)) {
    warning("Non-linear mappers are experimental!", immediate. = TRUE)
    mappers <- c(
      mappers,
      lapply(
        components[the_nonlinear],
        function(x) x[["mapper"]]
      )
    )
  }

  # Reorder
  mappers <- mappers[names(components)]

  class(mappers) <- c("comp_simple_list", class(mappers))
  mappers
}

#' @export
#' @rdname evaluate_comp_simple
evaluate_comp_simple.bru_model <- function(model, input, ...) {
  mappers <-
    lapply(
      input,
      function(inp) {
        included <- parse_inclusion(
          names(model[["effects"]]),
          names(inp),
          NULL
        )

        evaluate_comp_simple(model[["effects"]][included], input = inp, ...)
      }
    )

  class(mappers) <- c("comp_simple_list_list", class(mappers))
  mappers
}

#' Subsetting of comp_simple_list objects, retaining class
#' @export
#' @param x `comp_simple_list` object from which to extract element(s)
#' @param i indices specifying elements to extract
#' @keywords internal
#' @rdname evaluate_comp_simple_list_subsetting
`[.comp_simple_list` <- function(x, i) {
  env <- environment(x)
  object <- NextMethod()
  class(object) <- c("comp_simple_list", "list")
  environment(object) <- env
  object
}



#' Compute all component inputs
#'
#' Computes the component inputs for included components
#' for each model likelihood
#'
#' @param model A `bru_model` object
#' @param lhoods A `bru_like_list` object
#' @param inla_f logical
#' @rdname evaluate_inputs
evaluate_inputs <- function(model, lhoods, inla_f) {
  stopifnot(inherits(model, "bru_model"))
  lapply(
    lhoods,
    function(lh) {
      included <- parse_inclusion(
        names(model[["effects"]]),
        lh[["include_components"]],
        lh[["exclude_components"]]
      )

      input_eval(
        model$effects[included],
        data = lh[["data"]],
        inla_f = inla_f
      )
    }
  )
}

#' Compute all index values
#'
#' Computes the index values matrices for included components
#'
#' @param model A `bru_model` object
#' @param lhoods A `bru__like_list` object
#' @return A named list of `idx_full` and `idx_inla`,
#' named list of indices, and `inla_subset`, and `inla_subset`,
#' a named list of logical subset specifications for extracting the `INLA::f()`
#' compatible index subsets.
#' @rdname evaluate_index
evaluate_index <- function(model, lhoods) {
  stopifnot(inherits(model, "bru_model"))
  included <-
    unique(do.call(
      c,
      lapply(
        lhoods,
        function(lh) {
          parse_inclusion(
            names(model[["effects"]]),
            lh[["include_components"]],
            lh[["exclude_components"]]
          )
        }
      )
    ))

  list(
    idx_full = index_eval(model[["effects"]][included], inla_f = FALSE),
    idx_inla = index_eval(model[["effects"]][included], inla_f = TRUE),
    inla_subset = inla_subset_eval(model[["effects"]][included])
  )
}

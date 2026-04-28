#' Run decision gate
#'
#' Evaluates a named list of check functions and returns gate results.
#' Each check function should return a list with status (PASS/FAIL/CAUTION)
#' and message.
#'
#' @param checks Named list of functions. Each function takes no arguments
#'   and returns list(status = "PASS"|"FAIL"|"CAUTION", message = "...").
#' @param verbose Logical. Print results to console. Default TRUE.
#' @return Named list of gate results.
#' @examples
#' checks <- list(
#'   min_articles = function() {
#'     n <- nrow(dt)
#'     if (n >= 100) list(status = "PASS", message = sprintf("%d articles", n))
#'     else list(status = "CAUTION", message = sprintf("Only %d articles", n))
#'   }
#' )
#' gate <- run_decision_gate(checks)
run_decision_gate <- function(checks, verbose = TRUE) {
  results <- lapply(checks, function(fn) fn())

  if (verbose) {
    for (nm in names(results)) {
      cat(sprintf("[%s] %s: %s\n",
        results[[nm]]$status, nm, results[[nm]]$message
      ))
    }

    n_fail    <- sum(vapply(results, function(r) r$status == "FAIL", logical(1)))
    n_caution <- sum(vapply(results, function(r) r$status == "CAUTION", logical(1)))
    cat(sprintf("\nGate summary: %d FAIL, %d CAUTION, %d PASS\n",
      n_fail, n_caution, length(results) - n_fail - n_caution
    ))
  }

  results
}

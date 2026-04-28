#' Create and save metadata snapshot
#'
#' Captures session and phase metadata for reproducibility tracking.
#'
#' @param phase_name Character. Name of the phase (e.g., "01_retrieval").
#' @param config List. The phase config object.
#' @param gate_results List. Output from run_decision_gate().
#' @param output_files Character vector. Paths to output files produced.
#' @param dictionary_files Character vector. Paths to dictionaries used.
#' @param query_log Character vector. SQL queries executed (retrieval only).
#' @param notes Character. Free text observations.
#' @param output_dir Character. Directory for snapshot file.
#' @return Invisible. The snapshot list.
#' @examples
#' metadata_snapshot("01_retrieval", config, gate, c("data-raw/corpus.rds"))
metadata_snapshot <- function(phase_name,
                              config,
                              gate_results = list(),
                              output_files = character(0),
                              dictionary_files = character(0),
                              query_log = character(0),
                              notes = "",
                              output_dir = "output/metadata") {

  snapshot <- list(
    timestamp        = Sys.time(),
    r_version        = R.version.string,
    package_versions = sapply(loadedNamespaces(), function(p) {
      as.character(packageVersion(p))
    }),
    config           = config,
    dictionaries     = if (length(dictionary_files) > 0) {
      stats::setNames(tools::md5sum(dictionary_files), dictionary_files)
    } else {
      list()
    },
    query_log        = query_log,
    decision_gate    = gate_results,
    outputs          = if (length(output_files) > 0) {
      stats::setNames(tools::md5sum(output_files), output_files)
    } else {
      list()
    },
    notes            = notes
  )

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  filename <- sprintf("meta_%s_%s.rds", phase_name, format(Sys.Date(), "%Y%m%d"))
  filepath <- file.path(output_dir, filename)
  saveRDS(snapshot, filepath)

  cat(sprintf("Metadata snapshot saved: %s\n", filepath))
  invisible(snapshot)
}

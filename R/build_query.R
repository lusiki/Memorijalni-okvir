#' Build destination retrieval query
#'
#' Constructs a parameterised SQL query for a single destination,
#' including ILIKE patterns on TITLE and MENTION_SNIPPET and an
#' optional conjunctive context gate for polysemic names.
#'
#' @param destination_name Character. Human-readable destination name.
#' @param ilike_title Character. ILIKE pattern for TITLE field.
#' @param ilike_snippet Character. ILIKE pattern for MENTION_SNIPPET field.
#' @param context_gate_required Logical. Whether a context gate is needed.
#' @param context_gate_pattern Character. SQL OR pattern for the context gate.
#' @param table_name Character. Name of the source table in DuckDB.
#' @return Character. A complete SQL SELECT statement.
#' @examples
#' build_query("Sinj", "%Sinj%", "%Sinj%", TRUE,
#'   "%hodočašć% OR %Gospa Sinjsk% OR %crkv%")
build_query <- function(destination_name,
                        ilike_title,
                        ilike_snippet,
                        context_gate_required = FALSE,
                        context_gate_pattern = NULL,
                        table_name = "determ") {

  base_where <- sprintf(
    "(TITLE ILIKE '%s' OR MENTION_SNIPPET ILIKE '%s')",
    ilike_title, ilike_snippet
  )

  if (context_gate_required && !is.null(context_gate_pattern)) {
    gate_parts <- trimws(unlist(strsplit(context_gate_pattern, " OR ")))
    gate_clauses <- paste0("FULL_TEXT ILIKE '", gate_parts, "'", collapse = " OR ")
    where_clause <- sprintf("%s AND (%s)", base_where, gate_clauses)
  } else {
    where_clause <- base_where
  }

  sprintf("SELECT * FROM %s WHERE %s", table_name, where_clause)
}

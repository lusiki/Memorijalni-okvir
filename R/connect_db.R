#' Connect to DuckDB
#'
#' Opens a read-only connection to the Determ DuckDB database.
#' The database path is read from CLAUDE.local.md or passed explicitly.
#'
#' @param db_path Character. Path to the .duckdb file.
#'   Default: "C:/Users/lsikic/Luka C/DetermDB/determDB.duckdb"
#' @return A DBI connection object.
#' @examples
#' con <- connect_db()
#' DBI::dbListTables(con)
#' DBI::dbDisconnect(con)
connect_db <- function(db_path = "C:/Users/lsikic/Luka C/DetermDB/determDB.duckdb") {
  stopifnot(file.exists(db_path))
  con <- DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = db_path,
    read_only = TRUE
  )
  con
}

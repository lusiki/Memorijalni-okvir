#' Join dest_type_cat onto a corpus data.table
#'
#' Reads destinations.csv and merges the dest_type_cat column onto dt
#' by matching the `destination` column (lowercase snake_case) against
#' a derived key from destination_name.
#'
#' @param dt data.table with a `destination` column (lowercase snake_case).
#' @param dest_path character. Path to destinations.csv.
#' @return dt with dest_type_cat column added (or updated if already present).
#' @examples
#' dt <- join_dest_type(dt)
join_dest_type <- function(dt, dest_path = "../../dictionaries/destinations.csv") {
  stopifnot(data.table::is.data.table(dt))
  stopifnot("destination" %in% names(dt))

  dest <- data.table::fread(dest_path)
  dest[, dest_key := stringi::stri_trans_general(
    stringi::stri_trans_tolower(
      stringi::stri_replace_all_regex(destination_name, "\\s+", "_"),
      locale = "hr"
    ),
    "Latin-ASCII"
  )]
  dest_map <- dest[, .(dest_key, dest_type_cat)]

  if ("dest_type_cat" %in% names(dt)) dt[, dest_type_cat := NULL]

  dt <- merge(dt, dest_map, by.x = "destination", by.y = "dest_key",
              all.x = TRUE, sort = FALSE)
  dt
}

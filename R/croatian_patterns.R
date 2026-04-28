#' Generate morphological ILIKE patterns for Croatian named entities
#'
#' Takes a canonical destination name and produces wildcarded root
#' patterns covering nominative, genitive, dative, accusative,
#' locative, and instrumental case forms.
#'
#' @param name Character. Canonical destination name.
#' @param root Character. Root to use for wildcarding. If NULL,
#'   auto-detected by trimming the last 1-2 characters.
#' @return Character. ILIKE pattern with % wildcard.
#' @examples
#' croatian_ilike_root("Marija Bistrica", "Marija Bistric")
#' # Returns "%Marija Bistric%"
croatian_ilike_root <- function(name, root = NULL) {
  if (is.null(root)) {
    # Naive truncation: drop last 1 character as minimal root
    root <- substr(name, 1, nchar(name) - 1L)
  }
  paste0("%", root, "%")
}

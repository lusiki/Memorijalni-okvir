#' Tag register indicators
#'
#' Adds binary register columns (religious, tourism, scandal) to a
#' data.table by matching FULL_TEXT against register keyword patterns.
#'
#' @param dt data.table. Must contain a FULL_TEXT column.
#' @param registers data.table. Register definitions with columns:
#'   register, keyword_pattern.
#' @return dt with added columns: reg_religious, reg_tourism, reg_scandal
#'   (integer 0/1).
#' @examples
#' dt <- tag_registers(dt, fread("dictionaries/registers.csv"))
tag_registers <- function(dt, registers) {
  stopifnot(data.table::is.data.table(dt))
  stopifnot("FULL_TEXT" %in% names(dt))

  for (i in seq_len(nrow(registers))) {
    reg_name <- registers$register[i]
    pattern  <- registers$keyword_pattern[i]
    col_name <- paste0("reg_", reg_name)

    data.table::set(
      dt, j = col_name,
      value = as.integer(
        stringi::stri_detect_regex(
          stringi::stri_trans_tolower(dt$FULL_TEXT, locale = "hr"),
          pattern
        )
      )
    )
  }

  dt
}

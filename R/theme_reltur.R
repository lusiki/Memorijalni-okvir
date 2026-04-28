#' Publication ggplot2 theme for religious tourism analysis
#'
#' Minimal, print-friendly theme for all figures in this project.
#' Based on theme_minimal() with adjustments for journal submission.
#'
#' @param base_size Numeric. Base font size. Default 11.
#' @param base_family Character. Font family. Default "".
#' @return A ggplot2 theme object.
#' @examples
#' library(ggplot2)
#' ggplot(mtcars, aes(wt, mpg)) + geom_point() + theme_reltur()
theme_reltur <- function(base_size = 11, base_family = "") {
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(size = base_size * 1.2, face = "bold"),
      plot.subtitle    = ggplot2::element_text(size = base_size * 0.9, color = "grey40"),
      plot.caption     = ggplot2::element_text(size = base_size * 0.7, color = "grey50"),
      axis.title       = ggplot2::element_text(size = base_size * 0.9),
      axis.text        = ggplot2::element_text(size = base_size * 0.8),
      legend.position  = "bottom",
      legend.title     = ggplot2::element_text(size = base_size * 0.85),
      legend.text      = ggplot2::element_text(size = base_size * 0.8),
      panel.grid.minor = ggplot2::element_blank(),
      strip.text       = ggplot2::element_text(face = "bold", size = base_size * 0.9)
    )
}

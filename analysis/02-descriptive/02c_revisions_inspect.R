suppressMessages({
  library(data.table)
})

dt <- readRDS("analysis/02-descriptive/data/destinations_analytical_final.rds")
cat("rows:", nrow(dt), "  cols:", ncol(dt), "\n\n")

cat("=== columns ===\n")
print(sort(names(dt)))

cat("\n=== dominant_frame ===\n")
print(dt[, .N, by = dominant_frame][order(-N)])

cat("\n=== dest_type_cat ===\n")
print(dt[, .N, by = dest_type_cat])

cat("\n=== potential source/portal columns ===\n")
print(grep("source|portal|domain|url|from", names(dt),
           value = TRUE, ignore.case = TRUE))

cat("\n=== register flags ===\n")
print(grep("register|reg_|has_", names(dt), value = TRUE))

cat("\n=== text columns ===\n")
print(grep("text|title|snippet", names(dt),
           value = TRUE, ignore.case = TRUE))

cat("\n=== year-related columns ===\n")
print(grep("year|date|month", names(dt), value = TRUE, ignore.case = TRUE))

library(data.table)
library(digest)

out_meta <- "output/metadata/meta_cleaning_20260420.rds"

dt_orig  <- readRDS("analysis/02-descriptive/data/destinations_analytical_final.rds")
dt_clean <- readRDS("analysis/02-descriptive/data/destinations_analytical_cleaned.rds")
setDT(dt_orig); setDT(dt_clean)

meta <- list(
  phase             = "post-phase-1 corpus cleaning",
  timestamp         = "2026-04-20",
  r_version         = R.version.string,
  script            = "analysis/02-descriptive/clean_corpus.R",
  inputs = list(
    original_corpus   = "analysis/02-descriptive/data/destinations_analytical_final.rds",
    llm_classifications = "validation/llm-audit/llm_results_partial.json",
    sample_definition = "validation/llm_audit_sample.R"
  ),
  outputs = list(
    cleaned_corpus = "analysis/02-descriptive/data/destinations_analytical_cleaned.rds",
    cleaning_log   = "validation/llm-audit/cleaning_log.csv",
    decision_entry = "decisions/log.md (2026-04-20)"
  ),
  input_rows        = nrow(dt_orig),
  output_rows_total = nrow(dt_clean),
  output_rows_kept  = dt_clean[cleaning_action == "keep", .N],
  action_counts     = dt_clean[, .N, by = cleaning_action],
  per_destination_keep = dt_clean[cleaning_action == "keep", .N, by = destination][order(-N)],
  per_destination_substring_drops =
    dt_clean[cleaning_action == "drop_substring", .N, by = destination][order(-N)],
  seed_used         = 2026L,
  sample_size_audited = 350L,
  sample_size_collected = 120L,
  checksums = list(
    cleaned_corpus = digest::digest(file = "analysis/02-descriptive/data/destinations_analytical_cleaned.rds",
                                     algo = "sha256"),
    cleaning_log   = digest::digest(file = "validation/llm-audit/cleaning_log.csv",
                                     algo = "sha256"),
    llm_results    = digest::digest(file = "validation/llm-audit/llm_results_partial.json",
                                     algo = "sha256")
  )
)

saveRDS(meta, out_meta)
cat("Saved:", out_meta, "\n")
print(meta$action_counts)

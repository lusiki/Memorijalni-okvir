# Religious Tourism Media Analysis -- DigiKat Sub-study

This is a computational social science project analysing Croatian digital media coverage of religious tourism destinations. The primary language is R with Quarto documents. The database is DuckDB (read-only, ~25M records from the Determ platform, 2021 to May 2024).

## Rules (always loaded)

Read every file in `.claude/rules/` at the start of each session. These are non-negotiable constraints that apply to all work in this project.

- `.claude/rules/r-style.md` -- R coding conventions (data.table idioms, stringi, naming)
- `.claude/rules/croatian-nlp.md` -- Croatian text handling (diacritics, morphology, encoding)
- `.claude/rules/data-provenance.md` -- Metadata snapshots, file naming, decision gates
- `.claude/rules/manuscript-standards.md` -- Journal formatting, citation, table/figure numbering

## Contexts (loaded on demand)

When starting a work session, load the relevant context file. Each one configures priorities, key files, and definition of done for that work mode.

- `.claude/contexts/retrieval.md` -- Phase 1 work: DB queries, context gates, register tagging
- `.claude/contexts/analysis.md` -- Phases 2-4: descriptive, STM framing, seasonality
- `.claude/contexts/writing.md` -- Phase 5: manuscript drafting and revision
- `.claude/contexts/review.md` -- Quality assurance: validation, audits, inter-coder reliability

To activate a context, say "load the retrieval context" (or analysis, writing, review).

## Skills (invoked for specific tasks)

Project-specific skills live in `.claude/skills/`. These complement the global skills (croatian-academic-style, research-feedback, paper-reviewer) which remain available.

- `run-phase` -- Execute any pipeline phase with config, decision gate, metadata snapshot
- `validate-stm` -- STM diagnostics: coherence, exclusivity, held-out likelihood, K selection
- `build-event-window` -- Construct event study panels from liturgical calendar
- `write-section` -- Draft manuscript sections in Croatian academic style
- `update-metadata` -- Refresh metadata snapshot after any phase run

## Pipeline overview

The pipeline has five phases with hard disk boundaries between them. Each phase reads from disk and writes to disk. No in-memory dependency between phases.

1. **Retrieval** (analysis/01-retrieval/) -- SQL queries against DuckDB, context gates, register tagging. Output to data-raw/.
2. **Descriptive** (analysis/02-descriptive/) -- Aggregation into panels, ranked tables, time series plots. Output to data/ and output/.
3. **Framing** (analysis/03-framing/) -- STM fitting, topic-frame mapping, effect estimation. Output to data/ and output/.
4. **Seasonality** (analysis/04-seasonality/) -- STL decomposition, event study panel FE regression. Output to data/ and output/.
5. **Synthesis** (analysis/05-synthesis/) -- Cross-phase integration feeding into manuscript/.

## Key directories

- `R/` -- Reusable function definitions (imported by phase scripts via source())
- `dictionaries/` -- Shared terminology assets (destinations, registers, liturgical events)
- `validation/` -- Human review artefacts (coding sheets, gate audits, sentiment validation)
- `manuscript/` -- Self-contained Quarto manuscript (compiles independently)
- `output/` -- Machine-generated tables, figures, reports, metadata snapshots
- `ref/` -- Reference implementations (HNB scripts) and research design
- `decisions/` -- Append-only decision log for methodological choices
- `templates/` -- Reusable templates (phase script skeleton)

## Machine-specific configuration

Machine-specific paths (DuckDB location, Python environment) belong in `CLAUDE.local.md` which is git-ignored. Read it if present.

## Coding conventions

Read `ref/` for the HNB reference implementation that establishes conventions. Phase scripts are Quarto QMD with sections numbered 0-11 (Configuration, Pattern architecture, Connect, Query builder, Retrieve, Tag, Aggregate, Quality profile, Decision gate, Disconnect, Save, Metadata). Config is a single R list saved as .rds. Long format preferred. data.table over dplyr. stringi over base R for text. Explicit seed before every stochastic call.

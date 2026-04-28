# Decision Log

Append-only record of methodological choices. Each entry records what was decided, why, and what alternatives were considered. Do not edit or delete previous entries.

## Template

### YYYY-MM-DD | Phase N | Short title
**Decision:** What was decided.
**Rationale:** Why this choice was made over alternatives.
**Alternatives considered:** What else was on the table.
**Implications:** What downstream effects this has.

---

<!-- Entries below this line -->

### 2026-04-20 | Post-Phase 1 | LLM-assisted corpus audit and cleaning

**Decision:** Add an annotative corpus-cleaning layer after Phase 1, driven by a Croatian-language LLM audit of a 350-article stratified random sample. The cleaning flags (but does not delete) rows that fail any of three checks: (a) word-boundary destination re-match on FULL_TEXT, (b) tightened religious/tourism/scandal register regex with negative-context handling, (c) hand-curated blocklist of LLM-confirmed false positives. Produces `destinations_analytical_cleaned.rds` with new columns `wb_destination_ok`, `clean_religious`, `clean_tourism`, `clean_scandal`, `clean_dominant_frame`, `cleaning_action`, `cleaning_reason`. Downstream Phase 2–4 analyses should use the cleaned subset (`cleaning_action == "keep"`) as the primary corpus, with the unfiltered corpus retained for robustness checks.

**Rationale:** Manual inspection of audit columns (added 2026-04-20 via `analysis/02-descriptive/audit_matches.R`) revealed a satirical column about Putin entering the Nin corpus because the three-letter substring `nin` matched inside *Putinera* and *kontaminiran*. A stratified LLM audit (350 rows, Claude Sonnet, Croatian prompt in `validation/llm-audit/PROMPT_HR.md`) confirmed the Nin substring problem is systemic (≈80–90% false-positive rate on the 20-row Nin-substring-suspect oversample) and surfaced two additional patterns: (1) dictionary noise — tourism-register stems `ljetn`, `posjet`, `dolazak`, `izlet` and religious-register stems `krist`, `čudo`, `advent`, `uskrs`, `kapel` firing in non-topical senses (anniversaries, personal names, field trips, calendar timing, place names); (2) topicality ambiguity — articles where the destination is legitimately mentioned but the article operates in a non-religious-tourism discourse (basketball "Alkar" club, civic commemorations, obituaries published on shrine portals, Thompson concert venue). After cleaning, Nin loses 33% of its corpus and Krasno loses 34% to substring failures alone; the full cleaning drops 4,894 of 18,815 rows (26%), with the biggest cut (4,094 rows) from the tightened register requirement. The cleaned corpus keeps 13,921 rows.

**Alternatives considered:** (1) Rerun Phase 1 retrieval with tightened SQL patterns — rejected as too expensive and would require re-pulling from DuckDB; the annotative approach achieves the same precision gain without touching raw data. (2) Destructive drop of failed rows — rejected; annotative preserves the original for transparency and lets reviewers verify. (3) LLM-classify all 18,815 articles — rejected; flips methodology from "transparent, rule-based, auditable" to "LLM-classified", which is a different paper with different epistemological commitments and harder to defend in Medijske studije. (4) Skip cleaning entirely — rejected; the Nin/Krasno substring problem is severe enough that a reviewer would find it on spot-checking.

**Implications:** The typology and frame-distribution results must be re-run on the cleaned corpus and the changes reported as a robustness check. Expected directions: Nin's tourism-only share may drop (many FPs were sports/music articles that fired on noise tourism words); the religious-dominant destinations (Vepric, Ludbreg) are near-unaffected. The Rasprava must include a methodological limitations paragraph naming the substring issue, the register noise, and the topicality ambiguity, with the cleaning rates per destination in a supplementary table. The LLM audit itself should be cited as a validity check with three-way reliability (dictionary / LLM / human) ideally reported once the remaining ~230 rows of the 350-row audit are collected.

---


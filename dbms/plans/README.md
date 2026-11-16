# CP4 evidence index

`measured-run/` contains a successful real execution, not illustrative plans:

- `metadata.json`: engine/environment, row counts, PRAGMAs, input hashes, bindings and result-equality digests.
- `timings.csv`: all 240 recorded samples (4 queries × 2 stages × 30 repetitions).
- `summary.json`: min/median/nearest-rank p95 and fetched row counts.
- `q01-before.txt` through `q12-after.txt`: original SQL, bindings, actual EXPLAIN QUERY PLAN and full EXPLAIN bytecode for Q01/Q02/Q06/Q12.
- `experimental-indexes.sql`: the five index definitions absent in baseline and present afterward.

See [CP4 methodology](../05_query_timings.md). Run `python3 scripts/benchmark.py --output-dir work/benchmark-rerun-1` from the repository root to capture a fresh run without replacing committed evidence. The temporary benchmark DB is not committed.

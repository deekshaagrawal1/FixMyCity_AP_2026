# CP4 — Real query plans and measured timings

## Execution status and dataset

**Database execution succeeded. The values below are real local measurements, not example output.**

Captured at `2026-11-16T15:45:24.797669+00:00` using Python `3.14.2` and its linked SQLite `3.50.4` on `Darwin 25.6.0 / arm64`. The SQLite CLI can be a different version; the Python SQLite version is the measured engine. Exact environment, compile options, PRAGMAs, input hashes and bindings are in [metadata.json](plans/measured-run/metadata.json).

The isolated temporary, file-backed database contained **30,008 complaints and 30,004 notifications**: 30,000 deterministic synthetic rows of each type, plus the 8-complaint/4-notification fixture. It adds 1,000 fictional citizens and 40 officers. No real website data is used. Synthetic complaint statuses cycle across six values; creation times are minute offsets modulo 21,600 from 1 November 2026. All synthetic cases use the roads category/department. This distribution is deliberately simple, with correlated assignment/status patterns; it is not a production workload.

## Measurement method

1. Create a fresh temporary SQLite database; load CP2, the fixture seed, then deterministic synthetic data. Enable foreign keys and verify integrity.
2. Save the DDL of five experimental indexes. In the **before** stage, drop only those indexes; all other CP2 indexes, keys and triggers remain. This is not a no-index database.
3. Run ANALYZE. For Q01/Q02/Q06/Q12 capture `EXPLAIN QUERY PLAN` and full `EXPLAIN` with the same SQL and bindings used for measurement.
4. Run 5 unrecorded warmups per query/stage, then 30 measured execute-plus-fetchall repetitions. Use `time.perf_counter_ns`; report elapsed milliseconds. Exclude connection setup, fixture loading, ANALYZE, EXPLAIN, serialization and digest calculation.
5. Recreate all five indexes, run ANALYZE, repeat the same procedure on the same database and connection. Verify exact ordered row counts and SHA-256 result digests match before/after. Verify integrity and foreign keys again.
6. Write evidence only after all executions and assertions succeed. The temporary database is removed. The benchmark accepts no external database path and refuses to overwrite an existing evidence directory.

The cutoff is fixed at 16 November 2026, 12:00 UTC. Q01/Q12 bind `bench-citizen-000`; Q02 binds `bench-officer-001`; pagination is LIMIT 50, OFFSET 0. Q06 uses the fixed cutoff. Full bindings are recorded in every plan file.

## Observations

All values are milliseconds; p95 uses the nearest-rank 95th percentile of 30 samples. Very small differences, particularly inbox reads, should not be interpreted as durable gains.

| Query | Rows fetched | Before median | After median | Before p95 | After p95 | Median ratio before/after |
|---|---:|---:|---:|---:|---:|---:|
| Q01 | 30 | 1.458541 | 0.030667 | 1.526583 | 0.031708 | 47.56× |
| Q02 | 50 | 0.524375 | 0.042167 | 0.541125 | 0.046625 | 12.44× |
| Q06 | 50 | 0.072938 | 0.057709 | 0.074875 | 0.066917 | 1.26× |
| Q12 | 10 | 0.014979 | 0.012583 | 0.015834 | 0.013209 | 1.19× |

The ratios describe only this experiment. They are not a promise of production latency. Ordered query-result equality, `integrity_check = ok`, and zero foreign-key violations were verified; hashes are recorded in metadata.

## What the plans show

### Q01

Before — [full plan and bytecode](plans/measured-run/q01-before.txt):

```text
(7, 0, 164, 'SCAN Complaint')
(27, 0, 0, 'USE TEMP B-TREE FOR ORDER BY')
```

After — [full plan and bytecode](plans/measured-run/q01-after.txt):

```text
(8, 0, 74, 'SEARCH Complaint USING INDEX Complaint_citizen_created_idx (citizenId=?)')
```

### Q02

Before — [full plan and bytecode](plans/measured-run/q02-before.txt):

```text
(8, 0, 116, 'SEARCH Complaint USING INDEX Complaint_officerId_idx (officerId=?)')
(37, 0, 0, 'USE TEMP B-TREE FOR ORDER BY')
```

After — [full plan and bytecode](plans/measured-run/q02-after.txt):

```text
(8, 0, 112, 'SEARCH Complaint USING INDEX Complaint_officer_active_created_idx (officerId=?)')
```

### Q06

Before — [full plan and bytecode](plans/measured-run/q06-before.txt):

```text
(8, 0, 150, 'SEARCH Complaint USING INDEX Complaint_dueAt_idx (dueAt<?)')
(49, 0, 0, 'USE TEMP B-TREE FOR LAST TERM OF ORDER BY')
```

After — [full plan and bytecode](plans/measured-run/q06-after.txt):

```text
(8, 0, 145, 'SEARCH Complaint USING INDEX Complaint_active_due_idx (dueAt<?)')
```

### Q12

Before — [full plan and bytecode](plans/measured-run/q12-before.txt):

```text
(8, 0, 75, 'SEARCH Notification USING INDEX Notification_userId_createdAt_idx (userId=?)')
```

After — [full plan and bytecode](plans/measured-run/q12-after.txt):

```text
(8, 0, 61, 'SEARCH Notification USING INDEX Notification_unread_idx (userId=?)')
```

`SEARCH` indicates an index-constrained lookup; `SCAN` traverses a table/index; `USE TEMP B-TREE` identifies temporary sorting. Q01's citizen/time index avoids reading the whole complaint table and sorting matches. Q02's active-officer/time partial index selects active assignments in output order. Q06 can use an active-case deadline index instead of filtering all deadline-index entries. Q12's unread-recipient index narrows an already indexed inbox path. See the actual plan details above rather than assuming the optimizer must always choose an index. Index changes are saved in [experimental-indexes.sql](plans/measured-run/experimental-indexes.sql).

SQLite's plan output is diagnostic and can change between releases. [The official EXPLAIN QUERY PLAN reference](https://sqlite.org/eqp.html) explains its meaning and cautions against depending on a fixed output format. Full EXPLAIN is virtual-machine bytecode; neither EXPLAIN form measures actual run time. The timings come from executing and fetching the SELECTs separately.

## Reproduce

From this repository root:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/benchmark.py --rows 30000 --repeats 30 --warmups 5 --output-dir work/benchmark-rerun-1
```

Choose a new output directory for every run. Review the new `metadata.json`, `timings.csv`, `summary.json`, before/after plan files, and index DDL. Each query's original SQL comes from `dbms/04_queries.sql`; do not silently benchmark a differently rewritten query. The committed evidence is preserved even if your SQLite version chooses another plan.

For manual plans on a **new** seeded demo database:

```bash
python3 scripts/create_demo.py --database work/manual-plans.sqlite
sqlite3 -readonly work/manual-plans.sqlite "EXPLAIN QUERY PLAN SELECT id,title,status,priority,departmentId,officerId,createdAt,dueAt FROM Complaint WHERE citizenId='citizen-1' ORDER BY createdAt DESC,id LIMIT 50 OFFSET 0;"
sqlite3 -readonly work/manual-plans.sqlite "EXPLAIN SELECT id,title,status,priority,departmentId,officerId,createdAt,dueAt FROM Complaint WHERE citizenId='citizen-1' ORDER BY createdAt DESC,id LIMIT 50 OFFSET 0;"
```

This tiny fixture is for verifying SQL, not for reproducing the larger dataset's latency. A rerun only counts as measured evidence if the process exits successfully and writes its own files. If Python/SQLite execution fails, report the error and leave timings unmeasured; do not copy the committed figures into a claim about your machine.

## Limits and interpretation

These are warm-cache, single-process, single-connection local reads. Baseline always precedes indexed measurements; warmups reduce initial cache bias but do not eliminate experiment-order effects. There is no concurrent traffic, network, HTTP, Prisma overhead, authorization or uploaded-media I/O. Read result fetching is included; writes, index-build cost, storage overhead, large offsets, full-table analytics, cold disk behavior and production distributions are not benchmarked. Integer millisecond parameters avoid mixed-format date comparison. Synthetic data has no realistic text diversity or complete event timelines. A 0.01 ms inbox measurement is near enough to runtime noise that small ratios deserve little weight. Use multiple fresh runs and representative workload data before choosing production indexes.

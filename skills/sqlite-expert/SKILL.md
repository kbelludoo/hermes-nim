---
name: SQLite & Database Optimizer
description: Query optimization, index analysis, WAL mode configuration, and migration management.
---

# SQLite & Database Optimizer Skill

When working with SQLite databases:
1. Ensure WAL mode is enabled for concurrency: `PRAGMA journal_mode = WAL;`.
2. Set busy timeout to prevent locking errors: `PRAGMA busy_timeout = 5000;`.
3. Use `EXPLAIN QUERY PLAN` to verify that queries use indices rather than full table scans.
4. Execute mutations inside explicit transactions (`BEGIN TRANSACTION ... COMMIT`).

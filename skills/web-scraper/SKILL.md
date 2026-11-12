---
name: Web Scraping & Data Extractor
description: Extracts structured tables, JSON, and clean markdown from websites using the lean Rust Browser engine.
---

# Web Scraping & Data Extractor Skill

When extracting web data:
1. Prefer fast, lightweight fetching (`fetch_url` or `browser_snapshot`).
2. Strip ads, cookies, tracking scripts, and unnecessary styles.
3. Format tabular web data into clean Markdown tables or JSON arrays.
4. Respect robots.txt and apply modest rate-limits on continuous crawls.

# Changelog

## 0.1.0 (unreleased)

Initial release, extracted from Korrelate's `Korrelate::Dates`.

- Public API: `parse`, `parse_range`, `parse_datetime`, `parseable?`. Everything else is private.
- `parse_range` accepts Chronic options (`context:`, `now:`), as `parse` already did.

Fixes from the Korrelate version:

- Day words in ranges ("yesterday", "fri") were rewritten as ISO dates whose dashes then read as a range separator, so "yesterday" meant yesterday through today.
- "next fri" / "last mon" never matched as a phrase (a space inside an `/x` regex was ignored) and resolved to a span from today.
- One-sided ISO ranges ("since 2026-01-01", "after 2026-01-15") returned nil: the ISO rewrite consumed the space after the keyword.
- Weekday spans resolved each side from today ("tue thru thu" on a Wednesday became Thu–Tue); the right side now counts from the left.
- Month and year endpoints ("jan to mar", "2025-2026") used Chronic's mid-period guess; they now cover whole periods.
- "day", "next day" and "last day" ended in a time instead of a Date.
- `parse` read bare numbers ("5", "1999") as today and "10:15" as October 15; both now return nil.
- Words like "today" resolved in system time while ranges used `Time.zone`; Chronic is now anchored to `Time.zone`.
- `..` is accepted as a range separator.

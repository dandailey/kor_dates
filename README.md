# KorDates

Natural-language dates and date ranges for search boxes and filters.

KorDates turns what people type into date filters ("last month", "mtd", "since jan", "mon-fri", "past 2 weeks", "1/2/99") into `Date`s and `[from, to]` ranges. It wraps [Chronic](https://github.com/mojombo/chronic) with the range grammar Chronic lacks, and anchors everything to `Time.zone`.

```ruby
KorDates.parse("next fri")            # => Fri, 13 Nov 2026
KorDates.parse_range("last month")    # => [Thu, 01 Oct 2026, Sat, 31 Oct 2026]
KorDates.parse_range("since jan")     # => [Thu, 01 Jan 2026, Wed, 11 Nov 2026]
KorDates.parse_range("until fri")     # => [nil, Fri, 13 Nov 2026]
KorDates.parse_datetime("tomorrow at noon")
KorDates.parseable?("today")          # => true
```

Examples in this README assume today is Wednesday, November 11, 2026.

## Installation

```ruby
gem "kor_dates", github: "dandailey/kor_dates"
```

Requires Ruby 3.1+, ActiveSupport 7.0+ and Chronic 0.10.

## API

KorDates has four methods. None of them raise on bad input; anything unparseable returns `nil`.

| Method | Returns |
|---|---|
| `KorDates.parse(input, options = {})` | a `Date`, or `nil` |
| `KorDates.parse_range(input, options = {})` | `[from, to]` (either end may be `nil` for open-ended input), or `nil` |
| `KorDates.parse_datetime(input, options = {})` | a time in `Time.zone` (a `Time` when no zone is set), or `nil` |
| `KorDates.parseable?(input)` | `true` when the input reads as a single date |

`parse_range` always returns a pair: a single date comes back as `[date, date]`, and pairs are sorted so `from <= to`. `Date` and `Time` inputs pass straight through `parse` and `parse_datetime`.

## Phrase reference

Every phrase below is covered by the test suite.

### Single days

| Input | Result |
|---|---|
| `today`, `yesterday`, `tomorrow` | that day |
| `fri`, `next fri`, `last mon`, `next tuesday` | that weekday |
| `5th` | the 5th of this month |
| `3 days ago` | three days back |
| `2026-01-15`, `1/15/2026`, `1.15.2026`, `15/01/2026` | Jan 15, 2026 |
| `1/2/99`, `1/2/00`, `1/2/26` | 1999, 2000, 2026 |
| `jan 5 2026` | Jan 5, 2026 |
| `jan 5`, `1/2` | the next one (see [Ambiguous dates](#ambiguous-dates)) |
| `11/10` | Nov 10 this year (a date in the recent past stays in the past) |

### Periods

| Input | Range |
|---|---|
| `this month`, `mo` | Nov 1 – Nov 30, 2026 |
| `last month`, `past month` | Oct 1 – Oct 31 |
| `wk`, `last week`, `next wk` | Monday – Sunday of that week |
| `qtr`, `last quarter` | Oct 1 – Dec 31 / Jul 1 – Sep 30 |
| `yr`, `this year`, `last year` | the calendar year |
| `day`, `next day`, `last day` | that single day |
| `jan`, `jan 2026`, `january '99` | the whole month |
| `next jan`, `last jan` | January 2027 / January 2025 |
| `1999`, `'25` | the whole year |

### Spans from today

| Input | Range |
|---|---|
| `7 days`, `2wk`, `next 2 qtrs` | today forward |
| `-3 days`, `last 3 days`, `past 2 weeks` | back to today |
| `mtd`, `wtd`, `qtd`, `ytd`, `quarter to date` | start of the period – today |
| `recent` | the last 90 days |
| `current` | a week either side of today |

### Open-ended

| Input | Range |
|---|---|
| `since jan`, `since yesterday`, `since 2026-01-01` | that date – today |
| `since first of month` | Nov 1 – today |
| `through end of month` | today – Nov 30 |
| `after fri`, `after 2026-01-15` | the day after – open |
| `from 2/1`, `from 2026-02-01` | that date – open |
| `before 1/15`, `before 2026-03-01` | open – the day before |
| `until fri`, `until 2026-03-01` | open – that date |
| `past`, `future` | open – today / today – open |

### Explicit ranges

Separate two dates with `to`, `thru`, `through`, `and`, `-` or `..`.

| Input | Range |
|---|---|
| `2026-01-01 to 2026-01-31`, `2026-01-01..2026-01-31`, `2026-01-01 - 2026-01-31` | Jan 1 – Jan 31 |
| `1/2 to 3/4` | Jan 2 – Mar 4 |
| `today to fri`, `yesterday and today` | as written |
| `mon-fri`, `tue thru thu` | one week: the right side counts from the left |
| `5th thru 9th`, `march 3-10` | days within one month |
| `jan to mar`, `jan-mar`, `jan 2025 to mar 2026` | first of the first month – last of the last |
| `2025-2026` | Jan 1, 2025 – Dec 31, 2026 |

### Not dates

Bare numbers (`5`, `1999` in `parse`), bare times (`10:15`, `3pm`, `noon`) and other text return `nil` from `parse`. A bare four-digit number is a year in `parse_range`.

## Options

`parse`, `parse_range` and `parse_datetime` accept Chronic's options. Two are useful:

| Option | Effect |
|---|---|
| `context: :past` | ambiguous dates resolve backward: `parse("jan 5", context: :past)` is Jan 5, 2026 |
| `now:` | the reference point, as a `Date` or a time: `parse_range("this month", now: Date.new(2025, 2, 10))` is February 2025 |

Phrases with a direction of their own keep it: `since` always looks back and `through` always looks forward.

## Ambiguous dates

Without a year, Chronic resolves dates forward, which suits due dates and scheduling: on November 11, `jan 5` means January 5, 2027. There's one exception. A numeric month/day that would land almost a year ahead is taken as the recent past instead, so `11/10` typed on November 11 means yesterday, not next year.

For searching records that already exist, pass `context: :past`, or include the year.

Numeric dates are read month first (`1/2` is January 2). Day-first input is understood only when it can't be a month (`15/01/2026`).

## Time zones

Everything follows `Time.zone` when it's set, as in any Rails app; otherwise the system clock.

- `today`, `tomorrow`, weekdays and every range are computed from `Time.zone`'s current date, even when the server's system clock is on a different day.
- `parse_datetime` returns a time in `Time.zone`. ISO strings with an offset (`2026-09-01T10:15:00-07:00`) keep their instant; strings without one are read as local time in the zone. A date with no time of day means midnight.

## Development

```sh
bundle install
bundle exec rake test
```

The suite freezes time at Wednesday, November 11, 2026, so results don't depend on the day it runs.

## Origins

KorDates was extracted from Korrelate, where it powers date filters in search.

## License

Released under the [MIT License](LICENSE).

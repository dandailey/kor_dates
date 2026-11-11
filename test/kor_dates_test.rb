# frozen_string_literal: true

require "minitest/autorun"
require "active_support/testing/time_helpers"
require "kor_dates"

# Every test runs at Wednesday 2026-11-11 12:00 UTC unless it says otherwise.
class KorDatesTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def setup
    @saved_zone = Time.zone
    Time.zone = "UTC"
    travel_to Time.utc(2026, 11, 11, 12)
  end

  def teardown
    travel_back
    Time.zone = @saved_zone
  end

  def d(year, month, day) = Date.new(year, month, day)

  # ─── parse ────────────────────────────────────────────────────────────────

  def test_parse_numeric_dates
    assert_equal d(2026, 1, 15), KorDates.parse("2026-01-15")
    assert_equal d(2026, 1, 5), KorDates.parse("2026-1-5")
    assert_equal d(2026, 1, 2), KorDates.parse("1/2/2026")
    assert_equal d(2026, 1, 2), KorDates.parse("1.2.2026")
    assert_equal d(2026, 1, 15), KorDates.parse("15/01/2026")
  end

  def test_parse_two_digit_years
    assert_equal d(1999, 1, 2), KorDates.parse("1/2/99")
    assert_equal d(2000, 1, 2), KorDates.parse("1/2/00")
    assert_equal d(2026, 1, 2), KorDates.parse("1/2/26")
  end

  def test_parse_month_day_without_a_year
    # Recent past stays in this year; anything else resolves forward.
    assert_equal d(2026, 11, 10), KorDates.parse("11/10")
    assert_equal d(2027, 1, 2), KorDates.parse("1/2")
    assert_equal d(2026, 12, 25), KorDates.parse("12/25")
  end

  def test_parse_words
    assert_equal d(2026, 11, 11), KorDates.parse("today")
    assert_equal d(2026, 11, 10), KorDates.parse("yesterday")
    assert_equal d(2026, 11, 12), KorDates.parse("tomorrow")
    assert_equal d(2026, 11, 17), KorDates.parse("next tuesday")
    assert_equal d(2026, 11, 8), KorDates.parse("3 days ago")
    assert_equal d(2026, 11, 5), KorDates.parse("5th")
    assert_equal d(2026, 1, 5), KorDates.parse("jan 5 2026")
  end

  def test_parse_context_option
    assert_equal d(2027, 1, 5), KorDates.parse("jan 5")
    assert_equal d(2026, 1, 5), KorDates.parse("jan 5", context: :past)
  end

  def test_parse_now_option
    assert_equal d(2025, 3, 2), KorDates.parse("tomorrow", now: Time.utc(2025, 3, 1, 12))
    assert_equal d(2025, 3, 2), KorDates.parse("tomorrow", now: d(2025, 3, 1))
  end

  # Regression: bare numbers parsed as today ("5" became 2026-11-11).
  def test_parse_rejects_bare_numbers
    assert_nil KorDates.parse("5")
    assert_nil KorDates.parse("123")
    assert_nil KorDates.parse("1999")
  end

  # Regression: "10:15" was read as month 10, day 15.
  def test_parse_rejects_bare_times
    assert_nil KorDates.parse("10:15")
    assert_nil KorDates.parse("3pm")
    assert_nil KorDates.parse("noon")
  end

  def test_parse_non_strings_and_blanks
    assert_equal d(2026, 1, 2), KorDates.parse(d(2026, 1, 2))
    assert_equal d(2026, 1, 2), KorDates.parse(Time.utc(2026, 1, 2, 23))
    assert_nil KorDates.parse(nil)
    assert_nil KorDates.parse("")
    assert_nil KorDates.parse("   ")
    assert_nil KorDates.parse("garbage")
  end

  # ─── parseable? ───────────────────────────────────────────────────────────

  def test_parseable
    assert KorDates.parseable?("today")
    assert KorDates.parseable?("next fri")
    assert KorDates.parseable?("2026-01-15")
    assert KorDates.parseable?("5th")
    refute KorDates.parseable?("1999")
    refute KorDates.parseable?("1.5")
    refute KorDates.parseable?("foo")
  end

  # ─── parse_datetime ───────────────────────────────────────────────────────

  def test_parse_datetime_keeps_local_time_in_the_zone
    Time.use_zone("America/Los_Angeles") do
      parsed = KorDates.parse_datetime("2026-09-01T10:15")

      assert_equal Time.zone.local(2026, 9, 1, 10, 15), parsed
      assert_equal "PDT", parsed.zone
    end
  end

  def test_parse_datetime_respects_offsets
    assert_equal Time.utc(2026, 9, 1, 17, 15), KorDates.parse_datetime("2026-09-01T10:15:00-07:00")
  end

  def test_parse_datetime_natural_language
    Time.use_zone("America/Los_Angeles") do
      assert_equal Time.zone.local(2026, 9, 1, 10, 15), KorDates.parse_datetime("September 1 2026 at 10:15am")
      assert_equal Time.zone.local(2026, 9, 4), KorDates.parse_datetime("September 4 2026")
      assert_equal Time.zone.local(2026, 11, 12, 12), KorDates.parse_datetime("tomorrow at noon")
    end
  end

  def test_parse_datetime_garbage
    assert_nil KorDates.parse_datetime("garbage")
    assert_nil KorDates.parse_datetime(nil)
  end

  # ─── parse_range: periods ─────────────────────────────────────────────────

  def test_years
    assert_range "1999", d(1999, 1, 1), d(1999, 12, 31)
    assert_range "'25", d(2025, 1, 1), d(2025, 12, 31)
    assert_range "this year", d(2026, 1, 1), d(2026, 12, 31)
    assert_range "last year", d(2025, 1, 1), d(2025, 12, 31)
  end

  def test_months
    assert_range "jan", d(2026, 1, 1), d(2026, 1, 31)
    assert_range "january '99", d(1999, 1, 1), d(1999, 1, 31)
    assert_range "jan 2026", d(2026, 1, 1), d(2026, 1, 31)
    assert_range "next jan", d(2027, 1, 1), d(2027, 1, 31)
    assert_range "last jan", d(2025, 1, 1), d(2025, 1, 31)
    assert_range "this month", d(2026, 11, 1), d(2026, 11, 30)
    assert_range "past month", d(2026, 10, 1), d(2026, 10, 31)
    assert_range "last month", d(2026, 10, 1), d(2026, 10, 31)
  end

  def test_units
    assert_range "wk", d(2026, 11, 9), d(2026, 11, 15)
    assert_range "next wk", d(2026, 11, 16), d(2026, 11, 22)
    assert_range "last week", d(2026, 11, 2), d(2026, 11, 8)
    assert_range "mo", d(2026, 11, 1), d(2026, 11, 30)
    assert_range "qtr", d(2026, 10, 1), d(2026, 12, 31)
    assert_range "last quarter", d(2026, 7, 1), d(2026, 9, 30)
    assert_range "yr", d(2026, 1, 1), d(2026, 12, 31)
  end

  # Regression: "day" ranges ended in a TimeWithZone instead of a Date.
  def test_day_units_return_dates
    assert_range "day", d(2026, 11, 11), d(2026, 11, 11)
    assert_range "next day", d(2026, 11, 12), d(2026, 11, 12)
    assert_range "last day", d(2026, 11, 10), d(2026, 11, 10)
    assert(KorDates.parse_range("day").all? { |value| value.instance_of?(Date) })
  end

  def test_spans
    assert_range "7 days", d(2026, 11, 11), d(2026, 11, 18)
    assert_range "-3 days", d(2026, 11, 8), d(2026, 11, 11)
    assert_range "2wk", d(2026, 11, 11), d(2026, 11, 25)
    assert_range "past 2 weeks", d(2026, 10, 28), d(2026, 11, 11)
    assert_range "last 3 days", d(2026, 11, 8), d(2026, 11, 11)
    assert_range "next 2 qtrs", d(2026, 11, 11), d(2027, 5, 11)
  end

  def test_period_to_date
    assert_range "mtd", d(2026, 11, 1), d(2026, 11, 11)
    assert_range "wtd", d(2026, 11, 9), d(2026, 11, 11)
    assert_range "qtd", d(2026, 10, 1), d(2026, 11, 11)
    assert_range "ytd", d(2026, 1, 1), d(2026, 11, 11)
    assert_range "quarter to date", d(2026, 10, 1), d(2026, 11, 11)
  end

  def test_named_ranges
    assert_range "past", nil, d(2026, 11, 11)
    assert_range "future", d(2026, 11, 11), nil
    assert_range "recent", d(2026, 8, 13), d(2026, 11, 11)
    assert_range "current", d(2026, 11, 4), d(2026, 11, 18)
  end

  # ─── parse_range: one-sided ───────────────────────────────────────────────

  def test_one_sided
    assert_range "after fri", d(2026, 11, 14), nil
    assert_range "before 1/15", nil, d(2027, 1, 14)
    assert_range "from 2/1", d(2027, 2, 1), nil
    assert_range "until fri", nil, d(2026, 11, 13)
    assert_range "since jan", d(2026, 1, 1), d(2026, 11, 11)
    assert_range "since yesterday", d(2026, 11, 10), d(2026, 11, 11)
    assert_range "since first of month", d(2026, 11, 1), d(2026, 11, 11)
    assert_range "through end of month", d(2026, 11, 11), d(2026, 11, 30)
  end

  # Regression: the ISO rewrite swallowed the space after "since", so every
  # one-sided ISO range returned nil.
  def test_one_sided_iso
    assert_range "since 2026-01-01", d(2026, 1, 1), d(2026, 11, 11)
    assert_range "after 2026-01-15", d(2026, 1, 16), nil
    assert_range "from 2026-02-01", d(2026, 2, 1), nil
    assert_range "until 2026-03-01", nil, d(2026, 3, 1)
    assert_range "before 2026-03-01", nil, d(2026, 2, 28)
  end

  # ─── parse_range: single days ─────────────────────────────────────────────

  # Regression: day words were rewritten as ISO dates whose dashes then read
  # as a range separator ("yesterday" became yesterday..today).
  def test_day_words_are_single_days
    assert_range "today", d(2026, 11, 11), d(2026, 11, 11)
    assert_range "yesterday", d(2026, 11, 10), d(2026, 11, 10)
    assert_range "tomorrow", d(2026, 11, 12), d(2026, 11, 12)
    assert_range "fri", d(2026, 11, 13), d(2026, 11, 13)
    assert_range "2019-10-14", d(2019, 10, 14), d(2019, 10, 14)
    assert_range "jan 1", d(2027, 1, 1), d(2027, 1, 1)
  end

  # Regression: the /x replacement pattern ignored the space in "next +", so
  # relative weekdays never matched as a unit.
  def test_relative_weekdays_are_single_days
    assert_range "next fri", d(2026, 11, 13), d(2026, 11, 13)
    assert_range "last mon", d(2026, 11, 9), d(2026, 11, 9)
    assert_range "after next fri", d(2026, 11, 14), nil
  end

  # ─── parse_range: explicit ranges ─────────────────────────────────────────

  def test_explicit_ranges
    assert_range "1/2 to 3/4", d(2027, 1, 2), d(2027, 3, 4)
    assert_range "2026-01-01 to 2026-01-31", d(2026, 1, 1), d(2026, 1, 31)
    assert_range "2026-01-01 - 2026-01-31", d(2026, 1, 1), d(2026, 1, 31)
    assert_range "2026-01-01..2026-01-31", d(2026, 1, 1), d(2026, 1, 31)
    assert_range "yesterday and today", d(2026, 11, 10), d(2026, 11, 11)
    assert_range "today to fri", d(2026, 11, 11), d(2026, 11, 13)
    assert_range "5th thru 9th", d(2026, 11, 5), d(2026, 11, 9)
    assert_range "march 3-10", d(2027, 3, 3), d(2027, 3, 10)
  end

  # Regression: weekday sides resolved independently of each other, so
  # "tue thru thu" on a Wednesday became Thu 12..Tue 17.
  def test_weekday_spans
    assert_range "mon-fri", d(2026, 11, 16), d(2026, 11, 20)
    assert_range "mon - fri", d(2026, 11, 16), d(2026, 11, 20)
    assert_range "tue thru thu", d(2026, 11, 17), d(2026, 11, 19)
  end

  # Regression: month and year endpoints resolved to Chronic's mid-month
  # guess ("jan to mar" was Jan 16..Mar 16; "2025-2026" collapsed to today).
  def test_period_endpoints
    assert_range "jan to mar", d(2026, 1, 1), d(2026, 3, 31)
    assert_range "jan-mar", d(2026, 1, 1), d(2026, 3, 31)
    assert_range "jan 2025 to mar 2026", d(2025, 1, 1), d(2026, 3, 31)
    assert_range "2025-2026", d(2025, 1, 1), d(2026, 12, 31)
  end

  def test_unparseable
    assert_nil KorDates.parse_range("foo")
    assert_nil KorDates.parse_range("")
    assert_nil KorDates.parse_range(nil)
    assert_nil KorDates.parse_range("1/2/2026 to")
  end

  def test_range_context_and_now_options
    assert_range "jan 5", d(2026, 1, 5), d(2026, 1, 5), context: :past
    assert_range "this month", d(2025, 2, 1), d(2025, 2, 28), now: d(2025, 2, 10)
  end

  # ─── time zones ───────────────────────────────────────────────────────────

  # Regression: Chronic resolved "today" in system time while ranges used
  # Date.current, so the two disagreed whenever Time.zone was a different day.
  def test_words_follow_time_zone_not_system_time
    saved_tz = ENV["TZ"]
    ENV["TZ"] = "America/Los_Angeles" # system: Wed Nov 11, 04:00

    Time.use_zone("Pacific/Kiritimati") do # zone: Thu Nov 12, 02:00
      assert_equal d(2026, 11, 12), Date.current
      assert_equal d(2026, 11, 12), KorDates.parse("today")
      assert_range "today", d(2026, 11, 12), d(2026, 11, 12)
      assert_range "tomorrow", d(2026, 11, 13), d(2026, 11, 13)
      assert_equal Time.zone.local(2026, 11, 13, 12), KorDates.parse_datetime("tomorrow at noon")
    end
  ensure
    ENV["TZ"] = saved_tz
  end

  # ─── API surface ──────────────────────────────────────────────────────────

  def test_only_four_public_methods
    public_api = KorDates.singleton_methods(false).sort

    assert_equal %i[parse parse_datetime parse_range parseable?], public_api
  end

  private

  def assert_range(input, from, to, **options)
    assert_equal [from, to], KorDates.parse_range(input, options), input
  end
end

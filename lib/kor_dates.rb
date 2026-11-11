# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"
require "chronic"
require "time"

require_relative "kor_dates/version"

# Natural-language date parsing for search boxes and filters.
#
#   KorDates.parse("next fri")              # => Fri, 13 Nov 2026
#   KorDates.parse_range("last month")      # => [Thu, 01 Oct 2026, Sat, 31 Oct 2026]
#   KorDates.parse_range("since jan")       # => [Thu, 01 Jan 2026, Wed, 11 Nov 2026]
#   KorDates.parse_datetime("tomorrow at noon")
#   KorDates.parseable?("today")            # => true
#
# Nothing here raises on bad input: unparseable input returns nil.
module KorDates
  WEEKDAY_PATTERN = "su(n|nday)?|mo(n|nday)?|tu(e|es|esday)?|we(d|dnesday)?|" \
    "th(u|ur|urs|ursday)?|fr(i|iday)?|sa(t|tur|turday)?"
  MONTH_WORD_PATTERN = "jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|" \
    "aug(ust)?|sept?(ember)?|oct(ober)?|nov(ember)?|dec(ember)?"
  DATE_WORD_PATTERN = Regexp.new(
    "\\A((next +|last +|this +)?(#{WEEKDAY_PATTERN})|today|yesterday|tomorrow|" \
    "\\d{1,2}(st|nd|rd|th)|([ .\\/\\\\-]|[0-9]|#{MONTH_WORD_PATTERN}|days?|weeks?|ago){3,})\\z"
  )

  # Words resolved to a concrete date before range parsing, so "today to fri"
  # or "5th thru 9th" reach the range rules as plain dates. Lookarounds keep the
  # neighbouring separators in place.
  RELATIVE_DATE_WORD = /
    (?<![a-z])(?:(?:next|last|this)[ ]+)?(?:#{WEEKDAY_PATTERN})(?![a-z])
    | (?<![a-z])(?:today|yesterday|tomorrow)(?![a-z])
    | (?<![a-z0-9])\d{1,2}(?:st|nd|rd|th)(?![a-z])
  /xo

  RELATIVE_SHIFT_PATTERN = /this|current|next|upcoming|following|last|past|prev(?:ious)?/
  UNIT_SIZE_PATTERN = /days?|dys?|weeks?|wks?|mos?|months?|quarters?|qtrs?|years?|yrs?/
  MONTH_PATTERN = Regexp.new(
    "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|" \
    "sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
  )
  YEAR_PATTERN = /\d{4}|'\d{2}/
  PARSEABLE_DATE_PATTERN = /[a-z0-9 .\/\-,]{3,}|mo|tu|we|th|fr|sa|su/
  ISO_DATE_IN_TEXT = /(?<![\d\/])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d\/])/
  ISO_DATETIME_PATTERN = /\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?\z/
  EXPLICIT_TIME_PATTERN = /(?:\bat\b|\bnoon\b|\bmidnight\b|\d{1,2}:\d{2}|\d{1,2}\s*(?:am|pm)\b)/i
  NUMERIC_DATE_PATTERN = /\A(\d+)\s*[\/.\-]\s*(\d+)(?:\s*[\/.\-]\s*(\d+))?\z/
  TIME_ONLY_PATTERN = /\A(?:\d{1,2}(?::\d{2}){1,2}\s*(?:am|pm)?|\d{1,2}\s*(?:am|pm)|noon|midnight)\z/i

  private_constant :WEEKDAY_PATTERN, :MONTH_WORD_PATTERN, :DATE_WORD_PATTERN, :RELATIVE_DATE_WORD,
    :RELATIVE_SHIFT_PATTERN, :UNIT_SIZE_PATTERN, :MONTH_PATTERN, :YEAR_PATTERN, :PARSEABLE_DATE_PATTERN,
    :ISO_DATE_IN_TEXT, :ISO_DATETIME_PATTERN, :EXPLICIT_TIME_PATTERN, :NUMERIC_DATE_PATTERN, :TIME_ONLY_PATTERN

  class << self
    # Parse one date. Returns a Date, or nil when the input isn't a date.
    #
    # Options are passed to Chronic: `context: :past` resolves ambiguous dates
    # backward ("jan 5" means last January), and `now:` sets the reference
    # point. Dates and times pass through as dates.
    def parse(input, options = {})
      return input.to_date if input.respond_to?(:to_date) && !input.is_a?(String)
      return nil if input.nil?

      raw = input.to_s.strip
      # Bare numbers and bare times of day are not dates.
      return nil if raw.empty? || raw.match?(/\A\d+\z/) || raw.match?(TIME_ONLY_PATTERN)

      date_val = raw
      date_pieces = []

      if (match_data = raw.match(NUMERIC_DATE_PATTERN))
        date_pieces = match_data.to_a.slice(1..3).compact
        date_pieces[2] = "20#{date_pieces[2]}" if date_pieces[2] == "00"
        date_val = date_pieces.join("/")
      end

      chronic = chronic_options(options)
      parsed = Chronic.parse(date_val, chronic)&.to_date

      # A month/day without a year that Chronic pushed almost a year ahead was
      # meant as the recent past ("11/10" typed on Nov 11).
      if parsed && date_pieces.length == 2
        today = today(chronic)
        parsed -= 1.year if parsed > (today + 330.days) && parsed < (today + 1.year)
      end

      parsed
    rescue StandardError
      nil
    end

    # Parse a date and time in Time.zone (or system time when no zone is set).
    # Returns an ActiveSupport::TimeWithZone (or Time), or nil. A date with no
    # time of day means midnight.
    def parse_datetime(input, options = {})
      return input.in_time_zone if input.respond_to?(:in_time_zone) && !input.is_a?(String)
      return nil if input.nil?

      raw = input.to_s.strip
      return nil if raw.empty?
      return Time.zone ? Time.zone.parse(raw) : Time.parse(raw) if raw.match?(ISO_DATETIME_PATTERN)

      unless raw.match?(EXPLICIT_TIME_PATTERN)
        parsed_date = parse(raw, options)
        return parsed_date.in_time_zone if parsed_date
      end

      parsed = Chronic.parse(raw, chronic_options(options))
      return nil unless parsed
      return parsed unless Time.zone

      Time.zone.local(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.min, parsed.sec)
    rescue StandardError
      nil
    end

    # True when the input reads as a single date ("today", "next fri",
    # "1/2/26"). Bare numbers are never dates.
    def parseable?(input)
      raw = input.to_s.strip
      return false if raw.match?(/\A[0-9,.]+\z/)

      parse(raw).present? && raw.downcase.match?(DATE_WORD_PATTERN)
    end

    # Parse a date or a span of dates. Returns [from, to] with either end
    # possibly nil for open-ended input ("since jan", "until fri"), or nil
    # when the input isn't a date. A single date returns [date, date].
    #
    # Options are passed to Chronic, as for parse.
    def parse_range(input, options = {})
      original = input.to_s.strip.squish.downcase
      return nil if original.empty?

      opts = chronic_options(options)
      iso_rewritten = original.gsub(ISO_DATE_IN_TEXT) { "#{$2}/#{$3}/#{$1}" }
      range_val = iso_rewritten

      unless range_val.match?(/\A(after|from|before|until|since|thru|through)/)
        range_val = range_val.gsub(RELATIVE_DATE_WORD) do |text|
          parseable?(text) ? " #{parse(text, opts).strftime("%m/%d/%Y")} " : text
        end.squish
      end

      range = parse_named_range(range_val, opts) ||
        parse_year_range(range_val, opts) ||
        parse_month_range(range_val, opts) ||
        parse_unit_range(range_val, opts) ||
        parse_span_range(range_val, opts) ||
        parse_period_to_date_range(range_val, opts) ||
        parse_one_sided_before_after_range(range_val, opts) ||
        parse_one_sided_month_range(range_val, opts) ||
        parse_one_sided_since_through_range(range_val, opts) ||
        parse_month_day_range(range_val, opts) ||
        parse_verbose_range(iso_rewritten, opts) ||
        parse_verbose_range(range_val, opts) ||
        parse_single_date_range(range_val, opts)

      return nil unless range

      range.include?(nil) ? range : range.sort
    rescue StandardError
      nil
    end

    private

    # Chronic works in system time; anchor it to Time.zone's clock so "today"
    # agrees with Date.current. A Date given as `now:` becomes its midnight.
    def chronic_options(options)
      options = options.to_h.symbolize_keys
      now = options[:now]

      if now.nil?
        options[:now] = Time.zone.now if Time.zone
      elsif now.instance_of?(Date)
        options[:now] = Time.zone ? now.in_time_zone : now.to_time
      end

      options
    end

    def today(opts)
      opts[:now] ? opts[:now].to_date : Date.current
    end

    def parse_named_range(range_val, opts)
      today = today(opts)

      case range_val
      when "past" then [nil, today]
      when "future", "upcoming" then [today, nil]
      when "recent" then [today - 90.days, today]
      when "current" then [today - 1.week, today + 1.week]
      end
    end

    def parse_year_range(range_val, opts)
      return nil unless range_val.match?(/\A#{YEAR_PATTERN}\z/o)

      year = to_four_year(range_val.gsub(/\D/, ""), opts)
      [Date.new(year.to_i, 1, 1), Date.new(year.to_i, 12, 31)]
    end

    def parse_month_range(range_val, opts)
      match_data = range_val.match(/\A(#{RELATIVE_SHIFT_PATTERN} )?(#{MONTH_PATTERN})( #{YEAR_PATTERN})?\z/o)
      return nil unless match_data

      relative_shift = simplify_relative_shift(match_data[1].to_s.strip)
      month = match_data[2]

      first = if relative_shift.present?
        apply_shift(parse("#{month} 1st #{today(opts).year}", opts), relative_shift, "year")
      else
        year = to_four_year(match_data[3].to_s.gsub(/\D/, ""), opts)
        parse("#{month} 1st #{year.presence || today(opts).year}", opts)
      end

      [first, first.end_of_month]
    end

    def parse_unit_range(range_val, opts)
      match_data = range_val.match(/\A(#{RELATIVE_SHIFT_PATTERN})? ?(#{UNIT_SIZE_PATTERN})\z/o)
      return nil unless match_data

      relative_shift = simplify_relative_shift((match_data[1] || "this").strip)
      unit_size = simplify_unit_size(match_data[2].to_s.strip)
      first = today(opts).public_send("beginning_of_#{unit_size}").to_date
      first = apply_shift(first, relative_shift, unit_size)

      [first, first.public_send("end_of_#{unit_size}").to_date]
    end

    def parse_span_range(range_val, opts)
      match_data = range_val.match(/\A(#{RELATIVE_SHIFT_PATTERN})?( *-?[0-9]+ ?)? ?(#{UNIT_SIZE_PATTERN})\z/o)
      return nil unless match_data

      today = today(opts)
      relative_shift = simplify_relative_shift(match_data[1] || "next")
      step_size = (match_data[2] || 1).to_s.strip.to_i
      unit_size = simplify_unit_size(match_data[3].to_s.strip)
      shifted_date = apply_shift(today, relative_shift, unit_size, step_size)

      (relative_shift == "last") ? [shifted_date, today] : [today, shifted_date]
    end

    def parse_period_to_date_range(range_val, opts)
      match_data = range_val.match(/\A(w|week |m|month |q|quarter |y|year )(to date|td)\z/)
      return nil unless match_data

      relative_term = {
        "w" => "week",
        "m" => "month",
        "q" => "quarter",
        "y" => "year"
      }.fetch(match_data[1].strip[0], "")

      today = today(opts)
      [today.public_send("beginning_of_#{relative_term}"), today]
    end

    def parse_one_sided_before_after_range(range_val, opts)
      match_data = range_val.match(/\A(after|from|before|until) (#{PARSEABLE_DATE_PATTERN})\z/o)
      return nil unless match_data

      date = parse(match_data[2], opts)
      return nil unless date

      case match_data[1]
      when "after" then [date + 1.day, nil]
      when "from" then [date, nil]
      when "before" then [nil, date - 1.day]
      when "until" then [nil, date]
      end
    end

    def parse_one_sided_month_range(range_val, opts)
      match_data = range_val.match(
        /
          \A(since|thru|through)[ ]?(first|start|beginning|last|end)?[ ]?(?:of[ ])?
          ((?:this[ ]|last[ ]|next[ ])?month|#{MONTH_PATTERN}(?:[ ]#{YEAR_PATTERN})?)\z
        /xo
      )
      return nil unless match_data

      relative_term = match_data[1]
      month_term = match_data[3]
      today = today(opts)

      if relative_term == "since"
        date_shift = %w[last end].include?(match_data[2]) ? :end_of_month : :beginning_of_month
        [parse(month_term, opts.merge(context: :past)).public_send(date_shift), today]
      else
        date_shift = %w[first start beginning].include?(match_data[2]) ? :beginning_of_month : :end_of_month
        [today, parse(month_term, opts.merge(context: :future)).public_send(date_shift)]
      end
    end

    def parse_one_sided_since_through_range(range_val, opts)
      match_data = range_val.match(/\A(since|thru|through) (#{PARSEABLE_DATE_PATTERN})\z/o)
      return nil unless match_data

      if match_data[1] == "since"
        date = parse(match_data[2], opts.merge(context: :past))
        date && [date, today(opts)]
      else
        date = parse(match_data[2], opts.merge(context: :future))
        date && [today(opts), date]
      end
    end

    def parse_month_day_range(range_val, opts)
      match_data = range_val.match(
        /
          \A(#{MONTH_PATTERN})[ ](\d{1,2})[ ]?(?:st|nd|rd|th)?[ ]?(?:to|thru|through|-)[ ]?
          (\d{1,2})[ ]?(?:st|nd|rd|th)?\z
        /xo
      )
      return nil unless match_data

      today = today(opts)
      month = parse(match_data[1], opts).month
      future_months = (today.month..(today.month + 4)).map { |i| (i > 12) ? i - 12 : i }
      context = future_months.include?(month) ? :future : :past

      [
        parse("#{month}/#{match_data[2]}", opts.merge(context: context)),
        parse("#{month}/#{match_data[3]}", opts.merge(context: context))
      ]
    end

    # "a to b". A side that names a whole month or year contributes its first
    # day on the left and its last day on the right ("jan to mar"). The right
    # side resolves relative to the left ("mon-fri" is one week).
    def parse_verbose_range(range_val, opts)
      match_data = range_val.match(
        /\A(#{PARSEABLE_DATE_PATTERN}) ?(to|thru|through|\.\.|-|:|and)++ ?(#{PARSEABLE_DATE_PATTERN})\z/o
      )
      return nil unless match_data

      left_text = match_data[1].strip
      right_text = match_data[3].strip

      from = period_edge(left_text, :first, opts) || parse(left_text, opts)
      return nil unless from

      to = period_edge(right_text, :last, opts) || parse(right_text, opts.merge(now: from))
      return nil unless to

      [from, to]
    end

    def period_edge(text, edge, opts)
      range = parse_year_range(text, opts) || parse_month_range(text, opts)
      range&.public_send(edge)
    end

    def parse_single_date_range(range_val, opts)
      return nil unless parseable?(range_val)

      date = parse(range_val, opts)
      [date, date]
    end

    def simplify_relative_shift(relative_shift)
      case relative_shift
      when "next", "upcoming", "following" then "next"
      when "last", "past", "prev", "previous" then "last"
      when "this", "current" then "this"
      else relative_shift
      end
    end

    def simplify_unit_size(unit_size)
      case unit_size
      when "day", "days", "dy", "dys" then "day"
      when "week", "weeks", "wk", "wks" then "week"
      when "month", "months", "mo", "mos" then "month"
      when "quarter", "quarters", "qtr", "qtrs" then "quarter"
      when "year", "years", "yr", "yrs" then "year"
      else unit_size
      end
    end

    def apply_shift(first, relative_shift, unit_size, step_size = 1)
      return first if relative_shift == "this"

      if unit_size == "quarter"
        return first + (3 * step_size).months if relative_shift == "next"
        return first - (3 * step_size).months if relative_shift == "last"
      end

      return first + step_size.public_send(unit_size) if relative_shift == "next"
      return first - step_size.public_send(unit_size) if relative_shift == "last"

      first
    end

    # "99" → "1999", "26" → "2026": two-digit years more than 30 years ahead
    # belong to the previous century.
    def to_four_year(year, opts, years_forward_cutoff = 30)
      return year unless year.match?(/\A\d{2}\z/)

      current_year = today(opts).year
      this_century = current_year.to_s[0, 2]
      if "#{this_century}#{year}".to_i > (current_year + years_forward_cutoff)
        "#{this_century.to_i - 1}#{year}"
      else
        "#{this_century}#{year}"
      end
    end
  end
end

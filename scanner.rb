# This is the main class, and it scans a frame (Grid) for pattern matches using
# configurable similarity and filtering.
#
# I may have gone a bit overboard with how SOLID it is, but the problem
# description kind of hinted that it is desirable so I iterated over the
# initial solution to get to this point. I don't think this level of
# configurability is always a good thing when writing software but I wanted to
# see what I would end up with if I tried to go in this direction.
class Scanner
  # @param patterns [Array<Grid>] patterns to search for
  # @param threshold [Float] minimum similarity score to consider a match
  # @param similarity [#call] strategy for comparing two lines
  # @param filters [Array<#call>] post-processing filters applied to the resulting matches
  def initialize(
    patterns: [],
    threshold: 0.75,
    similarity: Similarity::Hamming,
    filters: [Filters::Overlap]
  )
    @matchers = patterns.map { |pattern| Matcher.new(pattern, similarity) }
    @threshold = threshold
    @filters = filters
  end

  def scan(frame)
    matches = []
    @matchers.each { |matcher| matcher.scan(frame, @threshold) { |match| matches << match } }
    @filters.reduce(matches) { |m, filter| filter.call(m) }
  end
end

# A sliding window that matches a single pattern against a grid using a
# configurable similarity strategy.
class Matcher
  attr_reader :pattern

  def initialize(pattern, similarity)
    @pattern = pattern
    @similarity = similarity
  end

  def scan(frame, threshold, &block)
    (-@pattern.height...frame.height).each do |y|
      (-@pattern.width...frame.width).each do |x|
        score = calculate_score(frame, x, y)
        block.call(Match.new(x, y, score, @pattern)) if score > threshold
      end
    end
  end

  private

  def calculate_score(frame, x, y)
    row = 0
    total = 0.0

    frame.subgrid(x, y, @pattern.width, @pattern.height) do |line|
      total += @similarity.call(line, @pattern.data[row])
      row += 1
    end

    total / @pattern.height.to_f
  end
end

# Line-level similarity strategies for comparing frame regions to patterns. All
# of the Similarity strategies follow the same callable interface.
module Similarity
  # All mismatches penalized equally
  module Hamming
    def self.call(frame_line, pattern_line)
      mismatches = (0...pattern_line.length).count { |i| frame_line[i] != pattern_line[i] }
      1.0 - mismatches.to_f / pattern_line.length
    end
  end

  # Weights foreground mismatches more heavily than background with
  # configurable weighting.
  class ForegroundWeighted
    DEFAULT_BACKGROUND_WEIGHT = 0.3

    def self.call(frame_line, pattern_line)
      new.call(frame_line, pattern_line)
    end

    def initialize(background_weight: DEFAULT_BACKGROUND_WEIGHT)
      @background_weight = background_weight
    end

    def call(frame_line, pattern_line)
      distance = 0.0
      max = 0.0

      (0...pattern_line.length).each do |i|
        snd = pattern_line[i]
        weight = snd == "o" ? 1.0 : @background_weight
        max += weight
        distance += weight if frame_line[i] != snd
      end

      1.0 - distance / max
    end
  end
end

# Post-processing filters applied to match results.
module Filters
  # Removes overlapping matches, keeping higher-scoring ones.
  module Overlap
    def self.call(matches)
      matches.sort_by { -_1.score }.each_with_object([]) do |match, kept|
        next if kept.any? { |other| overlaps?(match, other) }
        kept << match
      end
    end

    def self.overlaps?(a, b)
      a.x < b.x +
        b.pattern.width &&
        a.x +
        a.pattern.width > b.x &&
        a.y < b.y +
        b.pattern.height &&
        a.y +
        a.pattern.height > b.y
    end

    private_class_method :overlaps?
  end
end

# A 2D character grid with support for string parsing and subgrid extraction.
class Grid
  class ParseError < StandardError
  end

  attr_reader :width, :height, :data

  # @param raw [String] text with ~~~ delimiters around grid rows
  # @return [Grid]
  # @raise [ParseError] if delimiters are missing or line widths are inconsistent
  def self.parse(raw)
    lines = raw.strip.lines.map { it.strip }

    unless lines.shift&.match?(/\A~+\z/) && lines.pop&.match?(/\A~+\z/)
      raise ParseError, "grid must start and end with ~~~ delimiters"
    end

    lines.reject!(&:empty?)
    raise ParseError, "grid has no content between delimiters" if lines.empty?
    raise ParseError, "inconsistent line widths" unless lines.map(&:length).uniq.size == 1

    new(lines)
  end

  def initialize(data)
    @data = data
    @width = @data.first.length
    @height = @data.length
  end

  # @param x [Integer] left column (may be negative for clipping)
  # @param y [Integer] top row (may be negative for clipping)
  # @param w [Integer] width of the region
  # @param h [Integer] height of the region
  # @yield [String] each extracted line, if a block is given
  # @return [Grid, nil] a new Grid when no block is given
  def subgrid(x, y, w, h)
    if block_given?
      (0...h).each { |row| yield extract_line(x, y + row, w) }
    else
      Grid.new((0...h).map { |row| extract_line(x, y + row, w) })
    end
  end

  def ==(other)
    other.is_a?(Grid) && @data == other.data
  end

  alias_method :eql?, :==

  def hash
    @data.hash
  end

  private

  def extract_line(x, y, w)
    return " " * w if y < 0 || y >= @height

    left_pad = [-x, 0].max
    start = [x, 0].max
    line = (" " * left_pad) + @data[y][start, w - left_pad]
    line.ljust(w, " ")
  end
end

# An immutable value object representing a pattern match at a position.
Match = Data.define(:x, :y, :score, :pattern)

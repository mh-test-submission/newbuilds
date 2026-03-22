require "rspec"

require_relative "scanner"

describe Scanner do
  let(:invader_1) { Grid.parse(File.read("fixtures/sample_invader_1.txt")) }
  let(:invader_2) { Grid.parse(File.read("fixtures/sample_invader_2.txt")) }
  let(:patterns) { [invader_1, invader_2] }

  describe "#scan" do
    let(:patterns) { [invader_1] }
    let(:frame) { Grid.parse(File.read("fixtures/well_bounded_invader_1.txt")) }
    let(:scanner) { Scanner.new(patterns: patterns, threshold: 0.9) }
    subject { scanner.scan(frame) }

    specify("a really basic happy path") do
      expect(subject.count).to(eq(1))
      expect(subject.first.x).to(eq(1))
      expect(subject.first.y).to(eq(1))
      expect(subject.first.score).to(eq(1.0))
      expect(subject.first.pattern).to(eq(invader_1))
    end

    specify("frame with partial match") do
      partial_frame = Grid.parse(File.read("fixtures/partial_invader_1.txt"))
      result = Scanner
        .new(
          patterns: patterns,
          threshold: 0.6,
          similarity: Similarity::ForegroundWeighted
        )
        .scan(partial_frame)

      expect(result.count).to(eq(1))
      expect(result.first.x).to(eq(-4))
      expect(result.first.y).to(eq(1))
      expect(result.first.score).to(be_within(0.01).of(0.64))
    end

    specify("frame with vertical partial match") do
      vertical_partial = Grid.parse(File.read("fixtures/vertical_partial_invader_1.txt"))
      result = Scanner
        .new(patterns: patterns, threshold: 0.4)
        .scan(vertical_partial)

      top_match = result.select { |m| m.y < 0 }.max_by(&:score)
      expect(top_match).not_to(be_nil)
      expect(top_match.x).to(eq(0))
      expect(top_match.y).to(eq(-4))
      expect(top_match.score).to(eq(0.5))
    end

    specify("multiple patterns") do
      frame = Grid.new([
        "---------------------",
        "---o-----o-----oo----",
        "----o---o-----oooo---",
        "---ooooooo---oooooo--",
        "--oo-ooo-oo-oo-oo-oo-",
        "-ooooooooooooooooooo-",
        "-o-ooooooo-o--o--o---",
        "-o-o-----o-o-o-oo-o--",
        "----oo-oo---o-o--o-o-",
        "---------------------"
      ])
      result = Scanner.new(patterns: [invader_1, invader_2], threshold: 0.9).scan(frame)

      expect(result.count).to(eq(2))
      expect(result.map(&:pattern)).to(contain_exactly(
        invader_1,
        invader_2
      ))
    end

    specify("sample radar") do
      radar = Grid.parse(File.read("fixtures/sample_radar.txt"))
      result = Scanner.new(patterns: [invader_1, invader_2]).scan(radar)

      expect(result).not_to(be_empty)
      expect(result.map(&:pattern).uniq).to(contain_exactly(invader_1, invader_2))
      expect(result).to(all(satisfy { |m| m.score > 0.75 && m.score <= 1.0 }))
    end

    context("with no patterns to look") do
      let(:patterns) { [] }

      it "is empty" do
        is_expected.to(be_empty)
      end
    end
  end
end

describe Similarity::Hamming do
  it "returns 1.0 for identical lines" do
    expect(described_class.call("ooo", "ooo")).to(eq(1.0))
  end

  it "returns 0.0 for completely different lines" do
    expect(described_class.call("---", "ooo")).to(eq(0.0))
  end

  it "returns the fraction of matching characters" do
    expect(described_class.call("o-o", "ooo")).to(be_within(0.001).of(2.0 / 3))
  end
end

describe Similarity::ForegroundWeighted do
  it "returns 1.0 for identical lines" do
    expect(described_class.call("o-o", "o-o")).to(eq(1.0))
  end

  it "penalises missing foreground more than missing background" do
    # one foreground mismatch in a mixed line vs one background mismatch
    foreground_miss = described_class.call("--", "o-")
    background_miss = described_class.call("oo", "-o")
    expect(foreground_miss).to(be < background_miss)
  end

  it "returns 0.0 when all foreground mismatches" do
    expect(described_class.call("---", "ooo")).to(eq(0.0))
  end

  it "accepts a custom background weight" do
    low_bg = described_class.new(background_weight: 0.1)
    high_bg = described_class.new(background_weight: 0.9)

    # background mismatch penalised more with higher weight
    expect(low_bg.call("oo", "-o")).to(be > high_bg.call("oo", "-o"))
  end
end

describe Grid do
  describe ".parse" do
    it "strips ~ delimiters" do
      grid = Grid.parse("~~~\no-\n-o\n~~~")
      expect(grid.data).to(eq(["o-", "-o"]))
    end

    it "strips leading and trailing whitespace" do
      grid = Grid.parse("  ~~~  \n  o-  \n  -o  \n  ~~~  ")
      expect(grid.data).to(eq(["o-", "-o"]))
    end

    it "handles ~ and whitespace together" do
      grid = Grid.parse("~~~~\n  oo--  \n  --oo  \n~~~~\n")
      expect(grid.data).to(eq(["oo--", "--oo"]))
      expect(grid.width).to(eq(4))
      expect(grid.height).to(eq(2))
    end

    it "raises ParseError when missing delimiters" do
      expect { Grid.parse("oo\noo") }.to(raise_error(Grid::ParseError, "grid must start and end with ~~~ delimiters"))
    end

    it "raises ParseError for inconsistent line widths" do
      expect { Grid.parse("~~~\noo\nooo\n~~~") }.to(raise_error(Grid::ParseError, "inconsistent line widths"))
    end
  end

  let(:invader) { File.read("fixtures/sample_invader_1.txt") }
  subject { Grid.parse(invader) }

  it { expect(subject.width).to(eq(11)) }
  it { expect(subject.height).to(eq(8)) }
  it do
    expect(subject.data).to(
      eq(
        [
          "--o-----o--",
          "---o---o---",
          "--ooooooo--",
          "-oo-ooo-oo-",
          "ooooooooooo",
          "o-ooooooo-o",
          "o-o-----o-o",
          "---oo-oo---"
        ]
      )
    )
  end

  describe "#subgrid" do
    let(:grid) { Grid.new(["o--o", "-oo-", "oo-o", "-o-o"]) }

    it "extracts a fully inside region" do
      result = grid.subgrid(1, 1, 2, 2)
      expect(result.data).to(eq(["oo", "o-"]))
    end

    it "pads with spaces when clipped on the left" do
      result = grid.subgrid(-1, 0, 3, 2)
      expect(result.data).to(eq([" o-", " -o"]))
    end

    it "pads with spaces when clipped on top" do
      result = grid.subgrid(0, -1, 3, 2)
      expect(result.data).to(eq(["   ", "o--"]))
    end

    it "pads with spaces when clipped on the right" do
      result = grid.subgrid(3, 0, 3, 2)
      expect(result.data).to(eq(["o  ", "-  "]))
    end

    it "pads with spaces when clipped on the bottom" do
      result = grid.subgrid(0, 3, 3, 2)
      expect(result.data).to(eq(["-o-", "   "]))
    end

    it "pads with spaces when clipped on corner" do
      result = grid.subgrid(-1, -1, 3, 3)
      expect(result.data).to(eq(["   ", " o-", " -o"]))
    end

    it "yields lines when given a block" do
      lines = []
      grid.subgrid(1, 1, 2, 2) { |line| lines << line }
      expect(lines).to(eq(["oo", "o-"]))
    end
  end
end

describe Filters::Overlap do
  let(:pattern) { Grid.new(["oo", "oo"]) }
  let(:other_pattern) { Grid.new(["--", "--"]) }

  it "keeps non-overlapping matches" do
    matches = [
      Match.new(0, 0, 0.9, pattern),
      Match.new(10, 10, 0.8, pattern)
    ]
    expect(described_class.call(matches).count).to(eq(2))
  end

  it "keeps the higher-scoring match when overlapping" do
    matches = [
      Match.new(0, 0, 0.7, pattern),
      Match.new(1, 1, 0.9, pattern)
    ]
    result = described_class.call(matches)
    expect(result.count).to(eq(1))
    expect(result.first.score).to(eq(0.9))
  end

  it "keeps adjacent but non-overlapping matches" do
    matches = [
      Match.new(0, 0, 0.9, pattern),
      Match.new(2, 0, 0.8, pattern)
    ]
    expect(described_class.call(matches).count).to(eq(2))
  end

  it "suppresses across different patterns" do
    matches = [
      Match.new(0, 0, 0.9, pattern),
      Match.new(1, 1, 0.8, other_pattern)
    ]
    result = described_class.call(matches)
    expect(result.count).to(eq(1))
    expect(result.first.score).to(eq(0.9))
  end
end

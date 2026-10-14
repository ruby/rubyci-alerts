require "test/unit"
require_relative "../rubyci-alerts"

class TestRubyCIAlerts < Test::Unit::TestCase
  FIXTURES = File.join(__dir__, "fixtures")

  # URI.open falls back to Kernel#open for a local path, so the fixtures go
  # through the real fetch_json.
  def fetch_json(url)
    super(File.join(FIXTURES, File.basename(url)))
  end

  def test_get_failure_reports
    reports = get_failure_reports(get_servers).map {|_key, report| report.to_h }
    assert_equal [
      {
        name: "macOS 14.8 Sonoma",
        commit: "7ad8db23115",
        fail_uri: "http://rubyci.s3.amazonaws.com/osx1400arm/ruby-master/log/20261013T202906Z.fail.html.gz",
        shortsummary: "67W failed(dist)",
      },
      {
        name: "icc 2025.3 x64 (Ubuntu)",
        commit: "15212f6c1cf",
        fail_uri: "http://rubyci.s3.amazonaws.com/icc-x64/ruby-master/log/20261013T183012Z.fail.html.gz",
        shortsummary: "12W failed(test-all)",
      },
    ], reports
  end

  def test_filter_failure_reports
    reports = get_failure_reports(get_servers)
    notified = Time.iso8601("2026-10-13T20:29:06Z").to_i
    timestamps = { "122" => notified }

    filter_failure_reports(reports, timestamps)

    assert_equal ["icc 2025.3 x64 (Ubuntu)"], reports.map {|_key, report| report.name }
    assert_equal({ "122" => notified, "40" => Time.iso8601("2026-10-13T18:30:12Z").to_i }, timestamps)
  end
end

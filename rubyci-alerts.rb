#!/usr/bin/env ruby

require "open-uri"
require "uri"
require "json"
require "time"

SLACK_WEBHOOK_URL = ENV["RUBYCI_ALERTS_SLACK_WEBHOOK_URL"]
RUBYCI_SERVERS_URL = "https://rubyci.org/servers.json"
RUBYCI_REPORTS_URL = "https://rubyci.org/reports.json"
SIMPLER_ALERTS_URL = ENV["RUBYCI_ALERTS_SIMPLER_ALERTS_URL"]
TIMESTAMPS_JSON = File.join(__dir__, "timestamps.json")

NOTIFY_CHANNELS = [
  "C5FCXFXDZ", # alerts
  "CR2QGFCAE", # alerts-emoji
]

FailureReport = Struct.new(
  :name,
  :commit,
  :fail_uri,
  :shortsummary,
  keyword_init: true
) do
  def msg
    commit_link = " (<https://github.com/ruby/ruby/commit/#{ commit }|#{ commit }>)" if commit
    "#{ name }#{ commit_link }: <#{ fail_uri }|#{ shortsummary }>"
  end
end

def shortsummary(summary)
  summary[/^[^\x28]+(?:\s*\([^\x29]*\)|\s*\[[^\x5D]*\])*\s*(\S.*?) \(/, 1]
end

def escape(s)
  s.gsub(/[&<>]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
end

def notify_slack(msg, channel:)
  params = { text: msg, channel: channel }
  if SLACK_WEBHOOK_URL
    Net::HTTP.post(
      URI.parse(SLACK_WEBHOOK_URL),
      JSON.generate(params),
      "Content-Type" => "application/json"
    )
  else
    pp params
  end
end

def notify_simpler_alerts(report)
  params = {
    ci: "rubyci-alerts",
    env: report.name,
    url: report.fail_uri,
    commit: report.commit,
    message: report.shortsummary,
  }
  if SIMPLER_ALERTS_URL
    Net::HTTP.post(
      URI.parse(SIMPLER_ALERTS_URL),
      JSON.generate(params),
      "Content-Type" => "application/json"
    )
  else
    pp params
  end
end

def fetch_json(url)
  count = 0
  begin
    URI.open(url) do |f|
      JSON.parse(f.read)
    end
  rescue Exception
    count += 1
    if count < 3
      sleep 3
      retry
    end
    raise
  end
end

def get_servers
  servers = {}
  fetch_json(RUBYCI_SERVERS_URL).each do |server|
    servers[server["id"]] = server if server["name"] != "crossruby"
  end
  servers
end

def get_failure_reports(servers)
  failure_reports = []
  fetch_json(RUBYCI_REPORTS_URL).each do |report|
    next if report["branch"] != "master"

    server_id = report["server_id"]
    server = servers[server_id]
    next if !server
    name = server["name"]
    uri = URI.parse(server["uri"])
    ordinal = server["ordinal"]
    datetime = Time.iso8601(report["datetime"]).to_i
    summary = report["summary"]
    shortsummary = shortsummary(summary)
    commit = summary[/^(\h{10,}) /, 1]
    raw = report["ltsv"].split("\t").map {|s| s.split(":", 2) }.to_h
    fail_path = raw["compressed_failhtml_relpath"]
    fail_uri = uri.to_s
    fail_uri = File.join(fail_uri, "ruby-master", fail_path)

    unless shortsummary.include?("success")
      report = FailureReport.new(
        name: name,
        commit: commit,
        fail_uri: fail_uri,
        shortsummary: escape(shortsummary),
      )
      failure_reports << [[ordinal, datetime, server_id.to_s], report]
    end
  end
  failure_reports.sort_by {|key, _report| key }
end

def filter_failure_reports(failure_reports, timestamps)
  failure_reports.reject! do |(_ordinal, datetime, server_id), _report|
    timestamps[server_id] && datetime <= timestamps[server_id]
  end
  failure_reports.each do |(_ordinal, datetime, server_id), _report|
    timestamps[server_id] = [timestamps[server_id], datetime].compact.max
  end
end

begin
  timestamps = {}
  timestamps = JSON.parse(File.read(TIMESTAMPS_JSON))

  servers = get_servers
  failure_reports = get_failure_reports(servers)
  filter_failure_reports(failure_reports, timestamps)
  failure_reports.each do |_key, report|
    notify_simpler_alerts(report)
  end

  File.write(TIMESTAMPS_JSON, JSON.pretty_generate(timestamps))
rescue => e
  NOTIFY_CHANNELS.each do |channel|
    notify_slack("ruby/rubyci-alerts failed: #{e.class}: #{ escape(e.message) }", channel: channel)
  end
  puts e.backtrace
end

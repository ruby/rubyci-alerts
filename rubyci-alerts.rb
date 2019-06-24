#!/usr/bin/env ruby

require "open-uri"
require "uri"
require "json"
require "time"

SLACK_WEBHOOK_URL = ENV["SLACK_WEBHOOK_URL"]
RUBYCI_SERVERS_URL = "https://rubyci.org/servers.json"
RUBYCI_REPORTS_URL = "https://rubyci.org/reports.json"
TIMESTAMPS_DAT = File.join(__dir__, "timestamps.dat")

def shortsummary(summary)
  summary[/^[^\x28]+(?:\s*\([^\x29]*\)|\s*\[[^\x5D]*\])*\s*(\S.*?) \(/, 1]
end

def escape(s)
  s.gsub(/[&<>]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
end

def notify_slack(msg)
  params = { text: msg }
  Net::HTTP.post(
    URI.parse(SLACK_WEBHOOK_URL),
    JSON.generate(params),
    "Content-Type" => "application/json"
  )
end

def get_servers
  servers = {}
  open(RUBYCI_SERVERS_URL) do |f|
    JSON.parse(f.read).each do |server|
      servers[server["id"]] = server
    end
  end
  servers
end

def get_failure_reports(servers)
  failure_reports = []
  open(RUBYCI_REPORTS_URL) do |f|
    JSON.parse(f.read).each do |report|
      next if report["branch"] != "master"

      server_id = report["server_id"]
      server = servers[server_id]
      name = server["name"]
      uri = URI.parse(server["uri"])
      ordinal = server["ordinal"]
      datetime = Time.iso8601(report["datetime"])
      summary = report["summary"]
      shortsummary = shortsummary(summary)
      commit = summary[/^(\h{10,}) /, 1]
      raw = report["ltsv"].split("\t").map {|s| s.split(":", 2) }.to_h
      fail_path = raw["compressed_failhtml_relpath"]
      fail_uri = "https://rubyci.org/logs/#{ uri.host + uri.path }"
      fail_uri = File.join(fail_uri, "ruby-master", fail_path)

      unless shortsummary.include?("success")
        commit = " (<https://github.com/ruby/ruby/commit/#{ commit }|#{ commit }>)" if commit
        msg = "#{ name }#{ commit }: <#{ fail_uri }|#{ escape(shortsummary) }>"
        failure_reports << [[ordinal, datetime, server_id], msg]
      end
    end
  end
  failure_reports.sort_by {|key, _msg| key }
end

def filter_failure_reports(failure_reports, timestamps)
  failure_reports.reject! do |(_ordinal, datetime, server_id), _msg|
    timestamps[server_id] && datetime <= timestamps[server_id]
  end
  failure_reports.each do |(_ordinal, datetime, server_id), _msg|
    timestamps[server_id] = [timestamps[server_id], datetime].compact.max
  end
end

begin
  timestamps = {}
  timestamps = Marshal.load(File.binread(TIMESTAMPS_DAT)) if File.readable?(TIMESTAMPS_DAT)

  servers = get_servers
  failure_reports = get_failure_reports(servers)
  filter_failure_reports(failure_reports, timestamps)
  failure_reports.each do |_key, msg|
    notify_slack(msg)
  end

  File.binwrite(TIMESTAMPS_DAT, Marshal.dump(timestamps))
ensure
  notify_slack("failed: #{ escape($!.message) }")
end

#!/usr/bin/env ruby

require "selenium-webdriver"
require "net/http"
require "openssl"

SLACK_API_TOKEN = ENV["RUBYCI_SCREENSHOT_SLACK_API_TOKEN"]
CHANNEL_ID = ENV["RUBYCI_SCREENSHOT_SLACK_CHANNEL_ID"]
FILES_UPLOAD_URI = "https://slack.com/api/files.upload"

Dir.chdir(__dir__)

system("/usr/bin/chromedriver", "-v")
Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"

options = Selenium::WebDriver::Chrome::Options.new
options.add_argument("--headless")
options.add_argument("--window-size=1280,3000")
driver = Selenium::WebDriver.for(:chrome, options: options)

driver.navigate.to("https://rubyci.org")
driver.execute_script(<<END)
let IGNORED_SERVERS = [
// "Debian 10.0(testing) x86_64",
];
let trs = document.getElementsByTagName("tr");
let removed_entries = [];
for (let i = 0; i < trs.length; i++) {
  let tr = trs[i];
  let tds = tr.children;
  for(let j = 0; j < tds.length; j++) {
    let td = tds[j];
    if (td.className == "branch" && td.textContent != "master") {
      removed_entries.push(tr);
    }
    if (td.className == "server" && IGNORED_SERVERS.includes(td.textContent)) {
      removed_entries.push(tr);
    }
  }
}
for (let i = 0; i < removed_entries.length; i++) {
  removed_entries[i].remove();
}
END
elem = driver.find_elements(:tag_name, "table")[0]
loc = elem.location
width  = elem.css_value("width").to_i
height = elem.css_value("height").to_i

driver.save_screenshot("rubyci.orig.png")
crop = "#{ width }x#{ height }+#{ loc.x }+#{ loc.y }"
system("convert", "rubyci.orig.png", "-crop", crop, "rubyci.png")

unless SLACK_API_TOKEN
  puts "SLACK_API_TOKEN is not specified"
  exit
end

filename = Time.now.strftime("rubyci-%Y%m%d.png")
open("rubyci.png", "rb") do |f|
  data = [
    ["token", SLACK_API_TOKEN],
    ["channels", CHANNEL_ID],
    ["filename", filename],
    ["filetype", "png"],
    ["title", filename],
    ["file", f, { filename: filename, content_type: "image/png" } ],
  ]
  uri = URI.parse(FILES_UPLOAD_URI)
  req = Net::HTTP::Post.new(uri.path)
  req.set_form(data, "multipart/form-data")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  http.request(req)
end

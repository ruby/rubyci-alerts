name: rubyci-screenshot

on:
  push:
    branches:
      - master

jobs:
  latest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@master

      - uses: actions/setup-ruby@v1

      - name: Setup bundle
        run: bundle install

      - name: Run the script
        run: bundle exec ruby rubyci-screenshot.rb
        env:
          RUBYCI_SCREENSHOT_SLACK_API_TOKEN: ${{ secrets.RUBYCI_SCREENSHOT_SLACK_API_TOKEN }}
          RUBYCI_SCREENSHOT_SLACK_CHANNEL_ID: ${{ secrets.RUBYCI_SCREENSHOT_SLACK_CHANNEL_ID }}

      - uses: actions/upload-artifact@master
        with:
          name: rubyci-screenshot
          path: rubyci.png

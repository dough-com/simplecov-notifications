require "simplecov/notifications/version"
require 'octokit'

# Ensure we are using a compatible version of SimpleCov
major, minor, patch = SimpleCov::VERSION.scan(/\d+/).first(3).map(&:to_i)
if major < 0 || minor < 9 || patch < 0
  fail "The version of SimpleCov you are using is too old. "\
  "Please update with `gem install simplecov` or `bundle update simplecov`"
end

module SimpleCov
  module Formatter
    class Notifications

      attr_reader :last_report

      def last_report
        @last_report ||= SimpleCov::LastRun.read || {}
      end

      def format(result)
        current_coverage = result.covered_percent
        return unless last_report['result']

        previous_coverage = last_report['result']['covered_percent']

        coverage_data = {
          current_coverage: current_coverage,
          previous_coverage: previous_coverage
        }

        if previous_coverage > current_coverage
          coverage_drop = previous_coverage - current_coverage
          coverage_data[:coverage_drop] = coverage_drop
        end

        send_status coverage_data
      end

      private

      attr_reader :github

      def github
        @github ||= Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
      end

      def send_status(data)
        puts "Sending: #{data}"
        puts "ENV: #{ENV}"

        unless ENV['CIRCLECI']
          puts "Data: #{data}"
          return
        end

        # github.create_status(
        #   owner_repo_name,
        #   ENV['CIRCLE_SHA1'],
        #   coverage_check_status(data),
        #   context: 'simplecov/notifications',
        #   target_url: coverage_report_url,
        #   description: coverage_report_short_description(data)
        # )

        if data[:coverage_drop] && ENV['CI_PULL_REQUEST']
          github.add_comment(
            owner_repo_name,
            pull_request_number,
            coverage_report_description(data)
          )
        end
      end

      def coverage_check_status(data)
        if data[:coverage_drop]
          'failure'
        else
          'success'
        end
      end

      def coverage_report_url
        "https://circleci.com/gh/#{ENV['CIRCLE_PROJECT_USERNAME']}/#{ENV['CIRCLE_PROJECT_REPONAME']}/#{ENV['CIRCLE_BUILD_NUM']}/#{ENV['CIRCLE_ARTIFACTS']}/index.html"
      end

      def coverage_report_short_description(data)
        if data[:coverage_drop]
          "Code coverage dropped by *#{data[:coverage_drop]}%*."
        end
      end

      def coverage_report_description(data)
        if data[:coverage_drop]
          "@#{ENV['CIRCLE_USERNAME']}: Your last push resulted in a *#{data[:coverage_drop]}%* code coverage drop from *#{data[:previous_coverage]}%* to *#{data[:current_coverage]}*."
        end
      end

      def owner_repo_name
        "#{ENV['CIRCLE_PROJECT_USERNAME']}/#{ENV['CIRCLE_PROJECT_REPONAME']}"
      end

      def pull_request_number
        ENV['CI_PULL_REQUEST'][/([\d]+)\/?$/]
      end
    end
  end
end

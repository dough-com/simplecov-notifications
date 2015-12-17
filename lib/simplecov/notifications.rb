require 'simplecov'
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

      class CircleCiBuild
        attr_reader :owner,
          :username, :repo,
          :build, :pull_request,
          :sha1, :artifacts_path

        def initialize(env)
          @owner = env['CIRCLE_PROJECT_USERNAME']
          @username = env['CIRCLE_USERNAME']
          @repo = env['CIRCLE_PROJECT_REPONAME']
          @build = env['CIRCLE_BUILD_NUM']
          @pull_request = env['CI_PULL_REQUEST']
          @sha1 = env['CIRCLE_SHA1']
          @artifacts_path = env['CIRCLE_ARTIFACTS']
        end

        def repo_path
          "#{owner}/#{repo}"
        end

        def artifacts_url
          "https://circleci.com/gh/#{repo_path}/#{build}/#{artifacts_path}/"
        end

        def pull_request
          @pull_request[/([\d]+)\/?$/]
        end

      end

      attr_reader :last_run, :ci, :current_coverage,
       :coverage_drop, :last_coverage
      attr_accessor :coverage_data

      def initialize(env = ENV)
        @ci = CircleCiBuild.new(env)
      end

      def format(result)
        last_run = SimpleCov::LastRun.read
        return unless last_run

        self.current_coverage = result.covered_percent
        self.last_coverage = last_run['result']['covered_percent']


        if last_coverage > current_coverage
          self.coverage_drop = last_coverage - current_coverage
        end

        github.create_status(ci.repo_path, ci.sha1, status,
          context: 'simplecov/notifications',
          target_url: ci.artifacts_url,
          description: status_description
        )

        if ci.pull_request && coverage_drop
          github.add_comment(
            ci.repo_path,
            ci.pull_request,
            comment_description
          )
        end
      end

      private

      attr_writer :current_coverage, :coverage_drop, :last_coverage
      attr_reader :github

      def github
        @github ||= Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
      end

      def status
        if coverage_drop
          'failure'
        else
          'success'
        end
      end

      def status_description
        if coverage_drop
          "Code coverage dropped by #{coverage_drop}%."
        else
          "Current code coverage is at #{current_coverage}%"
        end
      end

      def comment_description
        "@#{ci.username}: Your last push resulted in a *#{coverage_drop}%* code coverage drop from *#{last_coverage}%* to *#{current_coverage}%*."
      end

    end
  end
end

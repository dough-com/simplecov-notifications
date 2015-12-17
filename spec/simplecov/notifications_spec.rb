require 'spec_helper'
require 'pry'

describe SimpleCov::Formatter::Notifications do

  let(:env) do
    {
      'CIRCLECI' => nil,
      'CI_PULL_REQUEST' => '88',
      'CIRCLE_SHA1' => '9fc29099caa165efef809d67fc274abba5c8c8fa',
      'CIRCLE_PROJECT_USERNAME' => 'tastyworks',
      'CIRCLE_PROJECT_REPONAME' => 'order-api',
      'CIRCLE_BUILD_NUM' => '458',
      'CIRCLE_ARTIFACTS' => '0/some-random-path/to/artifacts',
    }
  end

  subject { described_class.new env }

  it 'has a version number' do
    expect(SimpleCov::Formatter::Notifications::VERSION).not_to be nil
  end

  describe 'circle ci build' do
    let(:ci) { described_class::CircleCiBuild.new env }

    it 'has a valid repo path' do
      expect(ci.repo_path).to eq "#{env['CIRCLE_PROJECT_USERNAME']}/#{env['CIRCLE_PROJECT_REPONAME']}"
    end

    it 'has a valid artifacts url' do
      expect(ci.artifacts_url).to include env['CIRCLE_ARTIFACTS']
    end

    it 'has a valid pull request ID' do
      expect(ci.pull_request).to eq env['CI_PULL_REQUEST']
    end
  end

  describe 'github integration' do
    let(:ci) { described_class::CircleCiBuild.new env  }
    let(:github) { instance_double('Octokit::Client') }
    let(:high_coverage_result) { double('SimpleCov::Result', covered_percent: 98) }
    let(:low_coverage_result) { double('SimpleCov::Result', covered_percent: 50) }
    let(:low_coverage_run) do
      { 'result' => { 'covered_percent' => 23 } }
    end

    let(:high_coverage_run) do
      { 'result' => { 'covered_percent' => 100} }
    end

    before do
      allow(subject).to receive(:ci).and_return(ci)
      allow(subject).to receive(:github).and_return(github)
    end

    context 'no previous coverage data exists' do
      it 'will not create a status' do
        expect(github).not_to receive(:create_status)
        subject.format(high_coverage_result)
      end

      it 'will not create a PR comment' do
        expect(github).not_to receive(:add_comment)
        subject.format(high_coverage_result)
      end
    end

    context 'previous coverage data exists' do
      context 'without a PR' do
        before(:each) do
          allow(SimpleCov::LastRun).to receive(:read).and_return(low_coverage_run)
          allow(ci).to receive(:pull_request).and_return(nil)
        end

        it 'will create a status and no comment' do
          expect(github).to receive(:create_status).with(
            ci.repo_path,
            ci.sha1,
            'success',
            context: 'simplecov/notifications',
            target_url: ci.artifacts_url,
            description: "Current code coverage is at #{high_coverage_result.covered_percent}%"
          )

          expect(github).not_to receive(:add_comment)

          subject.format(high_coverage_result)
        end
      end

      context 'with a PR' do
        it 'will create a status' do
          allow(SimpleCov::LastRun).to receive(:read).and_return(low_coverage_run)
          expect(github).to receive(:create_status).with(
            ci.repo_path,
            ci.sha1,
            'success',
            context: 'simplecov/notifications',
            target_url: ci.artifacts_url,
            description: "Current code coverage is at #{high_coverage_result.covered_percent}%"
          )

          subject.format(high_coverage_result)
        end

        it 'will create a comment if there is a coverage drop' do
          allow(SimpleCov::LastRun).to receive(:read).and_return(high_coverage_run)
          expect(github).to receive(:create_status)
          expect(github).to receive(:add_comment).with(
            ci.repo_path,
            ci.pull_request,
            /#{subject.coverage_drop}%/
          )

          subject.format(low_coverage_result)
        end

        it 'will not create a comment if there is no coverage drop' do
          allow(SimpleCov::LastRun).to receive(:read).and_return(low_coverage_run)
          expect(github).to receive(:create_status)
          expect(github).not_to receive(:add_comment)

          subject.format(high_coverage_result)
        end
      end
    end
  end
end

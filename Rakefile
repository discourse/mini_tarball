# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

RSpec::Core::RakeTask.new(:unit) { |t| t.rspec_opts = "--tag ~integration" }

RSpec::Core::RakeTask.new(:integration) { |t| t.rspec_opts = "--tag integration" }

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Fix Ruby files with RuboCop and Syntax Tree"
task :fix do
  sh "bundle exec rubocop -A"
  sh "bundle exec stree write '**/*.rb' '**/*.rake' Gemfile Rakefile *.gemspec"
end

namespace :fixtures do
  desc "Regenerate all test fixtures"
  task :generate do
    require_relative "spec/fixtures/generator"
    FixtureGenerator.new.generate_all
  end

  desc "Verify fixtures are up-to-date (for CI)"
  task :verify do
    require "tmpdir"
    require "fileutils"
    require_relative "spec/fixtures/generator"

    Dir.mktmpdir do |tmpdir|
      # Point generator at temp directory
      temp_fixtures = File.join(tmpdir, "fixtures")
      FileUtils.mkdir_p(temp_fixtures)

      # Generate to temp location
      generator = FixtureGenerator.new
      original_dir = FixtureGenerator::FIXTURES_DIR

      # Temporarily redirect output directories
      FixtureGenerator.send(:remove_const, :FIXTURES_DIR)
      FixtureGenerator.const_set(:FIXTURES_DIR, temp_fixtures)
      FixtureGenerator.send(:remove_const, :HEADERS_DIR)
      FixtureGenerator.const_set(:HEADERS_DIR, File.join(temp_fixtures, "headers"))
      FixtureGenerator.send(:remove_const, :FILES_DIR)
      FixtureGenerator.const_set(:FILES_DIR, File.join(temp_fixtures, "files"))
      FixtureGenerator.send(:remove_const, :ARCHIVES_DIR)
      FixtureGenerator.const_set(:ARCHIVES_DIR, File.join(temp_fixtures, "archives"))

      generator.generate_all

      # Compare generated fixtures with existing ones
      differences = []

      Dir
        .glob(File.join(temp_fixtures, "**/*"))
        .each do |generated_file|
          next if File.directory?(generated_file)

          relative_path = generated_file.sub("#{temp_fixtures}/", "")
          existing_file = File.join(original_dir, relative_path)

          if !File.exist?(existing_file)
            differences << "Missing fixture: #{relative_path}"
          elsif File.binread(generated_file) != File.binread(existing_file)
            differences << "Stale fixture: #{relative_path}"
          end
        end

      if differences.any?
        puts "Fixture verification failed!"
        differences.each { |d| puts "  - #{d}" }
        puts "\nRun 'bundle exec rake fixtures:generate' to update fixtures."
        exit 1
      else
        puts "All fixtures are up-to-date."
      end
    end
  end
end

task default: %i[fix spec]

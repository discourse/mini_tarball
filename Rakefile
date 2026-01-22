# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Fix Ruby files with RuboCop and Syntax Tree"
task :fix do
  sh "bundle exec rubocop -A"
  sh "bundle exec stree write '**/*.rb' '**/*.rake' Gemfile Rakefile *.gemspec"
end

task default: %i[fix spec]

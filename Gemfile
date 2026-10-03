# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# mutant only runs in the MRI `mutation` CI jobs
gem "mutant-rspec", install_if: -> { RUBY_ENGINE == "ruby" }
gem "rake"
gem "reek"
gem "rspec"
gem "rspec-path_matchers"
gem "rubocop-discourse-base"
gem "rubocop-rspec"
gem "rubocop-rake"
gem "rubycritic"
gem "simplecov"
# binary string diffs need 0.19
gem "super_diff", ">= 0.19"
gem "syntax_tree"

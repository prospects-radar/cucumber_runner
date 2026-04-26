require "bundler/setup"
require "cucumber_runner"
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end

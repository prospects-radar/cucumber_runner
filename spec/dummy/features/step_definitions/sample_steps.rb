Given(/^a number (\d+)$/) { |n| @n = n.to_i }
When(/^I add (\d+)$/)    { |n| @n += n.to_i }
Then(/^the result is (\d+)$/) { |n| raise "fail" unless @n == n.to_i }

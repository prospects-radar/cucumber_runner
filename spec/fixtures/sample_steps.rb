Given(/^I am logged in$/) do
  # body
end

When("I visit the {string} page") do |name|
  visit name
end

Then(/^I should see "(.+)"$/) do |text|
  expect(page).to have_content(text)
end

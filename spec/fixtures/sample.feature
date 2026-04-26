@javascript @settings
Feature: Sample CRM
  As a user
  I want a sample feature

  Background:
    Given I am logged in

  @smoke @happy-path
  Scenario: Visit index
    When I visit the page
    Then I should see "Hello"

  @happy-path
  Scenario: Visit detail
    When I click an item
    Then I should see details

Feature: Sample
  Scenario: Pass
    Given a number 2
    When I add 2
    Then the result is 4

  Scenario: Fail
    Given a number 2
    When I add 2
    Then the result is 5

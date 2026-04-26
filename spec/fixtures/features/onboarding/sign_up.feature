Feature: Sign up

  Scenario: Happy path
    Given the sign-up page
    When I submit
    Then I am signed in

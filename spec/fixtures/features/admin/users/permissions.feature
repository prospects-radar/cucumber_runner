Feature: User permissions

  Scenario: Grant admin
    Given a user
    When I grant admin
    Then the user is admin

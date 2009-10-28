Feature: Searching within a single index
  In order to use Thinking Sphinx's core functionality
  A developer
  Should be able to search on a single index

  Scenario: Searching with alternative index
    Given Sphinx is running
    And I am searching on alphas
    When I order by value
    And I search on index alternative_core
    Then I should get 10 results

  Scenario: Searching with default index
    Given Sphinx is running
    And I am searching on alphas
    When I order by value
    And I search on index alpha_core
    Then I should get 10 results

  Scenario: Searching without specified index
    Given Sphinx is running
    And I am searching on alphas
    When I order by value
    Then I should get 10 results



Feature: PATCH request to the /tickets/:TicketID/articles/:ArticleID resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"

  Scenario: update a article
    Given a ticket
    Given a article
    When I update this article
    Then the response code is 200
    When I delete this ticket
    Then the response code is 204
    And the response has no content

  Scenario: update a article with fail mimetype
    Given a ticket
    Given a article
    When I update this article with fail mimetype
    Then the response code is 400
    When I delete this ticket
    Then the response code is 204
    And the response has no content

  Scenario: update a article with fail mimetype (write error)
    Given a ticket
    Given a article
    When I update this article with fail mimetype 2
    Then the response code is 400
    When I delete this ticket
    Then the response code is 204
    And the response has no content


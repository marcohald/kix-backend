 Feature: GET request to the /system/config resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"
        
  Scenario: get the list of existing config
    When I query the collection of config
    Then the response code is 200
    Then the response contains the following SysConfigOption key "ITSMConfigItem::Hook"
        | Value |
        | A#    |
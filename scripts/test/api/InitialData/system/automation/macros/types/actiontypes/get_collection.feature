Feature: GET request to the /system/automation/macros/types/:MacroType/actiontypes resource

  Background: 
    Given the API URL is __BACKEND_API_URL__
    Given the API schema files are located at __API_SCHEMA_LOCATION__
    Given I am logged in as agent user "admin" with password "Passw0rd"

  Scenario: get the list of automation macro type actiontypes
    When I query the collection of automation macro type "Ticket" actiontypes
    Then the response code is 200
    And the response contains 21 items of type "MacroActionType"
    And the response contains the following items of type MacroActionType
      | Name                 | Description                                                                                                | MacroType |
      | ArticleCreate        | Creates an article for a ticket.                                                                           | Ticket    |
      | AssembleObject       | Execute the depending macro if the logical expression is true.                                             | Ticket    |
      | Conditional          | Execute the depending macro if the logical expression is true.                                             | Ticket    |
      | ContactSet           | Sets the contact (and its primary organisation as organisation) of a ticket.                               | Ticket    |
      | CreateReport         | Create a report from a report definition.                                                                  | Ticket    |
      | DynamicFieldSet      | Sets a dynamic field value of a ticket.                                                                    | Ticket    |
      | ExecuteMacro         | Executes a given macro.                                                                                    | Ticket    |
      | ExtractText          | Extract parts of a text via Regular Expressions (RegEx).                                                   | Ticket    |
      | FetchAssetAttributes | Fetch value from attachments and use them to set dynamic fields of ticket.                                 | Ticket    |
      | LockSet              | Sets the lock state of a ticket.                                                                           | Ticket    |
      | Loop                 | Execute a loop over each of the given values. Each value will be the new ObjectID for the depending macro. | Ticket    |
      | OrganisationSet      | Sets the organisation of a ticket.                                                                         | Ticket    |
      | OwnerSet             | Sets the owner of a ticket.                                                                                | Ticket    |
      | PrioritySet          | Sets the priority of a ticket.                                                                             | Ticket    |
      | ResponsibleSet       | Sets the responsible of a ticket.                                                                          | Ticket    |
      | StateSet             | Sets the state of a ticket.                                                                                | Ticket    |
      | TeamSet              | Sets the team of a ticket.                                                                                 | Ticket    |
      | TicketCreate         | Creates an ticket.                                                                                         | Ticket    |
      | TicketDelete         | Deletes a ticket.                                                                                          | Ticket    |
      | TitleSet             | Sets the title of a ticket.                                                                                | Ticket    |
      | TypeSet              | Sets the type of a ticket.                                                                                 | Ticket    |

      
      
      
      
      
      
      
      
      
      
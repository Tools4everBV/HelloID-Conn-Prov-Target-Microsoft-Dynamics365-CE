# HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE](#helloid-conn-prov-target-microsoft-dynamics365-ce)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
    - [⚠️ No delete action possible through reconciliation](#️-no-delete-action-possible-through-reconciliation)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [API Limitations](#api-limitations)
    - [Manager correlation](#manager-correlation)
    - [Bookable resource](#bookable-resource)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE_ is a _target_ connector. _Microsoft-Dynamics365-CE_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                          | Remarks                    |
| ----------------------------------------- | --------- | -------------------------------- | -------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, | No Delete action           |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke          | Roles and BookableResource |
| **Resources**                             | ❌         | -                                |                            |
| **Entitlement Import: Accounts**          | ✅         | -                                |                            |
| **Entitlement Import: Permissions**       | ✅         | -                                |                            |
| **Governance Reconciliation Resolutions** | ✅⚠️        | -                                |                            |


### ⚠️ No delete action possible through reconciliation
Because there is no delete action available, deleting users by means of reconciliation is not possible.

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE/refs/heads/main/Icon.png
```

### Requirements

- **Connection Settings** Valid connection settings to connect to the API.

### Connection settings

The following settings are required to connect to the API.

| Setting       | Description                        | Mandatory |
| ------------- | ---------------------------------- | --------- |
| client_id     | The UserName to connect to the API | Yes       |
| client_secret | The Password to connect to the API | Yes       |
| tenant_id     | The TenantId to connect to the API | Yes       |
| BaseUrl       | The URL to the API                 | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Microsoft-Dynamics365-CE_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `hda_personnelnumber`             |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `systemuserid` property from _Microsoft-Dynamics365-CE_

## Remarks

### API Limitations
- **Role assignment for disabled accounts**: By default, the API does not support assigning roles to disabled accounts. If this functionality is required, it can be enabled by turning on the organization setting AllowRoleAssignmentOnDisabledUsers.

- **Account object conversion**: Because some properties differ between the GET response and the POST/PATCH requests, some scripts implement a hardcoded ConvertTo-HelloIDAccountObject function to ensure the account data is mapped correctly.

### Manager correlation
- **Manager reference**: When creating a user, the connector populates the parentsystemuserid property with the Microsoft Dynamics CE ID of the user's manager. To retrieve this ID, the create and update scripts perform an additional GET request based on the manager's reference or the external ID of the manager.

### Bookable resource
- **Static permission**: A bookable resource allows a user account to be scheduled and enables hours to be registered. A user can have only one bookable resource. To enforce this through HelloID, the bookable resource is configured as a static permission.

- **Bookable resource deletion**: To delete a bookableResource, the ID of the bookable resource linked to the account is required. To retrieve this ID, the revoke script performs an additional GET request.


## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                                                        | HTTP Method | Description                                             |
| ------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------- |
| `/api/data/v9.2/systemusers`                                                    | GET, POST   | Retrieve users (supports OData filters and pagination). |
| `/api/data/v9.2/systemusers(:id)`                                               | PATCH       | Update user (enable/disable or patch fields).           |
| `/api/data/v9.2/systemusers(:userId)/systemuserroles_association/$ref`          | POST        | Assign a role to a user.                                |
| `/api/data/v9.2/systemusers(:userId)/systemuserroles_association(:roleId)/$ref` | DELETE      | Revoke a role from a user.                              |
| `/api/data/v9.2/systemuserrolescollection`                                      | GET         | Retrieve user-role mappings.                            |
| `/api/data/v9.2/roles`                                                          | GET         | Retrieve roles.                                         |
| `/api/data/v9.2/bookableresources`                                              | GET, POST   | Retrieve or create Bookable Resources.                  |
| `/api/data/v9.2/bookableresources(:id)`                                         | DELETE      | Delete a Bookable Resource by id   .                    |
| `https://login.microsoftonline.com/:tenant_id/oauth2/token`                     | POST        | Acquire OAuth2 token.                                   |

### API documentation

The API documentation is **NOT** publicly available for this connector. Please refer to the Microsoft documentation for more information on the Dynamics 365 Finance and Operations API [here](https://learn.microsoft.com/en-us/odata/).

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

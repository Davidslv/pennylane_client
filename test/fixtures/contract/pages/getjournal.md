---
updatedAt: 2026-07-08T07:28:10.000Z
agentTools:
  projectIndex: https://pennylane.readme.io/llms.txt
---

# Retrieve a journal

Retrieve a journal

> ℹ️
> This endpoint requires one of the following scopes: `journals:readonly`, `journals:all`

<br />

# OpenAPI definition

```json
{
  "openapi": "3.0.1",
  "info": {
    "title": "Company V2",
    "version": "2.0"
  },
  "servers": [
    {
      "url": "https://app.pennylane.com"
    }
  ],
  "paths": {
    "/api/external/v2/journals/{id}": {
      "get": {
        "operationId": "getJournal",
        "summary": "Retrieve a journal",
        "description": "Retrieve a journal",
        "tags": [
          "Journals"
        ],
        "security": [
          {
            "oauth2": [
              "journals:readonly",
              "journals:all"
            ]
          }
        ],
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "schema": {
              "type": "integer"
            },
            "required": true,
            "example": 42
          }
        ],
        "responses": {
          "200": {
            "description": "Returns a journal",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "label": {
                      "type": "string"
                    },
                    "id": {
                      "type": "integer"
                    }
                  },
                  "required": [
                    "label",
                    "id"
                  ]
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "securitySchemes": {
      "oauth2": {
        "type": "oauth2"
      }
    }
  }
}
```

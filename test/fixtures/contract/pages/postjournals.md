---
updatedAt: 2026-07-08T07:28:10.000Z
---

# Create a journal

Create a journal. The body looks like this:
```
{ "code": "HA", "label": "Achats" }
```

# OpenAPI definition

````json
{
  "openapi": "3.0.1",
  "paths": {
    "/api/external/v2/journals": {
      "post": {
        "operationId": "postJournals",
        "summary": "Create a journal",
        "description": "Create a journal. The body looks like this:\n```\n{ \"code\": \"HA\", \"label\": \"Achats\" }\n```",
        "tags": [
          "Journals"
        ],
        "security": [
          {
            "oauth2": [
              "journals:all"
            ]
          }
        ],
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "label": {
                    "type": "string"
                  },
                  "code": {
                    "type": "string"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Journal created"
          }
        }
      }
    }
  }
}
````

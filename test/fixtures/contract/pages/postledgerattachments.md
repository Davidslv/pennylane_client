---
updatedAt: 2026-07-08T07:28:10.000Z
---

# Upload a file

Upload a file to attach to a ledger entry.

# OpenAPI definition

```json
{
  "openapi": "3.0.1",
  "paths": {
    "/api/external/v2/ledger_attachments": {
      "parameters": [
        {
          "name": "X-Request-Source",
          "in": "header",
          "schema": {
            "type": "string"
          }
        }
      ],
      "post": {
        "operationId": "postLedgerAttachments",
        "summary": "Upload a file",
        "description": "Upload a file to attach to a ledger entry.",
        "deprecated": true,
        "tags": [
          "Ledger Attachments"
        ],
        "security": [
          {
            "oauth2": [
              "ledger"
            ]
          },
          {
            "oauth2": [
              "ledger",
              "file_attachments:all"
            ]
          }
        ],
        "requestBody": {
          "content": {
            "multipart/form-data": {
              "schema": {
                "type": "object",
                "properties": {
                  "file": {
                    "type": "string",
                    "format": "binary"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "File uploaded"
          }
        }
      }
    }
  }
}
```

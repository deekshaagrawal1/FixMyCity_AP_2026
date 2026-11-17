# CP2 — Physical ER diagram

This diagram describes **the runnable 11-table schema**, including its two documented compatibility redundancies. The separate fully normalized logical endpoint is in [CP1, sections 6–9](01_normalization.md). IDs are application-supplied strings; timestamp attributes are integer UTC epoch milliseconds. `PK` is primary key, `UK` is unique key and `FK` is foreign key. `Support` has a composite PK.

```mermaid
erDiagram
    Department |o..o{ User : employs_officers
    Department ||..o{ Category : default_route
    Department ||..o{ Complaint : responsible_for
    Category ||..o{ Complaint : classifies
    User ||..o{ Complaint : citizen_reports
    User |o..o{ Complaint : officer_assigned
    User ||..o{ Session : has
    Complaint ||..o{ Image : evidence
    Complaint ||..o{ Video : evidence
    Complaint ||..o{ History : timeline
    User |o..o{ History : actor
    User ||--o{ Support : gives
    Complaint ||--o{ Support : receives
    User ||..o{ Feedback : author
    Complaint ||..o{ Feedback : resolution_cycles
    User ||..o{ Notification : recipient
    Complaint |o..o{ Notification : optional_subject

    Department {
        string id PK
        string name UK
        string description
    }
    User {
        string id PK
        string name
        string email UK
        string passwordHash
        string role "CITIZEN, OFFICER, ADMIN"
        string departmentId FK "nullable; required for officer"
        int createdAt
    }
    Category {
        string id PK
        string name UK
        string icon
        string departmentId FK "default route"
    }
    Complaint {
        string id PK
        string title
        string description
        string address
        string ward
        string city
        float latitude "nullable legacy metadata"
        float longitude "nullable legacy metadata"
        string priority "NORMAL, URGENT"
        string status
        string citizenId FK
        string categoryId FK
        string departmentId FK "actual route"
        string officerId FK "nullable"
        int createdAt
        int updatedAt
        int dueAt
        int resolvedAt "nullable"
        int escalatedAt "nullable"
    }
    Session {
        string id PK
        string userId FK
        string csrf
        int expiresAt
    }
    Image {
        string id PK
        string url
        string kind "REPORT, RESOLUTION"
        string complaintId FK
        int createdAt
    }
    Video {
        string id PK
        string url
        string mimeType
        int sizeBytes
        string complaintId FK
        int createdAt
    }
    History {
        string id PK
        string complaintId FK
        string actorId FK "nullable system actor"
        string status
        string note
        int createdAt
    }
    Support {
        string userId PK, FK
        string complaintId PK, FK
        int createdAt
    }
    Feedback {
        string id PK
        string complaintId FK
        string userId FK "must equal reporter"
        int rating "1 to 5"
        string comment
        int reopened "0 or 1"
        int createdAt
    }
    Notification {
        string id PK
        string userId FK
        string complaintId FK "nullable general message"
        string message
        int readAt "nullable means unread"
        int createdAt
    }
```

Cardinality details:

- A department has zero or more officers/categories/complaints. Users have zero or one department; officers must have exactly one. Non-officers have none in this educational DDL.
- Every complaint has one citizen, category and responsible department, with zero or one assigned officer. Assignment can differ from the category's default department, but the chosen officer must belong to the responsible department.
- Complaint child collections are all zero-to-many, including feedback across reopen cycles. Support resolves the user–complaint many-to-many relationship; duplicate pairs are forbidden.
- A history actor can be absent for system escalation. A notification can be unrelated to a complaint, but always has one recipient.
- Current status uses a checked string domain: `SUBMITTED`, `ASSIGNED`, `IN_PROGRESS`, `RESOLVED`, `CLOSED`, `REOPENED`. There is no physical Status table. Full transition authorization, photo requirements and history append behavior belong to the transaction/service layer.

Delete/update behavior and added constraints are documented in [schema alignment](../docs/schema-alignment.md). No map or heatmap entity exists.

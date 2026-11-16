CP1 — Normalization and functional dependencies
1. Scope and source of truth
Fix My City lets citizens report civic issues, officers work assigned cases, and administrators manage routing, staffing, overdue cases, and metrics. This checkpoint is a separate educational database, based on a read-only inspection of the website's actual prisma/schema.prisma, its two migrations, and complaint/admin services on 16 November 2026. No website files or database records are imported or modified.

The database dialect is SQLite, matching the actual Prisma datasource. The implemented entities are User, Session, Department, Category, Complaint, Image, Video, History, Support, Feedback, and Notification. Officers are User rows with role='OFFICER'; there is no separate officer-profile entity. Escalation is Complaint.escalatedAt plus history/notifications; there is no escalation-level or audit-log table in the inspected implementation.

Location is entered as address, ward, and city. The two optional coordinate columns are retained only for source-model compatibility. There is no interactive map, heatmap, spatial index, or spatial query.
2. Business rules that determine dependencies
1. Each user has one unique ID, one unique email, one role, and at most one department. Officers must belong to a department. A department has a unique name.
2. Each complaint has exactly one reporting citizen and one category. Its ID identifies its contents, routing, current state, and deadlines.
3. A category has a default routing department. A complaint has an actual responsible department. Administrators can reroute a complaint: categoryId -> Complaint.departmentId is not a valid FD. It would be an incorrect normalization step to remove the complaint's routing department just because a category has a default.
4. An assigned officer must belong to the complaint's responsible department. This is a conditional cross-table rule; it matters to the compatibility exceptions below.
5. A user can support a particular complaint only once. The pair (userId, complaintId) identifies one support event.
6. Images, videos, timeline events, feedback events and notifications can repeat. Their IDs identify individual events, not the complaint ID alone.
7. Only the reporting citizen gives feedback. The same complaint may be resolved, reopened, resolved again, and receive another feedback event. complaintId is not a feedback key.
8. Current status is a writable snapshot; history is a sequence of events. Several history rows can have the same status, including escalation events. (complaintId, status) and (complaintId, createdAt) are not candidate keys.
9. No FD from ward to city, address to ward, name to person, or status to deadline is assumed. Similar names/addresses and timestamps can repeat. Mumbai is a fixture value, not a schema-wide FD.
An FD X -> Y means that in every valid relation instance, rows equal on X must be equal on Y. A primary key is one selected candidate key; a surrogate ID does not automatically remove transitive dependencies.
3. Unnormalized starting point and anomalies
An illustrative paper register might contain:
ComplaintRegister(
  complaintId, title, description, address, ward, city,
  reporterId, reporterName, reporterEmail, reporterRole,
  categoryId, categoryName, categoryIcon, defaultDepartmentId,
  responsibleDepartmentId, responsibleDepartmentName,
  officerId, officerName, officerDepartmentId,
  status, priority, createdAt, updatedAt, dueAt, resolvedAt, escalatedAt,
  images=[...], videos=[...], supporters=[...], history=[...], feedback=[...]
)
This is UNF: collections are repeating groups, and copying each complaint for every supporter/image/history combination would multiply unrelated events. A report with 2 images and 3 supporters would produce 6 flattened rows before even adding history.
- Update anomaly: changing a citizen's email or department name requires editing every copied register row. Partial updates disagree.
- Insertion anomaly: a new department, category or officer cannot be recorded until a complaint exists if everything lives in the register.
- Deletion anomaly: deleting the last complaint for a department can erase its description and officer details.
- Counting anomaly: joining supporters and images directly inflates counts. Normalized storage prevents repeated facts; CP3 also aggregates independent child tables separately.
4. First normal form (1NF)
Use one scalar value per attribute and identifiable tuples. Store one image/video/history/feedback/notification event per row. Store one support relationship per pair of IDs; do not store comma-separated supporter IDs or arrays inside a complaint column.

For a focused flattened example, consider:
ReportSupport1(
 complaintId, supporterId, title, status, citizenId,
 reporterName, reporterEmail, supporterName, supportedAt
)
Key: (complaintId, supporterId)
Relevant FDs include:
complaintId -> title, status, citizenId
citizenId -> reporterName, reporterEmail
supporterId -> supporterName
(complaintId, supporterId) -> supportedAt
The example is atomic, but still repeats report and user facts.
5. Second normal form (2NF)
A relation is in 2NF if it is in 1NF and every non-prime attribute depends on the whole of every candidate key. In ReportSupport1, title/status depend only on complaintId, and supporterName depends only on supporterId, proper subsets of the composite key.

Decompose into:
Complaint2(complaintId PK, title, status, citizenId, reporterName, reporterEmail, ...)
Support2(userId PK/FK, complaintId PK/FK, createdAt)
User2(userId PK, name, email, role, ...)
Support2 now stores only the fact that depends on both IDs: when this user supported this complaint. Its composite primary key enforces the natural uniqueness rule. The other relations use single-attribute candidate keys, so no partial-key dependency remains, but Complaint2 still contains transitive dependencies.
6. Third normal form (3NF) — logical endpoint
For every nontrivial FD X -> A, 3NF requires X to be a superkey or A to be a prime attribute. Examples of remaining transitive chains are:
complaintId -> citizenId -> reporterName, reporterEmail
complaintId -> categoryId -> categoryName, categoryIcon, defaultDepartmentId
complaintId -> responsibleDepartmentId -> responsibleDepartmentName
Move descriptive facts to the entity whose key determines them. The fully normalized logical endpoint is the following. Attributes omitted behind ... are listed in the physical inventory below; the two intentional differences are spelled out in section 8.
User3(id PK, email UNIQUE, name, passwordHash, role, departmentId FK, createdAt)
Department3(id PK, name UNIQUE, description)
Category3(id PK, name UNIQUE, icon, departmentId FK)
ComplaintCore3(id PK, title, description, address, ward, city, latitude, longitude,
               priority, status, citizenId FK, categoryId FK, departmentId FK,
               createdAt, updatedAt, dueAt, resolvedAt, escalatedAt)
Assignment3(complaintId PK/FK, officerId FK)
Session3(id PK, userId FK, csrf, expiresAt)
Image3(id PK, url, kind, complaintId FK, createdAt)
Video3(id PK, url, mimeType, sizeBytes, complaintId FK, createdAt)
History3(id PK, complaintId FK, actorId FK nullable, status, note, createdAt)
Support3(userId PK/FK, complaintId PK/FK, createdAt)
Feedback3(id PK, complaintId FK, rating, comment, reopened, createdAt)
Notification3(id PK, userId FK, complaintId FK nullable, message, readAt, createdAt)
Feedback3 obtains the feedback author by joining its complaint to the reporter; it does not repeat the owner. Assignment3 isolates the optional officer assignment from the complaint's routing department. Each logical relation's nontrivial intrinsic FDs has a candidate key as determinant, under the stated rules. Cross-relation officer membership must still be validated; normalization alone cannot enforce that rule.
7. Physical entity, candidate-key and FD inventory
The executable DDL deliberately keeps the website's 11 table names and all original column names. Let all mean every other attribute in that row.
Physical relation	Candidate keys	Principal FDs and attributes
User	id; email	each candidate key -> all: name, passwordHash, role, departmentId, createdAt
Department	id; name	each candidate key -> description and the other key
Category	id; name	each candidate key -> icon, departmentId and the other key
Complaint	id	id -> title, description, address, ward, city, latitude, longitude, priority, status, citizenId, categoryId, departmentId, officerId, createdAt, updatedAt, dueAt, resolvedAt, escalatedAt
Session	id	id -> userId, csrf, expiresAt
Image	id	id -> url, kind, complaintId, createdAt
Video	id	id -> url, mimeType, sizeBytes, complaintId, createdAt
History	id	id -> complaintId, actorId, status, note, createdAt
Support	(userId, complaintId)	whole pair -> createdAt; neither component alone identifies a support
Feedback	id	id -> complaintId, userId, rating, comment, reopened, createdAt; also complaintId -> userId under owner-only feedback
Notification	id	id -> userId, complaintId, message, readAt, createdAt


There is no unique constraint on complaint title/address, officer name, session user, feedback complaint, or event timestamp. These are not candidate keys. Role/status/priority/kind values are checked domains, not extra entities with unimplemented relationships.
8. Explicit compatibility exceptions in CP2
Do not describe the entire physical website-compatible schema as strictly 3NF. The logical endpoint above reaches 3NF; the runnable operational schema retains two redundancies from the website:
- Feedback.userId repeats the reporter. Because complaintId -> userId and complaintId is not a feedback key, this is a genuine 3NF violation. It is retained for the original model's feedback-author relationship; triggers validate author ownership on INSERT and UPDATE, and the complaint reporter is immutable. A strictly normalized variant removes this column and joins Complaint.citizenId as shown in Feedback3.
- Complaint.officerId and Complaint.departmentId are both stored. For the assigned subset, officer membership fixes the department, creating a conditional transitive redundancy. NULL/unassigned rows mean this is not an ordinary FD over the whole SQL table. ComplaintCore3 plus optional Assignment3 is the normalized logical alternative. CP2 retains the original layout and enforces consistency with assignment and membership triggers.
Other operational snapshots, notably current status versus the latest history event, introduce potential cross-relation consistency issues. This is separate from claiming a non-key FD within one relation. Status writes should change the complaint, append history, and create notifications in one transaction. The CP3 example demonstrates that contract. The schema does not auto-create history for arbitrary SQL writes or enforce the full state machine.

These exceptions make the submitted SQL recognizable against the real application while making the academic normalization result and its limits explicit. No renaming or migration is applied to the website.
9. Losslessness and dependency preservation
For splitting complaint reporter details into User and Complaint, the intersection is the reporter key; that key determines the entire user projection. Their natural join is lossless for valid mandatory references. The same argument applies to category and department descriptive facts. Their key-based FDs remain enforceable inside their respective tables; foreign keys retain the references.

Splitting ReportSupport1 first on complaintId and then on supporterId preserves complaintId -> report facts, supporterId -> user facts, and (complaintId,supporterId) -> supportedAt. Shared determinants are keys of the extracted relations. Thus the illustrated FD-based decomposition is dependency-preserving and lossless.

For the logical optional assignment split, reconstruct with ComplaintCore3 LEFT JOIN Assignment3 ON complaintId=id; the assignment primary key allows at most one matching row. Required complaint facts remain even without an officer. The conditional officer/department rule is not enforceable by keys in either component alone: a cross-table check is still necessary. Similarly, reconstruct feedback authors by joining a mandatory complaint FK. We do not claim all cross-table business rules follow from 3NF or that joining all independent one-to-many event tables produces one row per complaint.

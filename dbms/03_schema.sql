-- CP2 | SQLite 3.35+ | NEW EMPTY DATABASE ONLY; deliberately no DROP statements.
-- UTC Unix epoch milliseconds for every *At column; caller supplies TEXT IDs.
-- Educational constraints/indexes supplement the inspected Prisma model.
PRAGMA foreign_keys = ON;
BEGIN;

CREATE TABLE "Department" (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE CHECK(length(trim(name)) > 0),
  description TEXT NOT NULL
);
CREATE TABLE "User" (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL CHECK(length(trim(name)) > 0),
  email TEXT NOT NULL UNIQUE CHECK(length(trim(email)) > 0),
  passwordHash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'CITIZEN' CHECK(role IN ('CITIZEN','OFFICER','ADMIN')),
  departmentId TEXT REFERENCES Department(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0),
  CHECK((role='OFFICER' AND departmentId IS NOT NULL) OR
        (role IN ('CITIZEN','ADMIN') AND departmentId IS NULL))
);
CREATE TABLE "Category" (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  icon TEXT NOT NULL,
  departmentId TEXT NOT NULL REFERENCES Department(id) ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE TABLE "Complaint" (
  id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL CHECK(length(trim(title)) > 0),
  description TEXT NOT NULL,
  address TEXT NOT NULL CHECK(length(trim(address)) > 0),
  ward TEXT NOT NULL,
  city TEXT NOT NULL,
  -- Optional legacy coordinates retained for model alignment; no map/heatmap.
  latitude REAL,
  longitude REAL,
  priority TEXT NOT NULL DEFAULT 'NORMAL' CHECK(priority IN ('NORMAL','URGENT')),
  status TEXT NOT NULL DEFAULT 'SUBMITTED'
    CHECK(status IN ('SUBMITTED','ASSIGNED','IN_PROGRESS','RESOLVED','CLOSED','REOPENED')),
  citizenId TEXT NOT NULL REFERENCES User(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  categoryId TEXT NOT NULL REFERENCES Category(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  -- Actual responsible department; may differ from category's default routing.
  departmentId TEXT NOT NULL REFERENCES Department(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  officerId TEXT REFERENCES User(id) ON DELETE SET NULL ON UPDATE CASCADE,
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0),
  updatedAt INTEGER NOT NULL CHECK(typeof(updatedAt)='integer' AND updatedAt >= createdAt),
  dueAt INTEGER NOT NULL CHECK(typeof(dueAt)='integer' AND dueAt >= createdAt),
  resolvedAt INTEGER CHECK(resolvedAt IS NULL OR
    (typeof(resolvedAt)='integer' AND resolvedAt >= createdAt)),
  escalatedAt INTEGER CHECK(escalatedAt IS NULL OR
    (typeof(escalatedAt)='integer' AND escalatedAt >= createdAt)),
  CHECK((latitude IS NULL AND longitude IS NULL) OR
        (latitude IS NOT NULL AND longitude IS NOT NULL AND
         typeof(latitude) IN ('integer','real') AND typeof(longitude) IN ('integer','real') AND
         latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)),
  CHECK(status NOT IN ('ASSIGNED','IN_PROGRESS','RESOLVED','CLOSED','REOPENED') OR officerId IS NOT NULL),
  CHECK((status IN ('RESOLVED','CLOSED') AND resolvedAt IS NOT NULL) OR
        (status NOT IN ('RESOLVED','CLOSED') AND resolvedAt IS NULL))
);
CREATE TABLE "Session" (
  id TEXT NOT NULL PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES User(id) ON DELETE CASCADE ON UPDATE CASCADE,
  csrf TEXT NOT NULL,
  expiresAt INTEGER NOT NULL CHECK(typeof(expiresAt)='integer' AND expiresAt >= 0)
);
CREATE TABLE "Image" (
  id TEXT NOT NULL PRIMARY KEY,
  url TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'REPORT' CHECK(kind IN ('REPORT','RESOLUTION')),
  complaintId TEXT NOT NULL REFERENCES Complaint(id) ON DELETE CASCADE ON UPDATE CASCADE,
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0)
);
CREATE TABLE "Video" (
  id TEXT NOT NULL PRIMARY KEY,
  url TEXT NOT NULL,
  mimeType TEXT NOT NULL CHECK(mimeType IN ('video/mp4','video/webm')),
  sizeBytes INTEGER NOT NULL CHECK(typeof(sizeBytes)='integer' AND sizeBytes > 0),
  complaintId TEXT NOT NULL REFERENCES Complaint(id) ON DELETE CASCADE ON UPDATE CASCADE,
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0)
);
CREATE TABLE "History" (
  id TEXT NOT NULL PRIMARY KEY,
  complaintId TEXT NOT NULL REFERENCES Complaint(id) ON DELETE CASCADE ON UPDATE CASCADE,
  actorId TEXT REFERENCES User(id) ON DELETE SET NULL ON UPDATE CASCADE,
  status TEXT NOT NULL CHECK(status IN ('SUBMITTED','ASSIGNED','IN_PROGRESS','RESOLVED','CLOSED','REOPENED')),
  note TEXT NOT NULL,
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0)
);
CREATE TABLE "Support" (
  userId TEXT NOT NULL REFERENCES User(id) ON DELETE CASCADE ON UPDATE CASCADE,
  complaintId TEXT NOT NULL REFERENCES Complaint(id) ON DELETE CASCADE ON UPDATE CASCADE,
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0),
  PRIMARY KEY(userId, complaintId)
);
CREATE TABLE "Feedback" (
  id TEXT NOT NULL PRIMARY KEY,
  complaintId TEXT NOT NULL REFERENCES Complaint(id) ON DELETE CASCADE ON UPDATE CASCADE,
  userId TEXT NOT NULL REFERENCES User(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  rating INTEGER NOT NULL CHECK(typeof(rating)='integer' AND rating BETWEEN 1 AND 5),
  comment TEXT NOT NULL,
  reopened INTEGER NOT NULL DEFAULT 0 CHECK(typeof(reopened)='integer' AND reopened IN (0,1)),
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0)
  -- Multiple feedback rows per complaint are intentional: reopen/resolve cycles.
);
CREATE TABLE "Notification" (
  id TEXT NOT NULL PRIMARY KEY,
  userId TEXT NOT NULL REFERENCES User(id) ON DELETE CASCADE ON UPDATE CASCADE,
  complaintId TEXT REFERENCES Complaint(id) ON DELETE CASCADE ON UPDATE CASCADE,
  message TEXT NOT NULL,
  readAt INTEGER CHECK(readAt IS NULL OR (typeof(readAt)='integer' AND readAt >= createdAt)),
  createdAt INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)*1000)
    CHECK(typeof(createdAt)='integer' AND createdAt >= 0)
);

-- Cross-table business constraints cannot be expressed as SQLite CHECK subqueries.
CREATE TRIGGER complaint_roles_insert BEFORE INSERT ON Complaint
BEGIN
  SELECT RAISE(ABORT,'Reporter must be a citizen') WHERE NOT EXISTS
    (SELECT 1 FROM User WHERE id=NEW.citizenId AND role='CITIZEN');
  SELECT RAISE(ABORT,'Assignee must be an officer in the responsible department')
    WHERE NEW.officerId IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM User WHERE id=NEW.officerId AND role='OFFICER' AND departmentId=NEW.departmentId);
END;
CREATE TRIGGER complaint_roles_update BEFORE UPDATE OF citizenId,officerId,departmentId ON Complaint
BEGIN
  SELECT RAISE(ABORT,'Reporter is immutable') WHERE NEW.citizenId IS NOT OLD.citizenId;
  SELECT RAISE(ABORT,'Assignee must be an officer in the responsible department')
    WHERE NEW.officerId IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM User WHERE id=NEW.officerId AND role='OFFICER' AND departmentId=NEW.departmentId);
END;
CREATE TRIGGER user_role_assignment_guard BEFORE UPDATE OF role,departmentId ON User
BEGIN
  SELECT RAISE(ABORT,'Reporting users must remain citizens')
    WHERE NEW.role!='CITIZEN' AND EXISTS(SELECT 1 FROM Complaint WHERE citizenId=OLD.id);
  SELECT RAISE(ABORT,'Reassign complaints before changing officer membership')
    WHERE EXISTS(SELECT 1 FROM Complaint WHERE officerId=OLD.id AND
      (NEW.role!='OFFICER' OR NEW.departmentId IS NOT departmentId));
END;
CREATE TRIGGER feedback_owner_insert BEFORE INSERT ON Feedback
BEGIN
  SELECT RAISE(ABORT,'Only the reporter can give feedback') WHERE NOT EXISTS
    (SELECT 1 FROM Complaint WHERE id=NEW.complaintId AND citizenId=NEW.userId);
END;
CREATE TRIGGER feedback_owner_update BEFORE UPDATE OF userId,complaintId ON Feedback
BEGIN
  SELECT RAISE(ABORT,'Only the reporter can give feedback') WHERE NOT EXISTS
    (SELECT 1 FROM Complaint WHERE id=NEW.complaintId AND citizenId=NEW.userId);
END;

-- Original query paths, extended with FK-child and dashboard indexes.
CREATE INDEX Session_expiresAt_idx ON Session(expiresAt);
CREATE INDEX Session_userId_idx ON Session(userId);
CREATE INDEX User_departmentId_role_idx ON User(departmentId,role);
CREATE INDEX Category_departmentId_idx ON Category(departmentId);
CREATE INDEX Complaint_status_city_idx ON Complaint(status,city);
CREATE INDEX Complaint_officerId_idx ON Complaint(officerId);
CREATE INDEX Complaint_dueAt_idx ON Complaint(dueAt);
CREATE INDEX Complaint_citizen_created_idx ON Complaint(citizenId,createdAt DESC,id);
CREATE INDEX Complaint_officer_status_created_idx ON Complaint(officerId,status,createdAt DESC,id);
CREATE INDEX Complaint_officer_active_created_idx ON Complaint(officerId,createdAt DESC,id)
  WHERE status NOT IN ('RESOLVED','CLOSED');
CREATE INDEX Complaint_department_status_idx ON Complaint(departmentId,status);
CREATE INDEX Complaint_categoryId_idx ON Complaint(categoryId);
CREATE INDEX Complaint_active_due_idx ON Complaint(dueAt,id)
  WHERE status NOT IN ('RESOLVED','CLOSED');
CREATE INDEX Image_complaintId_idx ON Image(complaintId);
CREATE INDEX Video_complaintId_idx ON Video(complaintId);
CREATE INDEX History_complaint_created_idx ON History(complaintId,createdAt,id);
CREATE INDEX History_actorId_idx ON History(actorId);
CREATE INDEX Support_complaintId_idx ON Support(complaintId);
CREATE INDEX Feedback_complaint_created_idx ON Feedback(complaintId,createdAt DESC,id);
CREATE INDEX Feedback_userId_idx ON Feedback(userId);
CREATE INDEX Notification_userId_createdAt_idx ON Notification(userId,createdAt DESC,id);
CREATE INDEX Notification_complaintId_idx ON Notification(complaintId);
CREATE INDEX Notification_unread_idx ON Notification(userId,createdAt DESC,id) WHERE readAt IS NULL;
COMMIT;

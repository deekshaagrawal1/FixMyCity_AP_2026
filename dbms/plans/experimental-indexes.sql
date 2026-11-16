-- Baseline drops these five indexes; after recreates them.
CREATE INDEX Complaint_citizen_created_idx ON Complaint(citizenId,createdAt DESC,id);
CREATE INDEX Complaint_officer_status_created_idx ON Complaint(officerId,status,createdAt DESC,id);
CREATE INDEX Complaint_officer_active_created_idx ON Complaint(officerId,createdAt DESC,id)
  WHERE status NOT IN ('RESOLVED','CLOSED');
CREATE INDEX Complaint_active_due_idx ON Complaint(dueAt,id)
  WHERE status NOT IN ('RESOLVED','CLOSED');
CREATE INDEX Notification_unread_idx ON Notification(userId,createdAt DESC,id) WHERE readAt IS NULL;

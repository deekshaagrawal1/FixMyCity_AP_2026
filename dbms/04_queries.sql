-- CP3 | SQLite | 20 read-only, independently executable, parameterized queries.
-- Defaults/bindings: scripts/common.py PARAMS; run_queries.py uses a read-only connection.
-- Times are UTC epoch milliseconds; as_of is an explicit reproducible reporting cutoff.
-- Caller authorization is required: a bound citizen/officer ID is not authentication.

-- name: Q01
-- Citizen: own complaints, latest first, stable pagination. :citizen_id :limit :offset
SELECT id,title,status,priority,departmentId,officerId,createdAt,dueAt
FROM Complaint WHERE citizenId=:citizen_id
ORDER BY createdAt DESC,id LIMIT :limit OFFSET :offset;

-- name: Q02
-- Officer: assigned active work. :officer_id :limit :offset
SELECT id,title,status,priority,departmentId,createdAt,dueAt
FROM Complaint WHERE officerId=:officer_id AND status NOT IN ('RESOLVED','CLOSED')
ORDER BY createdAt DESC,id LIMIT :limit OFFSET :offset;

-- name: Q03
-- Admin: oldest unassigned reports in city. :city :limit :offset
SELECT c.id,c.title,c.status,c.createdAt,d.name AS department_name,k.name AS category_name
FROM Complaint c JOIN Department d ON d.id=c.departmentId JOIN Category k ON k.id=c.categoryId
WHERE c.officerId IS NULL AND c.status='SUBMITTED' AND c.city=:city
ORDER BY c.createdAt,c.id LIMIT :limit OFFSET :offset;

-- name: Q04
-- Authorized detail: no password/session fields, independent counts avoid join multiplication.
SELECT c.id,c.title,c.description,c.address,c.ward,c.city,c.priority,c.status,c.createdAt,c.updatedAt,c.dueAt,
       c.resolvedAt,c.escalatedAt,k.name AS category_name,d.name AS department_name,u.name AS officer_name,
       (SELECT count(*) FROM Support s WHERE s.complaintId=c.id) AS support_count,
       (SELECT count(*) FROM Image i WHERE i.complaintId=c.id) AS image_count,
       (SELECT count(*) FROM Video v WHERE v.complaintId=c.id) AS video_count
FROM Complaint c JOIN Category k ON k.id=c.categoryId JOIN Department d ON d.id=c.departmentId
LEFT JOIN User u ON u.id=c.officerId WHERE c.id=:complaint_id;

-- name: Q05
-- Status timeline: preserve system events without an actor. Tie-break with event ID.
SELECT h.id,h.status,h.note,h.createdAt,COALESCE(u.name,'System') AS actor_name
FROM History h LEFT JOIN User u ON u.id=h.actorId
WHERE h.complaintId=:complaint_id ORDER BY h.createdAt,h.id;

-- name: Q06
-- Admin escalation candidates: strict dueAt < cutoff, resolved/closed excluded.
SELECT id,title,status,departmentId,officerId,dueAt,escalatedAt,
       ROUND((:as_of-dueAt)/3600000.0,2) AS overdue_hours
FROM Complaint WHERE status NOT IN ('RESOLVED','CLOSED') AND dueAt<:as_of
ORDER BY dueAt,id LIMIT :limit OFFSET :offset;

-- name: Q07
-- Status counts include zero-count states; :city scopes the report.
WITH statuses(status,position) AS (VALUES
 ('SUBMITTED',1),('ASSIGNED',2),('IN_PROGRESS',3),('RESOLVED',4),('CLOSED',5),('REOPENED',6))
SELECT s.status,count(c.id) AS total FROM statuses s
LEFT JOIN Complaint c ON c.status=s.status AND c.city=:city
GROUP BY s.status,s.position ORDER BY s.position;

-- name: Q08
-- Admin metrics. "Resolved" includes CLOSED. Average resolution is latest resolution
-- minus initial submission (includes reopen time); feedback is per event, not per complaint.
SELECT count(*) AS total,
 COALESCE(sum(status IN ('RESOLVED','CLOSED')),0) AS resolved_or_closed,
 COALESCE(sum(status NOT IN ('RESOLVED','CLOSED')),0) AS active,
 COALESCE(sum(status NOT IN ('RESOLVED','CLOSED') AND dueAt<:as_of),0) AS overdue,
 COALESCE(sum(escalatedAt IS NOT NULL),0) AS escalated,
 ROUND(avg(CASE WHEN status IN ('RESOLVED','CLOSED') THEN (resolvedAt-createdAt)/3600000.0 END),2) AS average_resolution_hours,
 (SELECT ROUND(avg(f.rating),2) FROM Feedback f JOIN Complaint x ON x.id=f.complaintId WHERE x.city=:city) AS average_rating
FROM Complaint WHERE city=:city;

-- name: Q09
-- Department metrics: aggregate child relations first; include departments with no cases.
WITH support_counts AS (SELECT complaintId,count(*) AS n FROM Support GROUP BY complaintId),
 feedback_counts AS (SELECT complaintId,count(*) AS n FROM Feedback GROUP BY complaintId)
SELECT d.id,d.name,count(c.id) AS total,
 COALESCE(sum(c.status IN ('RESOLVED','CLOSED')),0) AS resolved_or_closed,
 COALESCE(sum(c.status NOT IN ('RESOLVED','CLOSED') AND c.dueAt<:as_of),0) AS overdue,
 COALESCE(sum(s.n),0) AS support_count,COALESCE(sum(f.n),0) AS feedback_count
FROM Department d LEFT JOIN Complaint c ON c.departmentId=d.id AND c.city=:city
LEFT JOIN support_counts s ON s.complaintId=c.id LEFT JOIN feedback_counts f ON f.complaintId=c.id
GROUP BY d.id,d.name ORDER BY d.name;

-- name: Q10
-- Officer workload: pass NULL officer_id for all officers, otherwise one officer.
SELECT u.id,u.name,d.name AS department_name,count(c.id) AS total_count,
 COALESCE(sum(c.status NOT IN ('RESOLVED','CLOSED')),0) AS active_count,
 COALESCE(sum(c.status NOT IN ('RESOLVED','CLOSED') AND c.dueAt<:as_of),0) AS overdue_count
FROM User u JOIN Department d ON d.id=u.departmentId LEFT JOIN Complaint c ON c.officerId=u.id
WHERE u.role='OFFICER' AND (:officer_id IS NULL OR u.id=:officer_id)
GROUP BY u.id,u.name,d.name ORDER BY active_count DESC,u.id;

-- name: Q11
-- Community support ranking, including zero-support reports.
SELECT c.id,c.title,c.status,count(s.userId) AS support_count
FROM Complaint c LEFT JOIN Support s ON s.complaintId=c.id WHERE c.city=:city
GROUP BY c.id,c.title,c.status ORDER BY support_count DESC,c.id LIMIT :limit OFFSET :offset;

-- name: Q12
-- Citizen or officer inbox: unread only, latest first.
SELECT id,complaintId,message,createdAt FROM Notification
WHERE userId=:citizen_id AND readAt IS NULL ORDER BY createdAt DESC,id LIMIT :limit OFFSET :offset;

-- name: Q13
-- Reporting citizen's feedback events, including multiple cycles per complaint.
SELECT f.id,f.complaintId,f.rating,f.comment,f.reopened,f.createdAt,c.status AS current_status
FROM Feedback f JOIN Complaint c ON c.id=f.complaintId
WHERE f.userId=:citizen_id ORDER BY f.createdAt DESC,f.id;

-- name: Q14
-- Submission trend, calendar months with zero counts; month_start is YYYY-MM-01.
WITH RECURSIVE months(month,n) AS (
 SELECT date(:month_start),1 UNION ALL SELECT date(month,'+1 month'),n+1 FROM months WHERE n<:month_count
)
SELECT m.month,count(c.id) AS submitted FROM months m LEFT JOIN Complaint c
 ON c.createdAt>=CAST(strftime('%s',m.month) AS INTEGER)*1000
 AND c.createdAt<CAST(strftime('%s',m.month,'+1 month') AS INTEGER)*1000 AND c.city=:city
GROUP BY m.month ORDER BY m.month;

-- name: Q15
-- Text-location duplicate candidates, not a duplicate verdict or geographical distance.
-- Same category/ward/city; recent, active, excluding current complaint. No map dependency.
SELECT id,title,address,ward,status,createdAt FROM Complaint
WHERE categoryId=:category_id AND ward=:ward AND city=:city
 AND createdAt>=:since AND status NOT IN ('RESOLVED','CLOSED') AND id!=:complaint_id
ORDER BY createdAt DESC,id LIMIT :limit OFFSET :offset;

-- name: Q16
-- Admin user directory. NEVER select passwordHash, Session.id or csrf into a dashboard.
SELECT u.id,u.name,u.email,u.role,d.name AS department_name,u.createdAt
FROM User u LEFT JOIN Department d ON d.id=u.departmentId
ORDER BY u.createdAt DESC,u.id LIMIT :limit OFFSET :offset;

-- name: Q17
-- Admin assignment candidates restricted to responsible department, least loaded first.
SELECT u.id,u.name,count(c.id) AS active_count FROM User u
LEFT JOIN Complaint c ON c.officerId=u.id AND c.status NOT IN ('RESOLVED','CLOSED')
WHERE u.role='OFFICER' AND u.departmentId=:department_id
GROUP BY u.id,u.name ORDER BY active_count,u.id;

-- name: Q18
-- Evidence metadata only; files are external to the DB.
SELECT id,'IMAGE' AS media_type,url,kind,NULL AS mimeType,NULL AS sizeBytes,createdAt
FROM Image WHERE complaintId=:complaint_id
UNION ALL
SELECT id,'VIDEO',url,'REPORT',mimeType,sizeBytes,createdAt FROM Video WHERE complaintId=:complaint_id
ORDER BY createdAt,id;

-- name: Q19
-- SLA outcome by priority; division by zero yields NULL, not a fictitious 0%.
SELECT priority,count(*) AS total,
 sum(status IN ('RESOLVED','CLOSED')) AS completed,
 sum(status IN ('RESOLVED','CLOSED') AND resolvedAt<=dueAt) AS completed_on_time,
 ROUND(100.0*sum(status IN ('RESOLVED','CLOSED') AND resolvedAt<=dueAt)/
       NULLIF(sum(status IN ('RESOLVED','CLOSED')),0),2) AS completed_on_time_percent
FROM Complaint WHERE city=:city GROUP BY priority ORDER BY priority;

-- name: Q20
-- Escalation register. escalatedAt is a marker in the real model, not a separate entity.
SELECT c.id,c.title,d.name AS department_name,c.status,c.escalatedAt,
       CASE WHEN c.status IN ('RESOLVED','CLOSED') THEN 0 ELSE 1 END AS still_active
FROM Complaint c JOIN Department d ON d.id=c.departmentId
WHERE c.escalatedAt IS NOT NULL AND c.city=:city ORDER BY c.escalatedAt,c.id;

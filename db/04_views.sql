CREATE VIEW v_active_readers AS
SELECT r.reader_id, r.card_number, r.first_name, r.last_name, r.email, r.phone,
       r.updated_at, r.updated_by,
       fn_has_active_membership(r.reader_id) AS has_membership,
       fn_reader_active_loans(r.reader_id)   AS active_loans,
       fn_reader_debt(r.reader_id)           AS debt
FROM readers r WHERE NOT r.is_deleted;

CREATE VIEW v_books_catalog AS
SELECT b.book_id, b.isbn, b.title, b.publish_year,
       c.name AS category, p.name AS publisher,
       COALESCE(string_agg(a.full_name, ', ' ORDER BY ba.author_order), '') AS authors,
       (SELECT count(*) FROM book_copies bc WHERE bc.book_id = b.book_id AND NOT bc.is_deleted) AS total_copies,
       fn_available_copies(b.book_id) AS available_copies
FROM books b
LEFT JOIN categories c ON c.category_id = b.category_id
LEFT JOIN publishers p ON p.publisher_id = b.publisher_id
LEFT JOIN book_authors ba ON ba.book_id = b.book_id
LEFT JOIN authors a ON a.author_id = ba.author_id
WHERE NOT b.is_deleted
GROUP BY b.book_id, c.name, p.name;

CREATE VIEW v_active_loans AS
SELECT l.loan_id, l.reader_id, r.card_number, r.first_name || ' ' || r.last_name AS reader_name,
       l.copy_id, bc.inventory_number, b.book_id, b.title,
       l.loaned_at, l.due_date,
       (l.due_date < CURRENT_DATE) AS is_overdue
FROM loans l
JOIN readers r      ON r.reader_id = l.reader_id
JOIN book_copies bc ON bc.copy_id = l.copy_id
JOIN books b        ON b.book_id = bc.book_id
WHERE l.returned_at IS NULL;

CREATE VIEW v_overdue_loans AS
SELECT v.*, (CURRENT_DATE - v.due_date) AS days_overdue,
       fn_calc_fine(v.loan_id) AS current_fine
FROM v_active_loans v WHERE v.is_overdue;

CREATE VIEW v_unpaid_fines AS
SELECT f.fine_id, f.loan_id, f.reader_id, r.card_number,
       r.first_name || ' ' || r.last_name AS reader_name,
       f.amount, f.reason, f.created_at
FROM fines f JOIN readers r ON r.reader_id = f.reader_id
WHERE f.status = 'unpaid';

CREATE VIEW v_reader_debts AS
SELECT reader_id, card_number, reader_name,
       count(*) AS unpaid_fines, sum(amount) AS total_debt
FROM v_unpaid_fines GROUP BY reader_id, card_number, reader_name;

CREATE VIEW v_popular_books AS
SELECT b.book_id, b.title, count(l.loan_id) AS loans_count
FROM books b
JOIN book_copies bc ON bc.book_id = b.book_id
JOIN loans l ON l.copy_id = bc.copy_id
WHERE NOT b.is_deleted
GROUP BY b.book_id, b.title
ORDER BY loans_count DESC;

CREATE VIEW v_active_reservations AS
SELECT rs.reservation_id, rs.reader_id, r.card_number, rs.book_id, b.title,
       rs.copy_id, rs.status, rs.reserved_at, rs.expires_at
FROM reservations rs
JOIN readers r ON r.reader_id = rs.reader_id
JOIN books b   ON b.book_id = rs.book_id
WHERE rs.status IN ('pending','ready');

CREATE VIEW v_room_schedule AS
SELECT rb.booking_id, rm.room_id, rm.name AS room, rb.reader_id,
       r.first_name || ' ' || r.last_name AS reader_name,
       rb.start_time, rb.end_time, rb.total_price, rb.status
FROM room_bookings rb
JOIN rooms rm   ON rm.room_id = rb.room_id AND NOT rm.is_deleted
JOIN readers r  ON r.reader_id = rb.reader_id
WHERE rb.status = 'confirmed';

CREATE VIEW v_revenue_summary AS
SELECT purpose, count(*) AS payments_count, sum(amount) AS total_amount
FROM payments GROUP BY purpose;

CREATE VIEW v_active_services AS
SELECT service_id, name, unit, unit_price FROM services WHERE NOT is_deleted;

CREATE VIEW v_active_rooms AS
SELECT room_id, name, capacity, hourly_price FROM rooms WHERE NOT is_deleted;

CREATE VIEW v_reader_services_orders AS
SELECT so.order_id, so.reader_id, s.name AS service, so.quantity, so.total_price,
       so.status, so.ordered_at
FROM service_orders so JOIN services s ON s.service_id = so.service_id;

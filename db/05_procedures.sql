CREATE PROCEDURE sp_register_reader(
    p_first VARCHAR, p_last VARCHAR, p_email VARCHAR, p_phone VARCHAR,
    p_user_id INT, INOUT p_reader_id INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    INSERT INTO readers (first_name, last_name, email, phone, updated_by)
    VALUES (p_first, p_last, p_email, p_phone, p_user_id)
    RETURNING reader_id INTO p_reader_id;
END $$;

CREATE PROCEDURE sp_update_reader(
    p_reader_id INT, p_first VARCHAR, p_last VARCHAR, p_email VARCHAR,
    p_phone VARCHAR, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE readers SET first_name=p_first, last_name=p_last, email=p_email, phone=p_phone
    WHERE reader_id = p_reader_id AND NOT is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reader % not found', p_reader_id; END IF;
END $$;

CREATE PROCEDURE sp_soft_delete_reader(p_reader_id INT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE readers SET is_deleted = TRUE WHERE reader_id = p_reader_id AND NOT is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reader % not found', p_reader_id; END IF;
END $$;

CREATE PROCEDURE sp_restore_reader(p_reader_id INT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE readers SET is_deleted = FALSE WHERE reader_id = p_reader_id AND is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deleted reader % not found', p_reader_id; END IF;
END $$;

CREATE PROCEDURE sp_assign_membership(
    p_reader_id INT, p_plan_id INT, p_user_id INT, INOUT p_membership_id INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE v_plan membership_plans%ROWTYPE;
BEGIN
    PERFORM fn_set_user(p_user_id);
    IF NOT EXISTS (SELECT 1 FROM readers WHERE reader_id = p_reader_id AND NOT is_deleted) THEN
        RAISE EXCEPTION 'Reader % not found', p_reader_id;
    END IF;
    SELECT * INTO v_plan FROM membership_plans WHERE plan_id = p_plan_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Plan % not found', p_plan_id; END IF;

    UPDATE reader_memberships SET status = 'cancelled'
     WHERE reader_id = p_reader_id AND status = 'active';

    INSERT INTO reader_memberships (reader_id, plan_id, start_date, end_date)
    VALUES (p_reader_id, p_plan_id, CURRENT_DATE, CURRENT_DATE + v_plan.duration_days)
    RETURNING membership_id INTO p_membership_id;

    IF v_plan.price > 0 THEN
        INSERT INTO payments (reader_id, amount, purpose, membership_id)
        VALUES (p_reader_id, v_plan.price, 'membership', p_membership_id);
    END IF;
END $$;

CREATE PROCEDURE sp_add_book(
    p_isbn VARCHAR, p_title VARCHAR, p_publisher_id INT, p_category_id INT,
    p_year INT, p_author_ids INT[], p_copies INT, p_user_id INT,
    INOUT p_book_id INT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE i INT;
BEGIN
    PERFORM fn_set_user(p_user_id);
    INSERT INTO books (isbn, title, publisher_id, category_id, publish_year, updated_by)
    VALUES (p_isbn, p_title, p_publisher_id, p_category_id, p_year, p_user_id)
    RETURNING book_id INTO p_book_id;

    FOR i IN 1 .. COALESCE(array_length(p_author_ids, 1), 0) LOOP
        INSERT INTO book_authors (book_id, author_id, author_order)
        VALUES (p_book_id, p_author_ids[i], i);
    END LOOP;

    FOR i IN 1 .. p_copies LOOP
        INSERT INTO book_copies (book_id, inventory_number, updated_by)
        VALUES (p_book_id, 'INV-' || p_book_id || '-' || i, p_user_id);
    END LOOP;
END $$;

CREATE PROCEDURE sp_soft_delete_book(p_book_id INT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE books SET is_deleted = TRUE WHERE book_id = p_book_id AND NOT is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Book % not found', p_book_id; END IF;
END $$;

CREATE PROCEDURE sp_soft_delete_copy(p_copy_id INT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE book_copies SET is_deleted = TRUE WHERE copy_id = p_copy_id AND NOT is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Copy % not found', p_copy_id; END IF;
END $$;

CREATE PROCEDURE sp_issue_book(
    p_reader_id INT, p_copy_id INT, p_user_id INT,
    p_loaned_at TIMESTAMPTZ DEFAULT now(), INOUT p_loan_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_plan   membership_plans%ROWTYPE;
    v_copy   book_copies%ROWTYPE;
BEGIN
    PERFORM fn_set_user(p_user_id);

    IF NOT EXISTS (SELECT 1 FROM readers WHERE reader_id = p_reader_id AND NOT is_deleted) THEN
        RAISE EXCEPTION 'Reader % not found', p_reader_id;
    END IF;

    SELECT p.* INTO v_plan
    FROM reader_memberships m JOIN membership_plans p USING (plan_id)
    WHERE m.reader_id = p_reader_id AND m.status = 'active' AND CURRENT_DATE BETWEEN m.start_date AND m.end_date
    ORDER BY m.end_date DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reader % has no active membership', p_reader_id; END IF;

    IF fn_reader_debt(p_reader_id) > 0 THEN
        RAISE EXCEPTION 'Reader % has unpaid fines: %', p_reader_id, fn_reader_debt(p_reader_id);
    END IF;
    IF fn_reader_active_loans(p_reader_id) >= v_plan.max_loans THEN
        RAISE EXCEPTION 'Loan limit (%) reached for reader %', v_plan.max_loans, p_reader_id;
    END IF;

    SELECT * INTO v_copy FROM book_copies WHERE copy_id = p_copy_id AND NOT is_deleted FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Copy % not found', p_copy_id; END IF;

    IF v_copy.status = 'reserved' THEN
        IF NOT EXISTS (SELECT 1 FROM reservations WHERE copy_id = p_copy_id
                       AND reader_id = p_reader_id AND status = 'ready') THEN
            RAISE EXCEPTION 'Copy % is reserved for another reader', p_copy_id;
        END IF;
    ELSIF v_copy.status <> 'available' THEN
        RAISE EXCEPTION 'Copy % is not available (status: %)', p_copy_id, v_copy.status;
    END IF;

    INSERT INTO loans (reader_id, copy_id, issued_by, loaned_at, due_date, updated_by)
    VALUES (p_reader_id, p_copy_id, p_user_id, p_loaned_at,
            p_loaned_at::date + v_plan.loan_days, p_user_id)
    RETURNING loan_id INTO p_loan_id;
END $$;

CREATE PROCEDURE sp_return_book(p_loan_id BIGINT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE loans SET returned_at = now()
     WHERE loan_id = p_loan_id AND returned_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active loan % not found', p_loan_id; END IF;
END $$;

CREATE PROCEDURE sp_renew_loan(p_loan_id BIGINT, p_user_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    l loans%ROWTYPE;
    v_days INT;
BEGIN
    PERFORM fn_set_user(p_user_id);
    SELECT * INTO l FROM loans WHERE loan_id = p_loan_id AND returned_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active loan % not found', p_loan_id; END IF;
    IF l.due_date < CURRENT_DATE THEN RAISE EXCEPTION 'Loan % is overdue, cannot renew', p_loan_id; END IF;

    SELECT p.loan_days INTO v_days
    FROM reader_memberships m JOIN membership_plans p USING (plan_id)
    WHERE m.reader_id = l.reader_id AND m.status = 'active'
    ORDER BY m.end_date DESC LIMIT 1;
    v_days := COALESCE(v_days, 14);

    IF l.due_date > l.loaned_at::date + v_days THEN
        RAISE EXCEPTION 'Loan % was already renewed', p_loan_id;
    END IF;
    IF EXISTS (SELECT 1 FROM reservations r JOIN book_copies bc ON bc.book_id = r.book_id
               WHERE bc.copy_id = l.copy_id AND r.status = 'pending') THEN
        RAISE EXCEPTION 'Book has pending reservations, cannot renew';
    END IF;

    UPDATE loans SET due_date = due_date + v_days WHERE loan_id = p_loan_id;
END $$;

CREATE PROCEDURE sp_reserve_book(
    p_reader_id INT, p_book_id INT, p_user_id INT, INOUT p_reservation_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    IF NOT fn_has_active_membership(p_reader_id) THEN
        RAISE EXCEPTION 'Reader % has no active membership', p_reader_id;
    END IF;
    IF fn_available_copies(p_book_id) > 0 THEN
        RAISE EXCEPTION 'Book % has available copies, issue it directly', p_book_id;
    END IF;
    IF EXISTS (SELECT 1 FROM reservations WHERE reader_id = p_reader_id AND book_id = p_book_id
               AND status IN ('pending','ready')) THEN
        RAISE EXCEPTION 'Reader % already reserved book %', p_reader_id, p_book_id;
    END IF;
    INSERT INTO reservations (reader_id, book_id)
    VALUES (p_reader_id, p_book_id) RETURNING reservation_id INTO p_reservation_id;
END $$;

CREATE PROCEDURE sp_cancel_reservation(p_reservation_id BIGINT, p_user_id INT)
LANGUAGE plpgsql AS $$
DECLARE r reservations%ROWTYPE;
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE reservations SET status = 'cancelled'
     WHERE reservation_id = p_reservation_id AND status IN ('pending','ready')
    RETURNING * INTO r;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active reservation % not found', p_reservation_id; END IF;
    IF r.copy_id IS NOT NULL THEN PERFORM fn_release_copy(r.copy_id); END IF;
END $$;

CREATE PROCEDURE sp_expire_reservations(p_user_id INT)
LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    PERFORM fn_set_user(p_user_id);
    FOR r IN SELECT reservation_id, copy_id FROM reservations
             WHERE status = 'ready' AND expires_at < now() FOR UPDATE
    LOOP
        UPDATE reservations SET status = 'expired' WHERE reservation_id = r.reservation_id;
        PERFORM fn_release_copy(r.copy_id);
    END LOOP;
END $$;

CREATE PROCEDURE sp_pay_fine(
    p_fine_id BIGINT, p_user_id INT, INOUT p_payment_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE f fines%ROWTYPE;
BEGIN
    PERFORM fn_set_user(p_user_id);
    SELECT * INTO f FROM fines WHERE fine_id = p_fine_id AND status = 'unpaid' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unpaid fine % not found', p_fine_id; END IF;

    INSERT INTO payments (reader_id, amount, purpose, fine_id)
    VALUES (f.reader_id, f.amount, 'fine', f.fine_id)
    RETURNING payment_id INTO p_payment_id;
    UPDATE fines SET status = 'paid' WHERE fine_id = p_fine_id;
END $$;

CREATE PROCEDURE sp_waive_fine(p_fine_id BIGINT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE fines SET status = 'waived' WHERE fine_id = p_fine_id AND status = 'unpaid';
    IF NOT FOUND THEN RAISE EXCEPTION 'Unpaid fine % not found', p_fine_id; END IF;
END $$;

CREATE PROCEDURE sp_order_service(
    p_reader_id INT, p_service_id INT, p_qty INT, p_user_id INT, INOUT p_order_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE s services%ROWTYPE;
BEGIN
    PERFORM fn_set_user(p_user_id);
    SELECT * INTO s FROM services WHERE service_id = p_service_id AND NOT is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Service % not found', p_service_id; END IF;
    INSERT INTO service_orders (reader_id, service_id, handled_by, quantity, total_price)
    VALUES (p_reader_id, p_service_id, p_user_id, p_qty, s.unit_price * p_qty)
    RETURNING order_id INTO p_order_id;
END $$;

CREATE PROCEDURE sp_pay_service_order(
    p_order_id BIGINT, p_user_id INT, INOUT p_payment_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE o service_orders%ROWTYPE;
BEGIN
    PERFORM fn_set_user(p_user_id);
    SELECT * INTO o FROM service_orders WHERE order_id = p_order_id AND status = 'new' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'New order % not found', p_order_id; END IF;
    IF o.total_price > 0 THEN
        INSERT INTO payments (reader_id, amount, purpose, service_order_id)
        VALUES (o.reader_id, o.total_price, 'service', o.order_id)
        RETURNING payment_id INTO p_payment_id;
    END IF;
    UPDATE service_orders SET status = 'paid' WHERE order_id = p_order_id;
END $$;

CREATE PROCEDURE sp_soft_delete_service(p_service_id INT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE services SET is_deleted = TRUE WHERE service_id = p_service_id AND NOT is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Service % not found', p_service_id; END IF;
END $$;

CREATE PROCEDURE sp_book_room(
    p_room_id INT, p_reader_id INT, p_start TIMESTAMPTZ, p_end TIMESTAMPTZ,
    p_user_id INT, INOUT p_booking_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC;
BEGIN
    PERFORM fn_set_user(p_user_id);
    IF NOT EXISTS (SELECT 1 FROM reader_memberships m JOIN membership_plans p USING (plan_id)
                   WHERE m.reader_id = p_reader_id AND m.status = 'active'
                     AND CURRENT_DATE BETWEEN m.start_date AND m.end_date AND p.can_use_rooms) THEN
        RAISE EXCEPTION 'Reader % plan does not allow room booking', p_reader_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM rooms WHERE room_id = p_room_id AND NOT is_deleted) THEN
        RAISE EXCEPTION 'Room % not found', p_room_id;
    END IF;
    v_price := fn_room_price(p_room_id, p_start, p_end);

    INSERT INTO room_bookings (room_id, reader_id, start_time, end_time, total_price)
    VALUES (p_room_id, p_reader_id, p_start, p_end, v_price)
    RETURNING booking_id INTO p_booking_id;

    IF v_price > 0 THEN
        INSERT INTO payments (reader_id, amount, purpose, booking_id)
        VALUES (p_reader_id, v_price, 'room', p_booking_id);
    END IF;
END $$;

CREATE PROCEDURE sp_cancel_booking(p_booking_id BIGINT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_set_user(p_user_id);
    UPDATE room_bookings SET status = 'cancelled' WHERE booking_id = p_booking_id AND status = 'confirmed';
    IF NOT FOUND THEN RAISE EXCEPTION 'Confirmed booking % not found', p_booking_id; END IF;
END $$;

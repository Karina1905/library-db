CREATE FUNCTION fn_set_user(p_user_id INT) RETURNS VOID
LANGUAGE sql AS $$
    SELECT set_config('app.user_id', p_user_id::text, true);
$$;

CREATE FUNCTION fn_current_user() RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.user_id', true), '')::int;
$$;

CREATE FUNCTION fn_has_active_membership(p_reader_id INT, p_on DATE DEFAULT CURRENT_DATE)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM reader_memberships
        WHERE reader_id = p_reader_id AND status = 'active'
          AND p_on BETWEEN start_date AND end_date
    );
$$;

CREATE FUNCTION fn_available_copies(p_book_id INT) RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT count(*)::int FROM book_copies
    WHERE book_id = p_book_id AND status = 'available' AND NOT is_deleted;
$$;

CREATE FUNCTION fn_reader_active_loans(p_reader_id INT) RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT count(*)::int FROM loans WHERE reader_id = p_reader_id AND returned_at IS NULL;
$$;

CREATE FUNCTION fn_reader_debt(p_reader_id INT) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(sum(amount), 0) FROM fines
    WHERE reader_id = p_reader_id AND status = 'unpaid';
$$;

CREATE FUNCTION fn_calc_fine(p_loan_id BIGINT) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT GREATEST(0, COALESCE(l.returned_at, now())::date - l.due_date)
           * COALESCE((
                SELECT p.fine_per_day
                FROM reader_memberships m JOIN membership_plans p USING (plan_id)
                WHERE m.reader_id = l.reader_id AND m.start_date <= l.loaned_at::date
                ORDER BY m.start_date DESC LIMIT 1), 2.00)
    FROM loans l WHERE l.loan_id = p_loan_id;
$$;

CREATE FUNCTION fn_room_price(p_room_id INT, p_start TIMESTAMPTZ, p_end TIMESTAMPTZ)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT ceil(extract(epoch FROM (p_end - p_start)) / 3600.0) * hourly_price
    FROM rooms WHERE room_id = p_room_id;
$$;

CREATE FUNCTION fn_release_copy(p_copy_id INT) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_book INT;
    v_res  BIGINT;
BEGIN
    SELECT book_id INTO v_book FROM book_copies WHERE copy_id = p_copy_id;

    SELECT reservation_id INTO v_res FROM reservations
    WHERE book_id = v_book AND status = 'pending'
    ORDER BY reserved_at LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_res IS NOT NULL THEN
        UPDATE reservations
           SET status = 'ready', copy_id = p_copy_id, expires_at = now() + interval '3 days'
         WHERE reservation_id = v_res;
        UPDATE book_copies SET status = 'reserved' WHERE copy_id = p_copy_id;
    ELSE
        UPDATE book_copies SET status = 'available' WHERE copy_id = p_copy_id;
    END IF;
END $$;

CREATE FUNCTION trg_set_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    NEW.updated_by := COALESCE(fn_current_user(), NEW.updated_by);
    RETURN NEW;
END $$;

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['users','readers','books','book_copies','loans','fines']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%1$s_audit BEFORE INSERT OR UPDATE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_set_audit()', t);
    END LOOP;
END $$;

CREATE FUNCTION trg_block_hard_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Hard delete from % is forbidden, use soft delete (is_deleted = TRUE)', TG_TABLE_NAME;
END $$;

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['users','readers','books','book_copies','services','rooms']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%1$s_nodelete BEFORE DELETE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_block_hard_delete()', t);
    END LOOP;
END $$;

CREATE FUNCTION trg_reader_check_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.is_deleted AND NOT OLD.is_deleted THEN
        IF fn_reader_active_loans(NEW.reader_id) > 0 THEN
            RAISE EXCEPTION 'Reader % still has unreturned books', NEW.reader_id;
        END IF;
        IF fn_reader_debt(NEW.reader_id) > 0 THEN
            RAISE EXCEPTION 'Reader % has unpaid fines', NEW.reader_id;
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_readers_check_delete BEFORE UPDATE OF is_deleted ON readers
    FOR EACH ROW EXECUTE FUNCTION trg_reader_check_delete();

CREATE FUNCTION trg_copy_check_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.is_deleted AND NOT OLD.is_deleted AND OLD.status IN ('loaned','reserved') THEN
        RAISE EXCEPTION 'Copy % is % and cannot be deleted', OLD.copy_id, OLD.status;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_copies_check_delete BEFORE UPDATE OF is_deleted ON book_copies
    FOR EACH ROW EXECUTE FUNCTION trg_copy_check_delete();

CREATE FUNCTION trg_book_cascade_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.is_deleted AND NOT OLD.is_deleted THEN
        IF EXISTS (SELECT 1 FROM book_copies WHERE book_id = NEW.book_id
                   AND status IN ('loaned','reserved') AND NOT is_deleted) THEN
            RAISE EXCEPTION 'Book % has copies on loan or reserved', NEW.book_id;
        END IF;
        UPDATE book_copies SET is_deleted = TRUE WHERE book_id = NEW.book_id AND NOT is_deleted;
    ELSIF NOT NEW.is_deleted AND OLD.is_deleted THEN
        UPDATE book_copies SET is_deleted = FALSE WHERE book_id = NEW.book_id AND is_deleted;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_books_cascade_delete AFTER UPDATE OF is_deleted ON books
    FOR EACH ROW EXECUTE FUNCTION trg_book_cascade_delete();

CREATE FUNCTION trg_loans_after_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE book_copies SET status = 'loaned' WHERE copy_id = NEW.copy_id;
    UPDATE reservations SET status = 'fulfilled'
     WHERE copy_id = NEW.copy_id AND reader_id = NEW.reader_id AND status = 'ready';
    RETURN NEW;
END $$;
CREATE TRIGGER trg_loans_after_insert AFTER INSERT ON loans
    FOR EACH ROW EXECUTE FUNCTION trg_loans_after_insert();

CREATE FUNCTION trg_loans_before_return() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.status := 'returned';
    RETURN NEW;
END $$;
CREATE TRIGGER trg_loans_before_return BEFORE UPDATE OF returned_at ON loans
    FOR EACH ROW WHEN (OLD.returned_at IS NULL AND NEW.returned_at IS NOT NULL)
    EXECUTE FUNCTION trg_loans_before_return();

CREATE FUNCTION trg_loans_after_return() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_fine NUMERIC;
BEGIN
    v_fine := fn_calc_fine(NEW.loan_id);
    IF v_fine > 0 THEN
        INSERT INTO fines (loan_id, reader_id, amount, reason, updated_by)
        VALUES (NEW.loan_id, NEW.reader_id, v_fine,
                'Overdue: ' || (NEW.returned_at::date - NEW.due_date) || ' day(s)', NEW.updated_by);
    END IF;
    PERFORM fn_release_copy(NEW.copy_id);
    RETURN NEW;
END $$;
CREATE TRIGGER trg_loans_after_return AFTER UPDATE OF returned_at ON loans
    FOR EACH ROW WHEN (OLD.returned_at IS NULL AND NEW.returned_at IS NOT NULL)
    EXECUTE FUNCTION trg_loans_after_return();

CREATE FUNCTION trg_room_booking_overlap() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'confirmed' AND EXISTS (
        SELECT 1 FROM room_bookings
        WHERE room_id = NEW.room_id AND status = 'confirmed'
          AND booking_id IS DISTINCT FROM NEW.booking_id
          AND tstzrange(start_time, end_time) && tstzrange(NEW.start_time, NEW.end_time)
    ) THEN
        RAISE EXCEPTION 'Room % is already booked for this period', NEW.room_id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_room_bookings_overlap BEFORE INSERT OR UPDATE ON room_bookings
    FOR EACH ROW EXECUTE FUNCTION trg_room_booking_overlap();

CREATE FUNCTION trg_audit_log() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_row JSONB;
BEGIN
    v_row := to_jsonb(CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END);
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME, (v_row ->> TG_ARGV[0])::bigint, TG_OP,
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
            fn_current_user());
    RETURN NULL;
END $$;
CREATE TRIGGER trg_readers_log AFTER INSERT OR UPDATE OR DELETE ON readers
    FOR EACH ROW EXECUTE FUNCTION trg_audit_log('reader_id');
CREATE TRIGGER trg_books_log   AFTER INSERT OR UPDATE OR DELETE ON books
    FOR EACH ROW EXECUTE FUNCTION trg_audit_log('book_id');
CREATE TRIGGER trg_loans_log   AFTER INSERT OR UPDATE OR DELETE ON loans
    FOR EACH ROW EXECUTE FUNCTION trg_audit_log('loan_id');
CREATE TRIGGER trg_fines_log   AFTER INSERT OR UPDATE OR DELETE ON fines
    FOR EACH ROW EXECUTE FUNCTION trg_audit_log('fine_id');

CREATE UNIQUE INDEX ux_readers_email_active ON readers (lower(email)) WHERE NOT is_deleted;
CREATE UNIQUE INDEX ux_books_isbn_active    ON books (isbn)           WHERE NOT is_deleted;

CREATE INDEX ix_book_copies_book   ON book_copies (book_id) WHERE NOT is_deleted;
CREATE INDEX ix_loans_copy         ON loans (copy_id);
CREATE INDEX ix_fines_reader       ON fines (reader_id);

CREATE INDEX ix_loans_reader_due   ON loans (reader_id, due_date);

CREATE INDEX ix_loans_open_due     ON loans (due_date) WHERE returned_at IS NULL;
CREATE INDEX ix_fines_unpaid       ON fines (reader_id) WHERE status = 'unpaid';

CREATE INDEX ix_books_fts ON books USING GIN (to_tsvector('simple', title));

CREATE INDEX ix_readers_card_hash  ON readers USING HASH (card_number);

CREATE INDEX ix_audit_changed_brin ON audit_log USING BRIN (changed_at);
CREATE INDEX ix_audit_table_rec    ON audit_log (table_name, record_id);

CREATE INDEX ix_room_bookings_room_time ON room_bookings (room_id, start_time, end_time)
    WHERE status = 'confirmed';

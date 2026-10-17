\set ON_ERROR_STOP off
\echo '--- 1. Видача книги 30 днів тому (Марія, Standard: 21 день) і повернення зараз -> штраф'
CALL sp_issue_book(1, 1, 2, now() - interval '30 days');
CALL sp_return_book(1, 2);
SELECT fine_id, amount, reason, status, updated_by FROM fines;
\echo '--- 2. Борг блокує нову видачу'
CALL sp_issue_book(1, 2, 2);
\echo '--- 3. Оплата штрафу, потім видача проходить'
CALL sp_pay_fine(1, 2);
CALL sp_issue_book(1, 2, 2);
\echo '--- 4. Бронювання: єдиний примірник Clean Code зайнятий -> черга'
CALL sp_issue_book(2, 8, 3);
CALL sp_reserve_book(1, 4, 2);
CALL sp_return_book(3, 3);
SELECT reservation_id, status, copy_id FROM reservations;
SELECT copy_id, status FROM book_copies WHERE copy_id = 8;
\echo '--- 5. Чужий не може взяти заброньований примірник'
CALL sp_issue_book(3, 8, 3);
\echo '--- 6. Soft delete: читач з книгою не видаляється'
CALL sp_soft_delete_reader(1, 1);
\echo '--- 7. Hard delete заборонений'
DELETE FROM readers WHERE reader_id = 3;
\echo '--- 8. Soft delete Софії та перегляд через View'
CALL sp_soft_delete_reader(3, 1);
SELECT reader_id, card_number FROM v_active_readers;
SELECT reader_id, is_deleted, updated_by FROM readers WHERE reader_id=3;
CALL sp_restore_reader(3, 1);
\echo '--- 9. Кімнати: перетин бронювань'
CALL sp_book_room(2, 1, now() + interval '1 day', now() + interval '1 day 2 hours', 2);
CALL sp_book_room(2, 1, now() + interval '1 day 1 hour', now() + interval '1 day 3 hours', 2);
CALL sp_book_room(2, 2, now() + interval '2 day', now() + interval '2 day 1 hour', 2);
\echo '--- 10. Послуги'
CALL sp_order_service(1, 1, 10, 2);
CALL sp_pay_service_order(1, 2);
SELECT * FROM v_revenue_summary ORDER BY purpose;
\echo '--- 11. Видалення книги з примірником на руках'
CALL sp_soft_delete_book(1, 1);
CALL sp_soft_delete_book(2, 1);
SELECT book_id, title, available_copies FROM v_books_catalog ORDER BY 1;
\echo '--- 12. Аудит'
SELECT table_name, action, count(*) FROM audit_log GROUP BY 1,2 ORDER BY 1,2;
\echo '--- 13. Повнотекстовий пошук та популярні'
SELECT title FROM books WHERE to_tsvector('simple', title) @@ plainto_tsquery('simple','clean');
SELECT * FROM v_popular_books;

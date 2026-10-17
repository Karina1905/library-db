from __future__ import annotations
from datetime import datetime
from typing import Any, Optional, Sequence


class BaseRepository:
    def __init__(self, cursor):
        self._cur = cursor

    def _select(self, sql: str, params: Sequence[Any] = ()) -> list[dict]:
        self._cur.execute(sql, params)
        return list(self._cur.fetchall())

    def _call_returning(self, sql: str, params: Sequence[Any]) -> Any:
        self._cur.execute(sql, params)
        row = self._cur.fetchone()
        return next(iter(row.values())) if row else None

    def _call(self, sql: str, params: Sequence[Any]) -> None:
        self._cur.execute(sql, params)


class ReaderRepository(BaseRepository):
    def register(self, first: str, last: str, email: str, phone: str | None, user_id: int) -> int:
        return self._call_returning(
            "CALL sp_register_reader(%s,%s,%s,%s,%s,NULL::int)",
            (first, last, email, phone, user_id))

    def update(self, reader_id: int, first: str, last: str, email: str,
               phone: str | None, user_id: int) -> None:
        self._call("CALL sp_update_reader(%s,%s,%s,%s,%s,%s)",
                   (reader_id, first, last, email, phone, user_id))

    def soft_delete(self, reader_id: int, user_id: int) -> None:
        self._call("CALL sp_soft_delete_reader(%s,%s)", (reader_id, user_id))

    def restore(self, reader_id: int, user_id: int) -> None:
        self._call("CALL sp_restore_reader(%s,%s)", (reader_id, user_id))

    def assign_membership(self, reader_id: int, plan_id: int, user_id: int) -> int:
        return self._call_returning(
            "CALL sp_assign_membership(%s,%s,%s,NULL::int)", (reader_id, plan_id, user_id))

    def get(self, reader_id: int) -> Optional[dict]:
        rows = self._select("SELECT * FROM v_active_readers WHERE reader_id = %s", (reader_id,))
        return rows[0] if rows else None

    def list_active(self) -> list[dict]:
        return self._select("SELECT * FROM v_active_readers ORDER BY last_name, first_name")

    def debts(self) -> list[dict]:
        return self._select("SELECT * FROM v_reader_debts ORDER BY total_debt DESC")


class BookRepository(BaseRepository):
    def add(self, isbn: str, title: str, publisher_id: int | None, category_id: int | None,
            year: int | None, author_ids: list[int], copies: int, user_id: int) -> int:
        return self._call_returning(
            "CALL sp_add_book(%s,%s,%s,%s,%s,%s::int[],%s,%s,NULL::int)",
            (isbn, title, publisher_id, category_id, year, author_ids, copies, user_id))

    def soft_delete(self, book_id: int, user_id: int) -> None:
        self._call("CALL sp_soft_delete_book(%s,%s)", (book_id, user_id))

    def catalog(self, only_available: bool = False) -> list[dict]:
        sql = "SELECT * FROM v_books_catalog"
        if only_available:
            sql += " WHERE available_copies > 0"
        return self._select(sql + " ORDER BY title")

    def search(self, text: str) -> list[dict]:
        return self._select(
            "SELECT * FROM v_books_catalog WHERE title ILIKE %s OR authors ILIKE %s ORDER BY title",
            (f"%{text}%", f"%{text}%"))

    def popular(self, limit: int = 10) -> list[dict]:
        return self._select("SELECT * FROM v_popular_books LIMIT %s", (limit,))


class LoanRepository(BaseRepository):
    def issue(self, reader_id: int, copy_id: int, user_id: int,
              loaned_at: datetime | None = None) -> int:
        return self._call_returning(
            "CALL sp_issue_book(%s,%s,%s,COALESCE(%s::timestamptz, now()),NULL::bigint)",
            (reader_id, copy_id, user_id, loaned_at))

    def return_book(self, loan_id: int, user_id: int) -> None:
        self._call("CALL sp_return_book(%s,%s)", (loan_id, user_id))

    def renew(self, loan_id: int, user_id: int) -> None:
        self._call("CALL sp_renew_loan(%s,%s)", (loan_id, user_id))

    def reserve(self, reader_id: int, book_id: int, user_id: int) -> int:
        return self._call_returning(
            "CALL sp_reserve_book(%s,%s,%s,NULL::bigint)", (reader_id, book_id, user_id))

    def cancel_reservation(self, reservation_id: int, user_id: int) -> None:
        self._call("CALL sp_cancel_reservation(%s,%s)", (reservation_id, user_id))

    def active_by_reader(self, reader_id: int) -> list[dict]:
        return self._select("SELECT * FROM v_active_loans WHERE reader_id = %s ORDER BY due_date",
                            (reader_id,))

    def overdue(self) -> list[dict]:
        return self._select("SELECT * FROM v_overdue_loans ORDER BY days_overdue DESC")

    def reservations(self) -> list[dict]:
        return self._select("SELECT * FROM v_active_reservations ORDER BY reserved_at")


class FineRepository(BaseRepository):
    def unpaid_for_reader(self, reader_id: int) -> list[dict]:
        return self._select("SELECT * FROM v_unpaid_fines WHERE reader_id = %s ORDER BY created_at",
                            (reader_id,))

    def pay(self, fine_id: int, user_id: int) -> int:
        return self._call_returning("CALL sp_pay_fine(%s,%s,NULL::bigint)", (fine_id, user_id))

    def waive(self, fine_id: int, user_id: int) -> None:
        self._call("CALL sp_waive_fine(%s,%s)", (fine_id, user_id))

    def revenue(self) -> list[dict]:
        return self._select("SELECT * FROM v_revenue_summary ORDER BY purpose")


class ServiceRepository(BaseRepository):
    def catalog(self) -> list[dict]:
        return self._select("SELECT * FROM v_active_services ORDER BY name")

    def order(self, reader_id: int, service_id: int, qty: int, user_id: int) -> int:
        return self._call_returning("CALL sp_order_service(%s,%s,%s,%s,NULL::bigint)",
                                    (reader_id, service_id, qty, user_id))

    def pay_order(self, order_id: int, user_id: int) -> int:
        return self._call_returning("CALL sp_pay_service_order(%s,%s,NULL::bigint)",
                                    (order_id, user_id))

    def book_room(self, room_id: int, reader_id: int, start: datetime, end: datetime,
                  user_id: int) -> int:
        return self._call_returning(
            "CALL sp_book_room(%s,%s,%s,%s,%s,NULL::bigint)",
            (room_id, reader_id, start, end, user_id))

    def room_schedule(self) -> list[dict]:
        return self._select("SELECT * FROM v_room_schedule ORDER BY start_time")

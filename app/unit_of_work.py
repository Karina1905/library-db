from __future__ import annotations
import os
import psycopg2
import psycopg2.extras

from .repositories import (ReaderRepository, BookRepository, LoanRepository,
                           FineRepository, ServiceRepository)

DEFAULT_DSN = os.getenv("LIBRARY_DSN", "dbname=library host=localhost")


class UnitOfWork:

    def __init__(self, user_id: int, dsn: str = DEFAULT_DSN):
        self.user_id = user_id
        self._dsn = dsn
        self._conn = None
        self._committed = False

    def __enter__(self) -> "UnitOfWork":
        self._conn = psycopg2.connect(self._dsn)
        cur = self._conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        self.readers = ReaderRepository(cur)
        self.books = BookRepository(cur)
        self.loans = LoanRepository(cur)
        self.fines = FineRepository(cur)
        self.services = ServiceRepository(cur)
        self._cur = cur
        self._committed = False
        return self

    def commit(self) -> None:
        self._conn.commit()
        self._committed = True

    def rollback(self) -> None:
        self._conn.rollback()

    def __exit__(self, exc_type, exc, tb) -> bool:
        try:
            if exc_type is not None or not self._committed:
                self._conn.rollback()
        finally:
            self._cur.close()
            self._conn.close()
        return False

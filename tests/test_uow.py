import pytest
import psycopg2
from app.unit_of_work import UnitOfWork

U = 2


def test_commit_persists_and_rollback_discards():
    with UnitOfWork(U) as uow:
        rid = uow.readers.register("Рол", "Бек", "rb@example.com", None, U)

    with UnitOfWork(U) as uow:
        assert uow.readers.get(rid) is None

    with UnitOfWork(U) as uow:
        rid = uow.readers.register("Ком", "Іт", "ci@example.com", None, U)
        uow.commit()
    with UnitOfWork(U) as uow:
        assert uow.readers.get(rid)["email"] == "ci@example.com"


def test_exception_rolls_back_all_repositories():
    with pytest.raises(psycopg2.Error):
        with UnitOfWork(U) as uow:
            rid = uow.readers.register("Ех", "Це", "ex@example.com", None, U)
            uow.services.order(rid, 9999, 1, U)
            uow.commit()
    with UnitOfWork(U) as uow:
        assert all(r["email"] != "ex@example.com" for r in uow.readers.list_active())


def test_soft_delete_hides_reader_and_stamps_audit():
    with UnitOfWork(U) as uow:
        rid = uow.readers.register("Со", "Фт", "sd@example.com", None, U)
        uow.commit()
    with UnitOfWork(1) as uow:
        uow.readers.soft_delete(rid, 1)
        uow.commit()
    with UnitOfWork(U) as uow:
        assert uow.readers.get(rid) is None
        uow._cur.execute("SELECT is_deleted, updated_by FROM readers WHERE reader_id=%s", (rid,))
        row = uow._cur.fetchone()
        assert row["is_deleted"] and row["updated_by"] == 1

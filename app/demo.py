from datetime import datetime, timedelta, timezone
import psycopg2

from .unit_of_work import UnitOfWork

LIBRARIAN = 2


def show(title, rows):
    print(f"\n== {title}")
    for r in rows:
        print("  ", dict(r))


def scenario_1_late_return_and_fine():
    with UnitOfWork(LIBRARIAN) as uow:
        reader_id = uow.readers.register("Тест", "Читач", "demo@example.com",
                                          "+380500000000", LIBRARIAN)
        uow.readers.assign_membership(reader_id, plan_id=2, user_id=LIBRARIAN)
        loan_id = uow.loans.issue(reader_id, copy_id=3, user_id=LIBRARIAN,
                                  loaned_at=datetime.now(timezone.utc) - timedelta(days=30))
        uow.commit()
    print(f"[1] читач {reader_id}, видача {loan_id} збережені")

    with UnitOfWork(LIBRARIAN) as uow:
        uow.loans.return_book(loan_id, LIBRARIAN)
        fines = uow.fines.unpaid_for_reader(reader_id)
        show("штрафи після повернення", fines)
        for f in fines:
            uow.fines.pay(f["fine_id"], LIBRARIAN)
        uow.commit()
    with UnitOfWork(LIBRARIAN) as uow:
        show("виручка", uow.fines.revenue())
    return reader_id


def scenario_2_rollback(reader_id):
    try:
        with UnitOfWork(LIBRARIAN) as uow:
            uow.loans.issue(reader_id, copy_id=1, user_id=LIBRARIAN)
            print("[2] книгу видано (ще не commit); тепер штучна помилка")
            uow.services.order(reader_id, service_id=9999, qty=1, user_id=LIBRARIAN)
            uow.commit()
    except psycopg2.Error as e:
        print("[2] помилка:", str(e).splitlines()[0])
    with UnitOfWork(LIBRARIAN) as uow:
        copy1 = [b for b in uow.books.catalog() if b["title"] == "Кобзар"][0]
        print("[2] доступних примірників «Кобзаря»:", copy1["available_copies"], "(видача відкотилась)")


def scenario_3_views():
    with UnitOfWork(LIBRARIAN) as uow:
        show("каталог (доступні)", uow.books.catalog(only_available=True))
        show("популярні книги", uow.books.popular(3))
        show("активні читачі", uow.readers.list_active())


if __name__ == "__main__":
    rid = scenario_1_late_return_and_fine()
    scenario_2_rollback(rid)
    scenario_3_views()

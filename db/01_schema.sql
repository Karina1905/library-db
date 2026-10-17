DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

CREATE SEQUENCE reader_card_seq START 1;

CREATE TABLE roles (
    role_id     SMALLSERIAL PRIMARY KEY,
    name        VARCHAR(30) NOT NULL UNIQUE,
    description VARCHAR(200)
);

CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    role_id       SMALLINT     NOT NULL REFERENCES roles(role_id),
    username      VARCHAR(50)  NOT NULL UNIQUE,
    full_name     VARCHAR(150) NOT NULL,
    email         VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    is_deleted    BOOLEAN      NOT NULL DEFAULT FALSE,
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by    INT REFERENCES users(user_id)
);

CREATE TABLE membership_plans (
    plan_id        SERIAL PRIMARY KEY,
    name           VARCHAR(50)   NOT NULL UNIQUE,
    price          NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    duration_days  INT           NOT NULL CHECK (duration_days > 0),
    max_loans      INT           NOT NULL CHECK (max_loans > 0),
    loan_days      INT           NOT NULL CHECK (loan_days > 0),
    fine_per_day   NUMERIC(8,2)  NOT NULL CHECK (fine_per_day >= 0),
    can_use_rooms  BOOLEAN       NOT NULL DEFAULT FALSE
);

CREATE TABLE readers (
    reader_id   SERIAL PRIMARY KEY,
    card_number VARCHAR(20)  NOT NULL UNIQUE
                DEFAULT ('LIB-' || lpad(nextval('reader_card_seq')::text, 6, '0')),
    first_name  VARCHAR(80)  NOT NULL,
    last_name   VARCHAR(80)  NOT NULL,
    email       VARCHAR(150) NOT NULL,
    phone       VARCHAR(30),
    is_deleted  BOOLEAN      NOT NULL DEFAULT FALSE,
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by  INT REFERENCES users(user_id)
);

CREATE TABLE reader_memberships (
    membership_id SERIAL PRIMARY KEY,
    reader_id     INT  NOT NULL REFERENCES readers(reader_id),
    plan_id       INT  NOT NULL REFERENCES membership_plans(plan_id),
    start_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date      DATE NOT NULL,
    status        VARCHAR(12) NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active','cancelled')),
    CHECK (end_date > start_date)
);

CREATE TABLE publishers (
    publisher_id SERIAL PRIMARY KEY,
    name         VARCHAR(150) NOT NULL UNIQUE,
    country      VARCHAR(80)
);

CREATE TABLE authors (
    author_id SERIAL PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    country   VARCHAR(80)
);

CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    parent_id   INT REFERENCES categories(category_id),
    name        VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE books (
    book_id      SERIAL PRIMARY KEY,
    isbn         VARCHAR(20)  NOT NULL,
    title        VARCHAR(250) NOT NULL,
    publisher_id INT REFERENCES publishers(publisher_id),
    category_id  INT REFERENCES categories(category_id),
    publish_year INT CHECK (publish_year BETWEEN 1400 AND 2100),
    is_deleted   BOOLEAN     NOT NULL DEFAULT FALSE,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   INT REFERENCES users(user_id)
);

CREATE TABLE book_authors (
    book_id      INT NOT NULL REFERENCES books(book_id),
    author_id    INT NOT NULL REFERENCES authors(author_id),
    author_order SMALLINT NOT NULL DEFAULT 1,
    PRIMARY KEY (book_id, author_id)
);

CREATE TABLE book_copies (
    copy_id          SERIAL PRIMARY KEY,
    book_id          INT NOT NULL REFERENCES books(book_id),
    inventory_number VARCHAR(30) NOT NULL UNIQUE,
    status           VARCHAR(12) NOT NULL DEFAULT 'available'
                     CHECK (status IN ('available','loaned','reserved','lost','damaged')),
    is_deleted       BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by       INT REFERENCES users(user_id)
);

CREATE TABLE loans (
    loan_id     BIGSERIAL PRIMARY KEY,
    reader_id   INT NOT NULL REFERENCES readers(reader_id),
    copy_id     INT NOT NULL REFERENCES book_copies(copy_id),
    issued_by   INT NOT NULL REFERENCES users(user_id),
    loaned_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_date    DATE NOT NULL,
    returned_at TIMESTAMPTZ,
    status      VARCHAR(10) NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','returned')),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  INT REFERENCES users(user_id),
    CHECK (due_date >= loaned_at::date),
    CHECK (returned_at IS NULL OR returned_at >= loaned_at)
);

CREATE TABLE reservations (
    reservation_id BIGSERIAL PRIMARY KEY,
    reader_id      INT NOT NULL REFERENCES readers(reader_id),
    book_id        INT NOT NULL REFERENCES books(book_id),
    copy_id        INT REFERENCES book_copies(copy_id),
    reserved_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ,
    status         VARCHAR(12) NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','ready','fulfilled','cancelled','expired'))
);

CREATE TABLE fines (
    fine_id    BIGSERIAL PRIMARY KEY,
    loan_id    BIGINT NOT NULL REFERENCES loans(loan_id),
    reader_id  INT    NOT NULL REFERENCES readers(reader_id),
    amount     NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    reason     VARCHAR(200) NOT NULL,
    status     VARCHAR(10)  NOT NULL DEFAULT 'unpaid'
               CHECK (status IN ('unpaid','paid','waived')),
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by INT REFERENCES users(user_id)
);

CREATE TABLE services (
    service_id SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL UNIQUE,
    unit       VARCHAR(20)  NOT NULL DEFAULT 'шт',
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE service_orders (
    order_id    BIGSERIAL PRIMARY KEY,
    reader_id   INT NOT NULL REFERENCES readers(reader_id),
    service_id  INT NOT NULL REFERENCES services(service_id),
    handled_by  INT NOT NULL REFERENCES users(user_id),
    quantity    INT NOT NULL CHECK (quantity > 0),
    total_price NUMERIC(10,2) NOT NULL CHECK (total_price >= 0),
    status      VARCHAR(10) NOT NULL DEFAULT 'new'
                CHECK (status IN ('new','paid','cancelled')),
    ordered_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rooms (
    room_id      SERIAL PRIMARY KEY,
    name         VARCHAR(80) NOT NULL UNIQUE,
    capacity     INT NOT NULL CHECK (capacity > 0),
    hourly_price NUMERIC(10,2) NOT NULL CHECK (hourly_price >= 0),
    is_deleted   BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE room_bookings (
    booking_id  BIGSERIAL PRIMARY KEY,
    room_id     INT NOT NULL REFERENCES rooms(room_id),
    reader_id   INT NOT NULL REFERENCES readers(reader_id),
    start_time  TIMESTAMPTZ NOT NULL,
    end_time    TIMESTAMPTZ NOT NULL,
    total_price NUMERIC(10,2) NOT NULL CHECK (total_price >= 0),
    status      VARCHAR(10) NOT NULL DEFAULT 'confirmed'
                CHECK (status IN ('confirmed','cancelled','completed')),
    CHECK (end_time > start_time)
);

CREATE TABLE payments (
    payment_id       BIGSERIAL PRIMARY KEY,
    reader_id        INT NOT NULL REFERENCES readers(reader_id),
    amount           NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    purpose          VARCHAR(12) NOT NULL CHECK (purpose IN ('fine','membership','service','room')),
    fine_id          BIGINT REFERENCES fines(fine_id),
    membership_id    INT    REFERENCES reader_memberships(membership_id),
    service_order_id BIGINT REFERENCES service_orders(order_id),
    booking_id       BIGINT REFERENCES room_bookings(booking_id),
    paid_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (purpose='fine'       AND fine_id          IS NOT NULL) OR
        (purpose='membership' AND membership_id    IS NOT NULL) OR
        (purpose='service'    AND service_order_id IS NOT NULL) OR
        (purpose='room'       AND booking_id       IS NOT NULL)
    )
);

CREATE TABLE audit_log (
    log_id     BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id  BIGINT,
    action     VARCHAR(6)  NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_data   JSONB,
    new_data   JSONB,
    changed_by INT,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

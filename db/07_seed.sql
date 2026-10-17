INSERT INTO roles (name, description) VALUES
 ('admin','Адміністратор'), ('librarian','Бібліотекар');

INSERT INTO users (role_id, username, full_name, email, password_hash) VALUES
 (1,'admin','Адміністратор системи','admin@library.local','x'),
 (2,'olena','Олена Бібліотекар','olena@library.local','x'),
 (2,'ivan','Іван Бібліотекар','ivan@library.local','x');

INSERT INTO membership_plans (name, price, duration_days, max_loans, loan_days, fine_per_day, can_use_rooms) VALUES
 ('Basic',    100.00,  90, 3, 14, 2.00, FALSE),
 ('Standard', 250.00, 180, 5, 21, 2.00, TRUE),
 ('Premium',  400.00, 365, 10, 30, 1.00, TRUE);

INSERT INTO publishers (name, country) VALUES
 ('А-БА-БА-ГА-ЛА-МА-ГА','Україна'), ('Видавництво Старого Лева','Україна'), ('Penguin Books','UK');
INSERT INTO authors (full_name, country) VALUES
 ('Іван Франко','Україна'), ('Леся Українка','Україна'),
 ('Тарас Шевченко','Україна'), ('George Orwell','UK'), ('Robert C. Martin','USA');
INSERT INTO categories (name) VALUES ('Художня література'),('Наукова література'),('Програмування');
INSERT INTO categories (parent_id, name) VALUES (2,'Комп''ютерні науки');

INSERT INTO services (name, unit, unit_price) VALUES
 ('Друк А4','стор.',2.00),
 ('Сканування','стор.',3.00),
 ('Ксерокопія','стор.',1.50),
 ('Ламінування','шт',15.00);
INSERT INTO rooms (name, capacity, hourly_price) VALUES
 ('Читальна зала №1',20,0.00),
 ('Переговорна',8,120.00),
 ('Коворкінг',12,80.00);

CALL sp_add_book('978-966-03-1111-1','Кобзар',1,1,2020,ARRAY[3],3,1);
CALL sp_add_book('978-966-03-2222-2','Лісова пісня',2,1,2018,ARRAY[2],2,1);
CALL sp_add_book('978-0-14-103614-4','1984',3,1,2021,ARRAY[4],2,1);
CALL sp_add_book('978-0-13-235088-4','Clean Code',3,3,2008,ARRAY[5],1,1);
CALL sp_add_book('978-966-03-3333-3','Захар Беркут',1,1,2019,ARRAY[1],2,1);

CALL sp_register_reader('Марія','Коваль','maria@example.com','+380501111111',2);
CALL sp_register_reader('Андрій','Мельник','andriy@example.com','+380502222222',2);
CALL sp_register_reader('Софія','Бондар','sofia@example.com','+380503333333',3);
CALL sp_assign_membership(1, 2, 2);
CALL sp_assign_membership(2, 1, 2);
CALL sp_assign_membership(3, 3, 3);

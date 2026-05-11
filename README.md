## Проєкт

Аналіз прибутковості невеликої української B2B trucking-компанії з 12 вантажівками за період **липень 2022 - жовтень 2024**.

Компанія перевозить зернові культури Україною: пшеницю, соняшник, кукурудзу та сою. У 2024 році бізнес стикається зі зростанням вартості дизельного пального, тоді як клієнтські тарифи не зростають пропорційно.

Мета проєкту — визначити, які клієнти, маршрути та операційні фактори найбільше впливають на прибутковість бізнесу.

## Бізнес-питання

1. Які клієнти генерують прибуткове зростання, а які створюють низькомаржинальний обсяг?
2. Чи стало зростання цін на пальне у 2024 році критичним фактором для життєздатності бізнесу?
3. Які маршрути створюють найбільше операційне навантаження через затримки?
4. Які вантажівки та водії використовуються найефективніше?

## Дані

Проєкт використовує синтетичний, але бізнес-реалістичний датасет для української freight trucking компанії.

Основні таблиці:

| Таблиця | Опис |
|---|---|
| `trips` | Фактичні перевезення |
| `client_rates` | Тарифні сітки клієнтів |
| `fuel_purchases` | Заправки з паливних контрактів |
| `fuel_contracts` | Контракти на закупівлю дизелю |
| `clients` | Клієнти компанії |
| `routes` | Маршрути перевезень |
| `trucks` | Автопарк |
| `drivers` | Водії |
| `truck_downtime` | Простої вантажівок |

## Логіка метрик

У сирих даних немає готових колонок `revenue` або `profit`, тому фінансові метрики розраховуються аналітично.

Ключові припущення:

- `Revenue` розраховується через `trips` + `client_rates`.
- `Cancelled trips` виключаються з revenue.
- `Fuel cost` аналізується на рівні `truck_id + month`, бо заправки не прив’язані напряму до `trip_id`.
- `Estimated gross profit` = `revenue - allocated fuel cost`.
- `Delayed trips` включаються в revenue, але аналізуються окремо як операційний ризик.
- Trip-level profit є оцінкою, а не фактично записаним показником.

## Data Quality

Перед побудовою KPI датасет був перевірений на повноту, унікальність ключів, коректність зв’язків між таблицями та відповідність бізнес-правилам trucking-компанії.

Основні результати перевірок:

| Check | Result | Status |
|---|---:|---|
| Duplicate primary keys | 0 | Passed |
| Critical missing values | 0 | Passed |
| Invalid foreign keys | 0 | Passed |
| Trips during truck downtime | 0 | Passed |
| Seasonal clients outside Jul-Sep | 0 | Passed |
| Cargo-client mismatches | 0 | Passed |
| Fuel price mismatches vs contract | 0 | Passed |
| Fuel contract overuse | 0 | Passed |
| Odometer decreases | 0 | Passed |
| Cancelled trips | 32 | Reviewed |
| Strict weight-band rate gaps | 701 | Reviewed |
| Trips without client/date/distance rate | 0 | Passed |

Strict weight-band rate gaps пов’язані з overweight local trips, де `cargo_tons_actual` перевищує верхній тарифний weight band. Для `revenue` calculation використовується ranked rate matching.

Детальний підсумок: [`docs/02_data_quality_summary.md`](docs/02_data_quality_summary.md)  
SQL-перевірки: [`sql/01_data_quality_checks.sql`](sql/01_data_quality_checks.sql)


## Dashboard

Tableau dashboard побудований навколо трьох рівнів аналізу:

1. Business health overview
2. Client profitability and unit economics
3. Operational drivers: routes, delays, trucks and drivers

Посилання на Tableau Public: `додати посилання`

## Основні висновки

> Буде оновлено після завершення аналізу.

Очікувані напрями аналізу:

- вплив fuel cost на маржу у 2024 році;
- клієнти з високим revenue, але низькою маржею;
- сезонні клієнти як джерело обсягу, але не завжди прибутковості;
- портові маршрути як джерело затримок;
- вплив простоїв старіших вантажівок на операційну ефективність.

## Рекомендації

> Буде оновлено після завершення аналізу.

Можливі напрями рекомендацій:

- перегляд тарифів для низькомаржинальних клієнтів;
- пріоритезація прибуткових клієнтів у пікові сезони;
- окремий моніторинг портових маршрутів;
- оптимізація використання автопарку;
- використання паливних контрактів для захисту маржі.

## Інструменти

- SQL
- Tableau
- Python

## Структура репозиторію

```text
.
├── data/
├── sql/
├── tableau/
├── docs/
├── scripts/
└── README.md

# Go with GenAI — Lesson 12: Go Serverless

LibraTrack: дві функції з наданого прикладу та власна HTTP-функція нормалізації
профілю читача. Локальне виконання AWS Lambda через Floci та AWS SAM.

| Функція | Тригер | Результат |
|---|---|---|
| `cmd/webhook` | `POST /webhook` через API Gateway REST | Перевіряє та нормалізує пожертву книги |
| `cmd/thumbnail` | S3 ObjectCreated для `covers/` | Створює пропорційну PNG-мініатюру до 200 × 200 |
| `cmd/reader` | `POST /readers/normalize` через API Gateway REST | Перевіряє ім’я та email, нормалізує пробіли й домен email |

## Завдання та походження

- 70 балів: запустити приклади на власному ПК.
- +20 балів: згенерувати Terraform і проаналізувати рядок за рядком.
- +10 балів: написати власну функцію з HTTP-тригером.

Початковий стан `main` створено з `libratrack-lambda-demo.zip`; весь застосунок
відразу розміщено в корені. Доопрацювання виконуються в `develop`, прийняття
змін — через Pull Request `develop` → `main`.

[Оригінальний опис прикладу](docs/ORIGINAL_DEMO_README.md) збережено як джерело;
його статус перевірки належить автору. SHA-256 вихідного архіву:
`0105a9cfb34f774232b6877bae5c57f57b26d31323e0b430c19695ff40b23c2b`.

## Середовище

Потрібні Go 1.22+, Docker з Compose v2, AWS CLI v2, Terraform 1.5+,
AWS SAM CLI, Python 3, Bash та `zip`. Усі виклики AWS у сценаріях спрямовані
на локальний Floci з тестовими credentials; хмарний AWS-акаунт не потрібен.

Інструкції встановлення: [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
[SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html),
[Terraform](https://developer.hashicorp.com/terraform/install).
Якщо інструменти встановлені локально в `.tools/bin`, Makefile і `env.sh`
додають цю папку до PATH. Вона виключена з Git.

Опційні локальні налаштування:

```bash
cp .env.example .env
# Вкажіть абсолютні шляхи до зовнішніх runtime/evidence папок за потреби.
source scripts/env.sh
```

За замовчуванням state та план Terraform зберігаються поряд із checkout
у `../.lesson12-runtime`, докази — у `../lesson12-evidence`. Вони не є частиною
репозиторію. Дані Floci теж зберігаються у зовнішній runtime-папці.

## Локальний запуск

Команди виконуються з кореня репозиторію:

```bash
make test
make up
make build
make plan-tf
# Прочитайте terraform plan та docs/TERRAFORM_REVIEW.md.
make deploy-tf
make smoke
```

Якщо Floci вже працює в навчальній Ubuntu VM, пропустіть `make up` і використайте
її endpoint через NAT forwarding або SSH tunnel. Для окремого середовища задайте
в `.env` власний `LESSON12_RUNTIME_DIR`; при зміні backend-шляху один раз виконайте
`TF_CLI_ARGS_init=-reconfigure make plan-tf`. Не змішуйте state різних емуляторів.

На macOS із Docker Desktop 20.10 прямий Unix-клієнт Floci може завершити запуск
Lambda помилкою `java.net.BindException: Permission denied`. У такому разі
використовуйте Docker Engine навчальної Ubuntu VM. Самі SAM-виклики можуть
працювати на macOS окремо від Floci.

`make deploy-tf` застосовує вже збережений план. Після зміни Terraform, коду
або пакетів потрібно знову виконати `make plan-tf` і перечитати зміни.
CLI helpers `deploy-cli` і `cleanup` залишені з прикладу для порівняння;
вони відмовляються працювати, якщо ресурси вже керуються Terraform.

## Власна HTTP-функція

```bash
source scripts/env.sh
READER_URL=$(terraform -chdir=terraform output -raw reader_url_floci)
curl -i -H 'Content-Type: application/json' \
  --data-binary @events/reader/payload_valid.json "$READER_URL"
curl -i -H 'Content-Type: application/json' \
  --data-binary @events/reader/payload_invalid.json "$READER_URL"
```

Валідний запит повертає `200` і профіль:

```json
{"reader":{"name":"Олена Коваль","email":"Reader@example.com"},"status":"normalized"}
```

Пробіли в імені згортаються, краї рядків очищаються, домен email переводиться
в нижній регістр. Локальна частина email зберігає регістр. Функція не зберігає
профіль і не виводить персональні поля в логи.
Некоректний JSON, відсутні поля й помилковий email повертають `400` із nil Go
error. Додатково перевіряються base64, UTF-8, один JSON-об’єкт, невідомі поля,
ліміт 64 KiB (`413`) та метод POST (`405` для прямого виклику іншого методу).

## SAM

```bash
make sam-build
make sam-invoke
make sam-api
# В іншому терміналі:
curl -i -H 'Content-Type: application/json' \
  --data-binary @events/reader/payload_valid.json http://127.0.0.1:3000/readers/normalize
```

`sam build --build-in-source` не копіює локальні CLI та runtime-папки в scratch
директорію. SAM-пакети містять лише відповідний `bootstrap`.
SAM-шаблон показує HTTP-маршрути; автоматичний S3-тригер налаштований Terraform.

## Terraform і перевірки

[Промпт та розбір кожного змістовного рядка](docs/TERRAFORM_REVIEW.md) пояснюють
провайдера, три execution roles, scoped IAM, API Gateway, Lambda permissions,
S3 notification та зовнішній state. Lambda мають `provided.al2023`, Linux
`bootstrap` і архітектуру, узгоджену зі збіркою. Provider lock-файл зберігається в Git.

`make smoke` перевіряє Lambda invoke, HTTP-відповіді обох маршрутів,
автоматичне створення мініатюри за новим унікальним S3-ключем та повторну обробку
тієї самої події. Ручного fallback замість автоматичного тригера немає.
JSON-відповіді та зображення записуються лише до зовнішньої папки evidence.

`make bench` виконує 10 пар cold/warm. Видаляється лише контейнер вибраної
навчальної функції. Для Docker у VM задайте `LESSON12_DOCKER_WRAPPER` — шлях
до власного виконуваного SSH wrapper, що приймає одну команду. Вимірюється
клієнтський час із CLI, HTTP і Docker startup; це не AWS Init Duration.

GitHub Actions перевіряє форматування, `go vet`, race-тести, Linux Lambda
пакування, `terraform fmt` і `validate`. Логи, результати, скриншоти та фінальний
звіт зберігаються окремо від Git. Підготовка до демонстрації:
[сценарій](docs/DEMO_SCRIPT.md).

## Serverless чи постійний сервер

Для рідкісної обробки пожертв і нових обкладинок я обрав би serverless,
оскільки ці задачі природно запускаються подіями. Нормалізація профілю теж
вкладається в короткий stateless-виклик. Холодний старт може додати затримку,
тому його треба враховувати для інтерактивних запитів. Основний LibraTrack API
зі стабільним трафіком і PostgreSQL доцільно залишити на постійному сервері.
Так простіше керувати з’єднаннями з БД і довгими сесіями. Для цього проєкту
я поєднав би постійний API з подієвими Lambda для фонової обробки.

## Зупинка

`make down` зупиняє лише Floci, запущений цим Compose-проєктом, і зберігає дані.
Для окремо запущеної VM використовуйте її штатний порядок зупинки.
Не виконуйте legacy cleanup для Terraform-ресурсів. `scripts/deploy-tf.sh destroy`
потребує явного підтвердження; непорожні S3-бакети захищені `force_destroy=false`.

## English overview

Three Go Lambda functions run locally through Floci: a book-donation webhook,
an S3 thumbnail processor, and a custom HTTP reader-profile normalizer.
Run tests, build the packages, review the Terraform plan, apply that saved plan,
then run `make smoke`. Each function has a separate execution role; only the
thumbnail processor can read/write its two S3 buckets. SAM supports local HTTP
invocation. Evidence, logs, state and the final screenshot report stay outside Git.
Development takes place on `develop`, with changes reviewed through a PR into `main`.

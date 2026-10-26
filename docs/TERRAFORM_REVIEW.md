# Terraform: промпт і розбір рядок за рядком

Ця конфігурація підготовлена з AI-асистентом для фактичних трьох функцій.
Нижче подано пояснення кожного непорожнього рядка п’яти `.tf` файлів;
порожні рядки лише розділяють блоки. Таблиця є матеріалом для особистого
рев’ю студента, а не твердженням, що він уже прочитав усі рядки.

## Промпт генерації

```text
Підготуй Terraform для локального Floci (hashicorp/aws ~> 6.0):
3 Go Lambda: webhook (10 с, 256 МБ), thumbnail (30 с, 512 МБ),
reader (10 с, 256 МБ), provided.al2023, bootstrap, zip із ../build/,
узгоджена x86_64/arm64 архітектура та source_code_hash.
API Gateway REST: POST /webhook і POST /readers/normalize, AWS_PROXY, dev.
Окрема IAM execution role кожній функції. Створи log groups з retention 7 днів;
кожній ролі дозволь лише CreateLogStream/PutLogEvents у власній групі.
Лише thumbnail має GetObject у covers та PutObject у thumbnails.
S3 ObjectCreated з prefix covers/ викликає thumbnail; звузь permission
за source bucket і account. HTTP permissions звузь до stage, POST та path.
Задай залежності й redeployment trigger API та create_before_destroy.
Непорожні бакети не видаляй автоматично. Provider використовує лише локальні
endpoints і test/test. Додай змінні, outputs, local backend із зовнішнім path.
Поясни кожен рядок, IAM scope і припущення. Нічого не застосовуй у хмарі AWS.
```

## Рішення після порівняння з вихідним прикладом

- Спільну execution role розділено: webhook і reader не мають S3-доступу.
- Log groups створює Terraform; тому Lambda не потрібне CreateLogGroup.
  CreateLogStream і PutLogEvents обмежено власною групою та її streams.
- API Gateway може викликати кожну функцію лише через свій POST path у dev.
- S3 permission має конкретні bucket ARN та source account; notification
  обмежена prefix `covers/`, output зберігається в іншому бакеті.
- `force_destroy=false` зберігає захист від випадкового видалення непорожніх бакетів.
- API deployment залежить від методів, інтеграцій і permissions, а trigger
  включає значення конфігурації, а не лише ідентифікатори ресурсів.
- State і збережений plan перебувають поза checkout. Provider lock-файл входить до Git.
- 10/30 секунд і 256/512 МБ — початкові навчальні налаштування, не результат p99-тюнінгу.
- `authorization=NONE` обрано для локального демо. Для публічного сервісу потрібен
  окремо спроєктований механізм автентифікації; цю конфігурацію не розгортали в AWS.

Відсутність `Action="*"` сама по собі не доводить least privilege: слід перевірити,
чи кожен конкретний дозвіл потрібен саме функції, яка отримує роль.
Успішний виклик на емуляторі теж не є доказом IAM-поведінки реального AWS.

## Джерела для перевірки рішень

- [API Gateway deployment: dependencies, triggers, lifecycle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment).
- [Lambda та наявні CloudWatch log groups](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-loggroups.html).
- [Floci Docker configuration](https://floci.io/floci/configuration/docker/).

## versions.tf

| Рядок | Код | Пояснення та обмеження |
|---|---|---|
| 1 | `terraform {` | Відкриває налаштування Terraform CLI, backend та providers. |
| 2 | `backend "local" {}` | Продовження багаторядкового опису параметра; на створення ресурсів не впливає. |
| 3 | `required_version = ">= 1.5"` | Мінімальна версія Terraform CLI; provider версіонується окремо. |
| 5 | `required_providers {` | Оголошує потрібні providers. |
| 6 | `aws = {` | Елемент вкладеної map; значення використовується батьківським блоком. |
| 7 | `source  = "hashicorp/aws"` | Офіційний provider hashicorp/aws із Terraform Registry. |
| 8 | `version = "~> 6.0"` | Дозволена серія AWS provider 6.x; точний вибір і checksums зафіксовані lock-файлом. |
| 9 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 10 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 11 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |

## provider.tf

| Рядок | Код | Пояснення та обмеження |
|---|---|---|
| 1 | `# Провайдер спрямовано на Floci (http://localhost:4566).` | Коментар: пояснює налаштування і не виконується Terraform. |
| 2 | `# Ендпоїнт треба вказати для КОЖНОГО сервісу, який використовує конфігурація.` | Коментар: пояснює налаштування і не виконується Terraform. |
| 3 | `provider "aws" {` | Конфігурує AWS provider для Floci; усі endpoints нижче локальні. |
| 4 | `region     = var.region` | Регіон ресурсів усередині емулятора; не вибір віддаленої AWS-хмари. |
| 5 | `access_key = "test"` | Тестове локальне значення test, не реальний ключ доступу. |
| 6 | `secret_key = "test"` | Тестове локальне значення test, не секрет акаунта AWS. |
| 8 | `skip_credentials_validation = true` | Не виконує перевірку реальних AWS credentials для локального емулятора. |
| 9 | `skip_metadata_api_check     = true` | Не звертається до EC2 Instance Metadata Service цього ПК. |
| 10 | `skip_requesting_account_id  = false` | false дозволяє отримати локальний account ID через налаштований STS endpoint. |
| 11 | `s3_use_path_style           = true` | Використовує /bucket/key без wildcard DNS для S3. |
| 13 | `endpoints {` | Перевизначає всі використані AWS endpoints на локальний Floci. |
| 14 | `apigateway     = var.floci_endpoint` | Спрямовує API Gateway API на локальний endpoint. |
| 15 | `cloudwatchlogs = var.floci_endpoint` | Спрямовує CloudWatch Logs API на локальний endpoint. |
| 16 | `iam            = var.floci_endpoint` | Спрямовує IAM API на локальний endpoint. |
| 17 | `lambda         = var.floci_endpoint` | Спрямовує Lambda control/invoke API на локальний endpoint. |
| 18 | `s3             = var.floci_endpoint` | Спрямовує S3 API на локальний endpoint. |
| 19 | `sts            = var.floci_endpoint` | Спрямовує STS API на локальний endpoint, включно з caller identity. |
| 20 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 21 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |

## variables.tf

| Рядок | Код | Пояснення та обмеження |
|---|---|---|
| 1 | `variable "project_name" {` | Оголошує параметр конфігурації; тип, default і validation задані нижче. |
| 2 | `description = "Prefix shared by the lesson's Lambda functions and API."` | Пояснює призначення налаштування; саме по собі ресурсів не створює. |
| 3 | `type        = string` | Дозволяє лише рядкове значення параметра. |
| 4 | `default     = "libratrack"` | Значення за замовчуванням; його можна змінити через TF_VAR або tfvars. |
| 5 | `validation {` | Починає перевірку вхідної змінної. |
| 6 | `condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.project_name))` | Перевіряє допустиме значення до створення ресурсів. |
| 7 | `error_message = "Use a lowercase prefix of 1 to 40 letters, digits or hyphens."` | Пояснення відмови validation для некоректного значення. |
| 8 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 9 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 11 | `variable "region" {` | Оголошує параметр конфігурації; тип, default і validation задані нижче. |
| 12 | `description = "Регіон AWS (у Floci працює будь-який опублікований регіон)."` | Пояснює призначення налаштування; саме по собі ресурсів не створює. |
| 13 | `type        = string` | Дозволяє лише рядкове значення параметра. |
| 14 | `default     = "us-east-1"` | Значення за замовчуванням; його можна змінити через TF_VAR або tfvars. |
| 15 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 17 | `variable "floci_endpoint" {` | Оголошує параметр конфігурації; тип, default і validation задані нижче. |
| 18 | `description = "Адреса Floci."` | Пояснює призначення налаштування; саме по собі ресурсів не створює. |
| 19 | `type        = string` | Дозволяє лише рядкове значення параметра. |
| 20 | `default     = "http://localhost:4566"` | Значення за замовчуванням; його можна змінити через TF_VAR або tfvars. |
| 21 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 23 | `variable "lambda_architecture" {` | Оголошує параметр конфігурації; тип, default і validation задані нижче. |
| 24 | `description = <<-EOT` | Пояснює призначення налаштування; саме по собі ресурсів не створює. |
| 25 | `Архітектура Lambda: "x86_64" або "arm64". МАЄ збігатися з тим, як зібрано` | Продовження багаторядкового опису параметра; на створення ресурсів не впливає. |
| 26 | `бінарник (GOARCH) і з архітектурою Docker-хоста — Floci за замовчуванням` | Продовження багаторядкового опису параметра; на створення ресурсів не впливає. |
| 27 | `запускає контейнери в архітектурі хоста. scripts/env.sh виставляє` | Продовження багаторядкового опису параметра; на створення ресурсів не впливає. |
| 28 | `TF_VAR_lambda_architecture автоматично.` | Продовження багаторядкового опису параметра; на створення ресурсів не впливає. |
| 29 | `EOT` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 30 | `type        = string` | Дозволяє лише рядкове значення параметра. |
| 31 | `default     = "x86_64"` | Значення за замовчуванням; його можна змінити через TF_VAR або tfvars. |
| 33 | `validation {` | Починає перевірку вхідної змінної. |
| 34 | `condition     = contains(["x86_64", "arm64"], var.lambda_architecture)` | Перевіряє допустиме значення до створення ресурсів. |
| 35 | `error_message = "lambda_architecture має бути x86_64 або arm64."` | Пояснення відмови validation для некоректного значення. |
| 36 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 37 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 39 | `variable "covers_bucket" {` | Оголошує параметр конфігурації; тип, default і validation задані нижче. |
| 40 | `type    = string` | Дозволяє лише рядкове значення параметра. |
| 41 | `default = "libratrack-covers"` | Значення за замовчуванням; його можна змінити через TF_VAR або tfvars. |
| 42 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 44 | `variable "thumbnails_bucket" {` | Оголошує параметр конфігурації; тип, default і validation задані нижче. |
| 45 | `type    = string` | Дозволяє лише рядкове значення параметра. |
| 46 | `default = "libratrack-thumbnails"` | Значення за замовчуванням; його можна змінити через TF_VAR або tfvars. |
| 47 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 49 | `variable "stage_name" {` | Оголошує параметр конфігурації; тип, default і validation задані нижче. |
| 50 | `type    = string` | Дозволяє лише рядкове значення параметра. |
| 51 | `default = "dev"` | Значення за замовчуванням; його можна змінити через TF_VAR або tfvars. |
| 52 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |

## main.tf

| Рядок | Код | Пояснення та обмеження |
|---|---|---|
| 1 | `locals {` | Відкриває обчислювані локальні значення; окремих ресурсів не створює. |
| 2 | `functions = {` | Описує набір функцій та їхні початкові timeout/memory налаштування. |
| 3 | `webhook   = { timeout = 10, memory = 256 }` | Елемент map: ключ пов’язує функцію з її timeout/memory або resource_id/path. |
| 4 | `thumbnail = { timeout = 30, memory = 512 }` | Елемент map: ключ пов’язує функцію з її timeout/memory або resource_id/path. |
| 5 | `reader    = { timeout = 10, memory = 256 }` | Елемент map: ключ пов’язує функцію з її timeout/memory або resource_id/path. |
| 6 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 7 | `routes = {` | Пов’язує ключ функції з повним HTTP-шляхом і resource ID. |
| 8 | `webhook = { resource_id = aws_api_gateway_resource.webhook.id, path = "/webhook" }` | Елемент map: ключ пов’язує функцію з її timeout/memory або resource_id/path. |
| 9 | `reader  = { resource_id = aws_api_gateway_resource.normalize.id, path = "/readers/normalize" }` | Елемент map: ключ пов’язує функцію з її timeout/memory або resource_id/path. |
| 10 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 11 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 13 | `data "aws_caller_identity" "current" {}` | Читає локальний account ID через STS для обмеження S3 permission. |
| 15 | `resource "aws_s3_bucket" "covers" {` | Створює вхідний бакет для обкладинок; його об’єкти читає лише thumbnail. |
| 16 | `bucket        = var.covers_bucket` | Вказує ім’я/ID відповідного бакета; посилання створює залежність між ресурсами. |
| 17 | `force_destroy = false` | false забороняє Terraform автоматично очищати непорожній бакет під час destroy. |
| 18 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 20 | `resource "aws_s3_bucket" "thumbnails" {` | Створює окремий вихідний бакет; це запобігає циклу S3-тригера на власний результат. |
| 21 | `bucket        = var.thumbnails_bucket` | Вказує ім’я/ID відповідного бакета; посилання створює залежність між ресурсами. |
| 22 | `force_destroy = false` | false забороняє Terraform автоматично очищати непорожній бакет під час destroy. |
| 23 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 25 | `data "aws_iam_policy_document" "assume" {` | Формує trust policy: хто може прийняти роль. Це не дозвіл доступу до S3 чи логів. |
| 26 | `statement {` | Починає окремий IAM statement; Effect за замовчуванням у policy_document — Allow. |
| 27 | `actions = ["sts:AssumeRole"]` | Перелік конкретних дозволених API-дій; оцінюємо не лише назву, а й потрібність цій ролі. |
| 28 | `principals {` | Оголошує довіреного суб’єкта trust policy. |
| 29 | `type        = "Service"` | Тип principal, тип інтеграції або тип змінної — визначається поточним блоком. |
| 30 | `identifiers = ["lambda.amazonaws.com"]` | Довірений service principal Lambda; інші суб’єкти не включені. |
| 31 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 32 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 33 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 35 | `resource "aws_cloudwatch_log_group" "function" {` | Створює окрему групу логів для кожної з трьох функцій. |
| 36 | `for_each          = local.functions` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 37 | `name              = "/aws/lambda/${var.project_name}-${each.key}"` | Задає ім’я ресурсу або inline policy; each.key розрізняє функції. |
| 38 | `retention_in_days = 7` | Зберігає групу логів 7 днів замість безстрокового накопичення. |
| 39 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 41 | `resource "aws_iam_role" "function" {` | Створює три окремі execution roles замість однієї спільної. |
| 42 | `for_each           = local.functions` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 43 | `name               = "${var.project_name}-${each.key}-role"` | Задає ім’я ресурсу або inline policy; each.key розрізняє функції. |
| 44 | `assume_role_policy = data.aws_iam_policy_document.assume.json` | Підставляє JSON trust policy, що дозволяє сервісу Lambda прийняти роль. |
| 45 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 47 | `data "aws_iam_policy_document" "logs" {` | Формує політику запису лише у власну групу логів кожної функції. |
| 48 | `for_each = local.functions` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 49 | `statement {` | Починає окремий IAM statement; Effect за замовчуванням у policy_document — Allow. |
| 50 | `actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]` | Перелік конкретних дозволених API-дій; оцінюємо не лише назву, а й потрібність цій ролі. |
| 51 | `resources = ["${aws_cloudwatch_log_group.function[each.key].arn}:*"]` | ARN scope дозволу. Суфікс /* обмежений об’єктами бакета, :* — streams власної log group. |
| 52 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 53 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 55 | `resource "aws_iam_role_policy" "logs" {` | Прикріплює відповідну inline log policy до кожної ролі. |
| 56 | `for_each = local.functions` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 57 | `name     = "write-own-logs"` | Задає ім’я ресурсу або inline policy; each.key розрізняє функції. |
| 58 | `role     = aws_iam_role.function[each.key].id` | Вибирає execution role або роль для inline policy; thumbnail S3 policy не прикріплюється HTTP-функціям. |
| 59 | `policy   = data.aws_iam_policy_document.logs[each.key].json` | Підставляє сформований policy document у прикріплену inline policy. |
| 60 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 62 | `data "aws_iam_policy_document" "thumbnail_s3" {` | Формує лише два S3-дозволи: читати source objects і писати output objects. |
| 63 | `statement {` | Починає окремий IAM statement; Effect за замовчуванням у policy_document — Allow. |
| 64 | `actions   = ["s3:GetObject"]` | Перелік конкретних дозволених API-дій; оцінюємо не лише назву, а й потрібність цій ролі. |
| 65 | `resources = ["${aws_s3_bucket.covers.arn}/*"]` | ARN scope дозволу. Суфікс /* обмежений об’єктами бакета, :* — streams власної log group. |
| 66 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 67 | `statement {` | Починає окремий IAM statement; Effect за замовчуванням у policy_document — Allow. |
| 68 | `actions   = ["s3:PutObject"]` | Перелік конкретних дозволених API-дій; оцінюємо не лише назву, а й потрібність цій ролі. |
| 69 | `resources = ["${aws_s3_bucket.thumbnails.arn}/*"]` | ARN scope дозволу. Суфікс /* обмежений об’єктами бакета, :* — streams власної log group. |
| 70 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 71 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 73 | `resource "aws_iam_role_policy" "thumbnail_s3" {` | Додає S3-політику виключно ролі thumbnail. |
| 74 | `name   = "read-covers-write-thumbnails"` | Задає ім’я ресурсу або inline policy; each.key розрізняє функції. |
| 75 | `role   = aws_iam_role.function["thumbnail"].id` | Вибирає execution role або роль для inline policy; thumbnail S3 policy не прикріплюється HTTP-функціям. |
| 76 | `policy = data.aws_iam_policy_document.thumbnail_s3.json` | Підставляє сформований policy document у прикріплену inline policy. |
| 77 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 79 | `resource "aws_lambda_function" "function" {` | Створює три Lambda з окремих Linux ZIP-пакетів. |
| 80 | `for_each         = local.functions` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 81 | `function_name    = "${var.project_name}-${each.key}"` | Фіксує ім’я функції; `${each.key}` розрізняє пакети й ролі. |
| 82 | `role             = aws_iam_role.function[each.key].arn` | Вибирає execution role або роль для inline policy; thumbnail S3 policy не прикріплюється HTTP-функціям. |
| 83 | `runtime          = "provided.al2023"` | OS-only runtime provided.al2023 для Go bootstrap; не застарілий go1.x. |
| 84 | `architectures    = [var.lambda_architecture]` | Має відповідати GOARCH збірки: amd64 → x86_64, arm64 → arm64. |
| 85 | `handler          = "bootstrap"` | Ім’я executable bootstrap у корені ZIP для provided runtime. |
| 86 | `filename         = "${path.module}/../build/${each.key}.zip"` | Шлях до пакета конкретної функції відносно terraform module; пакет має бути зібраний. |
| 87 | `source_code_hash = filebase64sha256("${path.module}/../build/${each.key}.zip")` | SHA-256 ZIP у base64; зміна коду стає видимою плану Terraform. |
| 88 | `timeout          = each.value.timeout` | Ліміт часу конкретної функції з local.functions; потребує перевірки на реальному навантаженні. |
| 89 | `memory_size      = each.value.memory` | Обсяг пам’яті конкретної функції; впливає на доступні ресурси виконання. |
| 90 | `environment {` | Оголошує environment variables конкретної Lambda. |
| 91 | `variables = each.key == "thumbnail" ? { OUTPUT_BUCKET = aws_s3_bucket.thumbnails.bucket } : {}` | OUTPUT_BUCKET передається лише thumbnail; HTTP-функції отримують порожню map. |
| 92 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 93 | `depends_on = [aws_iam_role_policy.logs, aws_iam_role_policy.thumbnail_s3]` | Явний порядок створення: політики до функцій, permissions до notification/deployment. |
| 94 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 96 | `resource "aws_api_gateway_rest_api" "api" {` | Створює REST API для двох HTTP-функцій. |
| 97 | `name = "${var.project_name}-api"` | Задає ім’я ресурсу або inline policy; each.key розрізняє функції. |
| 98 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 100 | `resource "aws_api_gateway_resource" "webhook" {` | Створює кореневий шлях /webhook. |
| 101 | `rest_api_id = aws_api_gateway_rest_api.api.id` | Пов’язує об’єкт із конкретним REST API. |
| 102 | `parent_id   = aws_api_gateway_rest_api.api.root_resource_id` | Визначає батьківський шлях: корінь API або /readers. |
| 103 | `path_part   = "webhook"` | Один сегмент шляху; вкладення визначається parent_id. |
| 104 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 106 | `resource "aws_api_gateway_resource" "readers" {` | Створює батьківський шлях /readers. |
| 107 | `rest_api_id = aws_api_gateway_rest_api.api.id` | Пов’язує об’єкт із конкретним REST API. |
| 108 | `parent_id   = aws_api_gateway_rest_api.api.root_resource_id` | Визначає батьківський шлях: корінь API або /readers. |
| 109 | `path_part   = "readers"` | Один сегмент шляху; вкладення визначається parent_id. |
| 110 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 112 | `resource "aws_api_gateway_resource" "normalize" {` | Створює вкладений шлях /readers/normalize. |
| 113 | `rest_api_id = aws_api_gateway_rest_api.api.id` | Пов’язує об’єкт із конкретним REST API. |
| 114 | `parent_id   = aws_api_gateway_resource.readers.id` | Визначає батьківський шлях: корінь API або /readers. |
| 115 | `path_part   = "normalize"` | Один сегмент шляху; вкладення визначається parent_id. |
| 116 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 118 | `resource "aws_api_gateway_method" "post" {` | Оголошує POST на двох маршрутах. |
| 119 | `for_each      = local.routes` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 120 | `rest_api_id   = aws_api_gateway_rest_api.api.id` | Пов’язує об’єкт із конкретним REST API. |
| 121 | `resource_id   = each.value.resource_id` | Вибирає конкретний ресурс шляху з map routes. |
| 122 | `http_method   = "POST"` | Метод клієнтського маршруту POST, узгоджений із method та integration. |
| 123 | `authorization = "NONE"` | NONE прийнятне лише для цього локального навчального демо. |
| 124 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 126 | `resource "aws_api_gateway_integration" "http" {` | З’єднує кожен маршрут із відповідною Lambda через proxy event. |
| 127 | `for_each                = local.routes` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 128 | `rest_api_id             = aws_api_gateway_rest_api.api.id` | Пов’язує об’єкт із конкретним REST API. |
| 129 | `resource_id             = each.value.resource_id` | Вибирає конкретний ресурс шляху з map routes. |
| 130 | `http_method             = aws_api_gateway_method.post[each.key].http_method` | Метод клієнтського маршруту POST, узгоджений із method та integration. |
| 131 | `integration_http_method = "POST"` | POST — метод виклику Lambda API, окремий від методу клієнта. |
| 132 | `type                    = "AWS_PROXY"` | Lambda proxy integration: handler отримує API Gateway event і повертає statusCode/headers/body. |
| 133 | `uri                     = aws_lambda_function.function[each.key].invoke_arn` | Invoke ARN відповідної функції; зв’язує integration з Lambda. |
| 134 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 136 | `resource "aws_lambda_permission" "apigateway" {` | Надає API Gateway право виклику конкретної функції з конкретного маршруту. |
| 137 | `for_each      = local.routes` | Створює окремий екземпляр для кожного ключа map; each.key обирає саме його роль/функцію. |
| 138 | `statement_id  = "AllowAPIGatewayPOST"` | Унікальний ідентифікатор statement у resource policy кожної функції. |
| 139 | `action        = "lambda:InvokeFunction"` | Лише lambda:InvokeFunction; це право виклику, не execution role функції. |
| 140 | `function_name = aws_lambda_function.function[each.key].function_name` | Фіксує ім’я функції; `${each.key}` розрізняє пакети й ролі. |
| 141 | `principal     = "apigateway.amazonaws.com"` | Сервіс API Gateway або S3, якому дозволяється виклик. |
| 142 | `source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/${var.stage_name}/POST${each.value.path}"` | Обмежує джерело виклику конкретним stage/методом/path або вхідним бакетом. |
| 143 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 145 | `resource "aws_api_gateway_deployment" "api" {` | Створює snapshot конфігурації API та забезпечує redeployment за зміни маршруту/інтеграції. |
| 146 | `rest_api_id = aws_api_gateway_rest_api.api.id` | Пов’язує об’єкт із конкретним REST API. |
| 147 | `triggers = {` | Елемент вкладеної map; значення використовується батьківським блоком. |
| 148 | `redeployment = sha1(jsonencode([` | Hash конфігурації маршрутів; зміна значення створює новий deployment. |
| 149 | `for key, route in local.routes : {` | Перебирає обидва HTTP-маршрути, щоб включити їхню фактичну конфігурацію до deployment hash. |
| 150 | `path   = route.path` | Повний HTTP path, що входить до hash deployment. |
| 151 | `uri    = aws_api_gateway_integration.http[key].uri` | Invoke ARN відповідної функції; зв’язує integration з Lambda. |
| 152 | `method = aws_api_gateway_method.post[key].http_method` | Метод, що входить до hash deployment. |
| 153 | `type   = aws_api_gateway_integration.http[key].type` | Тип principal, тип інтеграції або тип змінної — визначається поточним блоком. |
| 154 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 155 | `]))` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 156 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 157 | `lifecycle {` | Налаштовує порядок зміни ресурсу. |
| 158 | `create_before_destroy = true` | Новий API deployment створюється до видалення старого, на який посилається stage. |
| 159 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 160 | `depends_on = [aws_lambda_permission.apigateway]` | Явний порядок створення: політики до функцій, permissions до notification/deployment. |
| 161 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 163 | `resource "aws_api_gateway_stage" "stage" {` | Публікує deployment на stage dev (або значенні змінної). |
| 164 | `rest_api_id   = aws_api_gateway_rest_api.api.id` | Пов’язує об’єкт із конкретним REST API. |
| 165 | `deployment_id = aws_api_gateway_deployment.api.id` | Вибирає snapshot API для опублікованого stage. |
| 166 | `stage_name    = var.stage_name` | Назва stage також має збігатися з source_arn permissions та URL outputs. |
| 167 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 169 | `resource "aws_lambda_permission" "s3_thumbnail" {` | Дозволяє лише вхідному S3-бакету цього account викликати thumbnail. |
| 170 | `statement_id   = "AllowCoversS3Invoke"` | Унікальний ідентифікатор statement у resource policy кожної функції. |
| 171 | `action         = "lambda:InvokeFunction"` | Лише lambda:InvokeFunction; це право виклику, не execution role функції. |
| 172 | `function_name  = aws_lambda_function.function["thumbnail"].function_name` | Фіксує ім’я функції; `${each.key}` розрізняє пакети й ролі. |
| 173 | `principal      = "s3.amazonaws.com"` | Сервіс API Gateway або S3, якому дозволяється виклик. |
| 174 | `source_arn     = aws_s3_bucket.covers.arn` | Обмежує джерело виклику конкретним stage/методом/path або вхідним бакетом. |
| 175 | `source_account = data.aws_caller_identity.current.account_id` | Account ID із локального STS; додаткове обмеження джерела S3. |
| 176 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 178 | `resource "aws_s3_bucket_notification" "covers" {` | Підключає автоматичні S3 ObjectCreated notifications до thumbnail. |
| 179 | `bucket = aws_s3_bucket.covers.id` | Вказує ім’я/ID відповідного бакета; посилання створює залежність між ресурсами. |
| 180 | `lambda_function {` | Описує notification для однієї Lambda. |
| 181 | `lambda_function_arn = aws_lambda_function.function["thumbnail"].arn` | Ціль автоматичної S3-події — лише thumbnail. |
| 182 | `events              = ["s3:ObjectCreated:*"]` | Лише ObjectCreated; інші типи подій не запускають цю notification. |
| 183 | `filter_prefix       = "covers/"` | Лише ключі covers/ потрапляють до обробника. |
| 184 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 185 | `depends_on = [aws_lambda_permission.s3_thumbnail]` | Явний порядок створення: політики до функцій, permissions до notification/deployment. |
| 186 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |

## outputs.tf

| Рядок | Код | Пояснення та обмеження |
|---|---|---|
| 1 | `output "api_id" {` | Оголошує вихідне значення для CLI та сценаріїв демонстрації. |
| 2 | `value = aws_api_gateway_rest_api.api.id` | Повертає ID, імена функцій або фактичний локальний URL; output ресурсів не створює. |
| 3 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 5 | `output "webhook_url_floci" {` | Оголошує вихідне значення для CLI та сценаріїв демонстрації. |
| 6 | `value = "${var.floci_endpoint}/restapis/${aws_api_gateway_rest_api.api.id}/${var.stage_name}/_user_request_/webhook"` | Повертає ID, імена функцій або фактичний локальний URL; output ресурсів не створює. |
| 7 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 9 | `output "reader_url_floci" {` | Оголошує вихідне значення для CLI та сценаріїв демонстрації. |
| 10 | `value = "${var.floci_endpoint}/restapis/${aws_api_gateway_rest_api.api.id}/${var.stage_name}/_user_request_/readers/normalize"` | Повертає ID, імена функцій або фактичний локальний URL; output ресурсів не створює. |
| 11 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |
| 13 | `output "function_names" {` | Оголошує вихідне значення для CLI та сценаріїв демонстрації. |
| 14 | `value = { for key, function in aws_lambda_function.function : key => function.function_name }` | Повертає ID, імена функцій або фактичний локальний URL; output ресурсів не створює. |
| 15 | `}` | Закриває відповідний блок, колекцію, виклик функції або heredoc; самостійних дозволів не додає. |

## Особисте рев’ю перед здачею

Пройдіть таблиці разом із файлами, поясніть різницю між trust policy,
execution permissions і resource policy. Перевірте, що timeout та пам’ять
є початковими параметрами, а локальний успішний запуск не доводить AWS IAM.
Прочитайте фактичний plan із власної зовнішньої runtime-папки перед apply.
Запишіть власними словами, які ресурси й дозволи були неочікуваними та чому.
Факт особистого перегляду не позначено виконаним автоматично.

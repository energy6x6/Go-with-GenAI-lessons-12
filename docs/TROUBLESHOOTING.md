# Розв’язання проблем Lesson 12

Використовуйте актуальні команди з кореневого README. Статус автора архіву
в `ORIGINAL_DEMO_README.md` є історичним контекстом.

| Симптом | Перевірка та дія |
|---|---|
| Docker daemon недоступний | Запустіть Docker Desktop або Docker Engine у VM; перевірте `docker version` |
| Floci на Docker Desktop 20.10 повертає `java.net.BindException: Permission denied` при Lambda invoke | SAM може працювати незалежно; для Floci використайте Ubuntu VM з актуальним Docker Engine |
| Lambda container запускається, але invocation timeout | Перевірте callback Runtime API та спільну мережу. Compose задає `FLOCI_SERVICES_LAMBDA_DOCKER_HOST_OVERRIDE=floci`, щоб не обирати IP іншої VPC-мережі |
| Порт 4566 вже зайнятий | Створіть окремий Compose-проєкт із `FLOCI_PORT=4567`; узгодьте AWS endpoint, NAT forwarding та Terraform variable |
| Mac використовує Floci у VirtualBox NAT | Передайте порт гостя на `127.0.0.1` хоста; `AWS_ENDPOINT_URL` має вказувати на переспрямований порт |
| `aws`, `sam` або `terraform` не знайдено | Встановіть CLI або додайте їх у `.tools/bin`; виконайте `source scripts/env.sh` |
| `exec format error` | Узгодьте Docker host architecture, Linux GOARCH, SAM Architectures та Terraform lambda_architecture |
| Terraform просить reconfigure backend | Перевірте `LESSON12_RUNTIME_DIR` і один раз виконайте `TF_CLI_ARGS_init=-reconfigure make plan-tf` |
| Terraform показує відсутні ресурси іншого середовища | Не змішуйте state між емуляторами. Для кожного окремого Floci потрібна власна runtime-папка |
| `Saved plan is stale` | Стан або код змінився: повторіть `make plan-tf`, прочитайте план, потім apply |
| S3 thumbnail не з’явився | Перевірте notification, prefix covers/, OUTPUT_BUCKET та логи thumbnail. Smoke завершується FAIL; ручний invoke не замінює доказ автоматичного тригера |
| S3 API має неправильний endpoint | Lambda має бачити Floci через Docker DNS, а клієнт S3 використовує path-style; перевірте injected AWS_ENDPOINT_URL |
| Legacy CLI helper відмовляється працювати | Ресурсами вже керує Terraform. Використовуйте збережений plan і не змішуйте ownership |
| Bench не знаходить warm container | Перевірте Docker host/SSH wrapper та окрему мережу lesson12-floci; не запускайте ephemeral mode під час paired cold/warm |

Логи та результати зберігаються поза checkout у `LESSON12_EVIDENCE_DIR`.
Для перегляду поточного Floci виконайте `docker logs --tail 100 lesson12-floci`
на тому Docker host, де він запущений. Не видаляйте runtime/state/volume до
збереження доказів; `make down` зупиняє лише локальний Compose-проєкт.

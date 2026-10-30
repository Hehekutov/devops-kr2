# Контрольная работа 2

Кудояров Денис Рустемович, ЭФБО-18-24. Номер в списке 10, вариант 2.

Сервис Flask + Redis опубликован на https://notes.devops.local через Nginx.
Приложение слушает 8002 внутри контейнера, на сервере опубликовано только
127.0.0.1:8002. Redis 7 Alpine не публикует порт; счётчик сохраняется в
именованном томе kr2_redis_data с AOF.

## Файлы

- Dockerfile: python:3.12-slim, UID 999, exec CMD, отдельный слой зависимостей.
- docker-compose.yml: app и redis, сеть backend, проверки готовности,
  restart: unless-stopped, том redis_data.
- deploy/kr2.nginx: отдельный HTTPS vhost и HTTP 301.
- scripts/audit.sh: аудит предыдущих практик и пять проверок КР2.
- docs/evidence: реальные журналы выполнения без действующего пароля.
- docs/report.docx: отчёт по практической работе.

Логика app.py и requirements.txt сохранены. В app.py добавлен только комментарий
с фамилией для проверки кэша.

## Развёртывание

Из корня проекта на компьютере:

```bash
rsync -avz --delete --exclude=.env --exclude=.git --dry-run ./ devops:kr2/
rsync -avz --delete --exclude=.env --exclude=.git ./ devops:kr2/
```

На сервере от devops, пароль генерируется только при отсутствии .env:

```bash
cd ~/kr2
unset REDIS_PASSWORD
if [ ! -f .env ]; then
  (umask 077; printf 'REDIS_PASSWORD=%s\n' "$(openssl rand -hex 32)" > .env)
fi
chmod 600 .env
docker compose up -d --build --wait
docker compose ps
docker compose top
curl -fsS http://127.0.0.1:8002/health
```

Не экспортировать REDIS_PASSWORD в оболочке: env_file должен совпадать с
источником подстановки requirepass. Не печатать docker compose config или полный
docker inspect в отчёт: они содержат секрет. Шаблонный пароль в унаследованной
истории main не используется на сервере.

## HTTPS

На сервере:

```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /etc/ssl/private/kr2.key -out /etc/ssl/certs/kr2.crt \
  -subj '/CN=notes.devops.local' \
  -addext 'subjectAltName=DNS:notes.devops.local'
sudo chmod 600 /etc/ssl/private/kr2.key
sudo chown root:root /etc/ssl/private/kr2.key
sudo install -m 644 deploy/kr2.nginx /etc/nginx/sites-available/kr2
sudo ln -s /etc/nginx/sites-available/kr2 /etc/nginx/sites-enabled/kr2
sudo nginx -t && sudo systemctl reload nginx
```

В Windows hosts: `192.168.56.101 notes.devops.local`. При активном VPN требуется
исключение для этого адреса. Проверка с компьютера:

```bash
scp devops:/etc/ssl/certs/kr2.crt ~/kr2.crt
curl -I http://notes.devops.local/
curl --cacert ~/kr2.crt https://notes.devops.local/
curl --cacert ~/kr2.crt https://notes.devops.local/whoami
curl -m 3 http://notes.devops.local:8002/health
```

Последняя команда должна завершиться ошибкой доступа. Для браузера потребуется
явное доверие учебному самоподписанному сертификату; системное доверие не менялось.

## Аудит и восстановление

`sudo bash ~/devops-course-2026/scripts/audit.sh` возвращает 0. Дополнительная
проверка обнаруживает публикацию `8002:8002`, возвращая 1. Штатная публикация
восстановлена. Правила UFW и devops-site не изменены.

Для проверки сохранности данных использовать `docker compose down` без `-v`,
затем `docker compose up -d --wait`. Том не удалять. Снимки VirtualBox:
06-before-kr2 и 07-kr2. Ветка kr2/variant-2 предназначена для открытого PR в main;
до защиты не сливать.

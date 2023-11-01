# Деплой приложений. Ruby on Rails

Модуль [Terraform](https://www.terraform.io) и роли [Ansible](https://www.ansible.com) для выполнения задания "Деплой приложений. Ruby on Rails".

Для запуска необходимы `Environment variables`

```bash
export AWS_ACCESS_KEY=AKIA...
export AWS_SECRET_KEY=U4Up...
export DO_API_TOKEN=65f2...
```

## TL;DR

В качестве менеджера версий Ruby используется [rvm](https://rvm.io), сервера приложений — [Phusion Passenger®](https://www.phusionpassenger.com/docs/tutorials/what_is_passenger/).

Ruby и приложение выполняются в пользовательском окружении.

Для запуска приложения в Production-окружении используется директива `RAILS_ENV=production` при сборке приложения, для миграций, генерации `assets` и режима работы Nginx с сервером приложений. Используется СУБД PostgreSQL в соответствии с декларацией

```yaml
production:
  <<: postgresql
```

в файле `config/database.yml` приложения.

SSL-терминацию и проксирование запросов к серверу приложений обеспечивает Nginx с поддержкой модуля `libnginx-mod-http-passenger` из [репозитория](https://www.phusionpassenger.com/docs/tutorials/deploy_to_production/installations/oss/digital_ocean/ruby/nginx/) Phusion Passenger®.

Для получение и настройки wildcard сертификата Let’s Encrypt используется [acme.sh](https://github.com/acmesh-official/acme.sh).

## Terraform

Для получения данных из `Environment variables` используется [`jq`](https://stedolan.github.io/jq/), утилита для обработки JSON в командной строке.

Все необходимые переменные для создания `droplet'а` [Digital Ocean](https://www.digitalocean.com) и А-записи в [Amazon Route 53](https://aws.amazon.com/ru/route53/) определены в секции `Variables` файла `main.tf`.

Количество `droplet'ов` и, соответственно, А-записей определяется длиной списка `local.hosts`.

Выполняется загрузка на создаваемые хосты публичных ключей `SSH` пользователя, создание `inventory.yml` для последующего запуска `ansible-playbook` и вывод в консоль публичного IP и DNS имени для каждого созданного хоста.

В шаблоне `inventory.tmpl` предусмотрено опциональное разнесение по группам `loadbalancer` и `webapp` по принципу именования хостов в `local.hosts`. В текущей редакции предполагается использование префиксов `lb-[*]` и `www-[*]`.

## Ansible

Глобальные переменные для всех ролей Ansible определяются в файле `group_vars/all.yml`, локальные, при необходимости, в папке `defaults` соответствующей роли.

Файл `playbook.yml`:

```yaml
---
- hosts: all
  become: true

  roles:
    - common
    - user
    - postgres
    - role: ruby
      become: yes
      become_user: ruby
      tags:
        - ruby
    - passenger
    - letsencrypt
```

1. **Common:** полное обновление всех пакетов, установка основных пакетов. Перезагрузка при необходимости.
2. **User:** Создание пользователя для Web-приложения, включение в группу `sudo` и настройка публичного ключа SSH.
3. **Postgres:** установка СУБД и сопутствующих пакетов, создание пользователя и базы.
4. **Ruby:** установка RVM, требуемой версии Ruby, bundler. Производится проверка наличия и установка ключей GPG для RVM и определение списка завиисимостей для установки Ruby с последующей их установкой. Назначается версия Ruby по умолчанию и для текущего использования.

   1. **Gpg:** вызывается из основного модуля при отсутствии ключей GPG, необходимых для установки RVM.

   2. **Webapp:** вызывается из основного модуля, клонирует приложение в подготовленную заранее папку, устанавливает необходимые gem'ы, исключая предназначенные для окружений Test и Development, настраивает подключение к базе данных для окружения Production с генерацией криптографического ключа и соответствующей правкой в `config/secrets.yml`. Выполняет миграции и генерацию assets для окружения Production.

5. **Passenger:** настройка репозитория и установка Nginx с поддержкой модуля `libnginx-mod-http-passenger`, настройка конфигурации Nginx и сайта в http-режиме. Удаление default-сайта (назначается глобальной переменной).
Окружение для выполнения приложения задаётся директивой `passenger_app_env` в шаблоне сайта, переменная — в `group_vars/all.yml`.

6. **Letsencrypt:** получение и настройка SSL сертификата (host & wildcard), настройка сайта в https-режиме, удаление временного http-сайта.

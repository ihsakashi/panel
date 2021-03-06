#!/bin/ash
## Ensure we are in /app

cd /app

mkdir -p /var/log/panel/logs/ /var/log/supervisord/ /var/log/nginx/ /var/log/php7/ \
&& rm -rf /app/storage/logs/ \
&& chmod 777 /var/log/panel/logs/ \
&& ln -s /var/log/panel/logs/ /app/storage/

## check for .env file and generate app keys if missing
if [ -f /app/var/.env ]; then
  echo "external vars exist."
  rm -rf /app/.env

  ln -s /app/var/.env /app/
else
  echo "external vars don't exist."
  rm -rf /app/.env
  touch /app/var/.env

  ## manually generate a key because key generate --force fails
  if [ -z $APP_KEY ]; then
     echo -e "Generating key."
     APP_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
     echo -e "Generated app key: $APP_KEY"
     echo -e "APP_KEY=$APP_KEY" > /app/var/.env
  else
    echo -e "APP_KEY exists in environment, using that."
    echo -e "APP_KEY=$APP_KEY" > /app/var/.env
  fi

  ln -s /app/var/.env /app/
fi

echo "Checking if https is required."
if [ -f /etc/nginx/conf.d/default.conf ]; then
  echo "Using nginx config already in place."
  if [ $LE_EMAIL ]; then
    echo "Checking for cert update"
    certbot certonly -d $(echo $APP_URL | sed 's~http[s]*://~~g')  --standalone -m $LE_EMAIL --agree-tos -n
  else
    echo "No letsencrypt email is set"
  fi
else
  echo "Checking if letsencrypt email is set."
  if [ -z $LE_EMAIL ]; then
    echo "No letsencrypt email is set using http config."
    cp docker/default.conf /etc/nginx/conf.d/default.conf
  else
    echo "writing ssl config"
    cp docker/default_ssl.conf /etc/nginx/conf.d/default.conf
    echo "updating ssl config for domain"
    sed -i "s|<domain>|$(echo $APP_URL | sed 's~http[s]*://~~g')|g" /etc/nginx/conf.d/default.conf
    echo "generating certs"
    certbot certonly -d $(echo $APP_URL | sed 's~http[s]*://~~g')  --standalone -m $LE_EMAIL --agree-tos -n
  fi
fi

## check for DB up before starting the panel
echo "Checking database status."
until nc -z -v -w30 $DB_HOST 3306

do
  echo "Waiting for database connection..."
  # wait for 5 seconds before check again
  sleep 5
done

## make sure the db is set up
echo -e "Migrating and Seeding D.B"
php artisan migrate --force
php artisan db:seed --force

## start cronjobs for the queue
echo -e "Starting cron jobs."
crond -L /var/log/crond -l 5

## install yarn stuff
yarn install --production
yarn add cross-env
yarn run build:production

echo -e "Starting supervisord."
exec "$@"

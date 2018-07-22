#!/bin/sh

set -o errexit

command=$1

upgrade () {

  echo Upgrade ...

  if [ ! -L /seafile/seafile-server-latest ]; then
    echo No /seafile/seafile-server-latest!
    exit 1
  fi

  curdir=$(readlink /seafile/seafile-server-latest) # like seafile-server-5.1.1
  curver=${curdir##*-} # 5.1.1
  curverm=${curver%.*} # 5.1

  if [ "$curver" == "${SEAFILE_VERSION}" ]; then
    echo Already on ${SEAFILE_VERSION}
    exit 0
  fi

  # download and unpack
  cd /seafile
  wget -c https://download.seadrive.org/seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz
  tar xf seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz

  cd seafile-server-${SEAFILE_VERSION}

  # run major (4.x -> 5.x) and minor (5.x -> 5.y) upgrade scripts
  upgrade_sh=$(ls upgrade/upgrade_${curverm}* || true)
  while [ -n "$upgrade_sh" ]; do
    echo Upgrade from $curverm ...
    yes | $upgrade_sh
    # get next
    curverm=${upgrade_sh##*_}
    curverm=${curverm%.sh}
    upgrade_sh=$(ls upgrade/upgrade_${curverm}* || true)
  done

  # run maintenance (5.x.y -> 5.x.z) upgrade script
  echo Maintenance upgrade ...
  yes | upgrade/minor-upgrade.sh
  
  # seahub (gunicorn) to run in foreground
  sed -i 's/daemon = True/daemon = False/' /seafile/seafile-server-latest/runtime/seahub.conf

}


init () {

  echo Init ...
  if [ -L /seafile/seafile-server-latest ]; then
    echo /seafile/seafile-server-latest exists. Assuming this is upgrade
    upgrade
    exit 0
  fi

  # download and unpack
  cd /seafile
  wget -c https://download.seadrive.org/seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz
  tar xf seafile-server_${SEAFILE_VERSION}_x86-64.tar.gz

  # this directory is used to exchange upload files between seahub and seaf-server
  mkdir -p /seafile/tmp

  # generate configuration files
  env -i PYTHON=python2.7 python /seafile/seafile-server-${SEAFILE_VERSION}/setup-seafile-mysql.py auto \
    --server-name ${SERVER_NAME} --server-ip ${SERVER_HOSTNAME} \
    --seafile-dir /seafile/data \
    --use-existing-db 1 \
    --mysql-host ${MYSQL_HOST} \
    --mysql-user ${MYSQL_USER} --mysql-user-passwd ${MYSQL_PASSWORD} \
    --ccnet-db ${CCNETDB} --seafile-db ${SEAFILEDB} --seahub-db ${SEAHUBDB}

  # put correct urls
  sed -i 's|SERVICE_URL.*|SERVICE_URL = https://'$SERVER_HOSTNAME'|' /seafile/conf/ccnet.conf
  echo "FILE_SERVER_ROOT = 'https://$SERVER_HOSTNAME/seafhttp'" >> /seafile/conf/seahub_settings.py

  # seahub (gunicorn) to run in foreground
  sed -i 's/daemon = True/daemon = False/' /seafile/seafile-server-latest/runtime/seahub.conf
  # seahub to log to stdout
  echo 'LOGGING = {}' >> /seafile/conf/seahub_settings.py

  # put admin account creds into a file
  echo "{ \"email\": \"$ADMINEMAIL\", \"password\": \"$ADMINPASSWORD\" }" > /seafile/conf/admin.txt

}


ccnet () {

  echo Starting ccnet ...
  exe=/seafile/seafile-server-latest/seafile/bin/ccnet-server
  SEAFILE_LD_LIBRARY_PATH=/seafile/seafile-server-latest/seafile/lib/:/seafile/seafile-server-latest/seafile/lib64
  exec env -i LD_LIBRARY_PATH=$SEAFILE_LD_LIBRARY_PATH \
    $exe -F /seafile/conf -c /seafile/ccnet --logfile -

}


seaf () {

  echo Starting seaf ...
  exe=/seafile/seafile-server-latest/seafile/bin/seaf-server
  SEAFILE_LD_LIBRARY_PATH=/seafile/seafile-server-latest/seafile/lib/:/seafile/seafile-server-latest/seafile/lib64
  exec env -i LD_LIBRARY_PATH=$SEAFILE_LD_LIBRARY_PATH \
    $exe -F /seafile/conf -c /seafile/ccnet --foreground --seafdir /seafile/data --log -

}


seahub () {

  echo Starting seahub ...
  gunicorn_conf=/seafile/seafile-server-latest/runtime/seahub.conf
  gunicorn_exe=/seafile/seafile-server-latest/seahub/thirdpart/gunicorn
  PYTHONPATH=/seafile/seafile-server-latest/seafile/lib/python2.7/site-packages:/seafile/seafile-server-latest/seafile/lib64/python2.7/site-packages:/seafile/seafile-server-latest/seahub:/seafile/seafile-server-latest/seahub/thirdpart
  if [ -f /seafile/conf/admin.txt ]; then
    # let's wait for ccnet and seaf
    sleep 10
    env -i PYTHONPATH=$PYTHONPATH CCNET_CONF_DIR=/seafile/ccnet SEAFILE_CENTRAL_CONF_DIR=/seafile/conf \
      python /seafile/seafile-server-latest/check_init_admin.py
  fi
  exec env -i PYTHONPATH=$PYTHONPATH TMPDIR=/seafile/tmp \
    SEAFILE_CONF_DIR=/seafile/data CCNET_CONF_DIR=/seafile/ccnet SEAFILE_CENTRAL_CONF_DIR=/seafile/conf \
    python $gunicorn_exe seahub.wsgi:application -c "${gunicorn_conf}" -b "0.0.0.0:8000" --preload
}


case $command in
  init) init ;;
  upgrade) upgrade ;;
  ccnet) ccnet ;;
  seaf) seaf ;;
  seahub) seahub ;;
  *)
    echo "specify command argument, one of: init ccnet seaf seahub"
    exit 1
    ;;
esac




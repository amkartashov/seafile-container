FROM debian:9

VOLUME /seafile
# Seafile Web UI
EXPOSE 8000
# Seafile File server
EXPOSE 8082

ENV SEAFILE_VERSION 6.3.2
ENV SERVER_NAME seafile
ENV SERVER_HOSTNAME seafile.com
ENV MYSQL_HOST mysql
ENV MYSQL_USER root
ENV MYSQL_PASSWORD secret
ENV CCNETDB ccnet
ENV SEAFILEDB seafile
ENV SEAHUBDB seahub
ENV ADMINEMAIL admin@seafile.com
ENV ADMINASSWORD secret

ENTRYPOINT ["/bin/entrypoint"]

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python2.7 libpython2.7 python-setuptools \
    python-imaging python-ldap python-urllib3 ffmpeg python-pip python-mysqldb python-memcache wget

RUN pip install pillow moviepy

RUN mkdir -p /seafile

ADD entrypoint.sh /bin/entrypoint
RUN chmod +x /bin/entrypoint


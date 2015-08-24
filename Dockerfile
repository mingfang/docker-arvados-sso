FROM ubuntu:14.04
 
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
RUN locale-gen en_US en_US.UTF-8
ENV LANG en_US.UTF-8
RUN echo "export PS1='\e[1;31m\]\u@\h:\w\\$\[\e[0m\] '" >> /root/.bashrc

#Runit
RUN apt-get install -y runit 
CMD export > /etc/envvars && /usr/sbin/runsvdir-start
RUN echo 'export > /etc/envvars' >> /root/.bashrc

#Utilities
RUN apt-get install -y vim less net-tools inetutils-ping wget curl git telnet nmap socat dnsutils netcat tree htop unzip sudo software-properties-common jq psmisc

#For building Ruby
RUN apt-get install -y \
    gawk g++ gcc make libc6-dev libreadline6-dev zlib1g-dev libssl-dev \
    libyaml-dev libsqlite3-dev sqlite3 autoconf libgdbm-dev \
    libncurses5-dev automake libtool bison pkg-config libffi-dev
#Ruby
ENV CONFIGURE_OPTS --disable-install-doc
RUN curl http://ftp.ruby-lang.org/pub/ruby/2.1/ruby-2.1.6.tar.gz | tar -xz && \
    cd ruby* && \
    ./configure --disable-install-doc && \
    make -j8 && \
    make install && \
    cd / && \
    rm -rf ruby*
RUN gem install bundler

#PostgreSQL
RUN apt-get install -y libpq-dev postgresql

#Defaults
ENV UUID_PREFIX=arvados SECRET_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx RAILS_ENV=production

#SSO Server
RUN git clone --depth 1 https://github.com/curoverse/sso-devise-omniauth-provider.git
RUN cd sso-devise-omniauth-provider && \
    bundle install --without=development
RUN cd sso-devise-omniauth-provider && \
    cp config/application.yml.example config/application.yml && \
    sed -i -e "s|uuid_prefix:.*|uuid_prefix: ${UUID_PREFIX}|" config/application.yml && \
    sed -i -e "s|secret_token:.*|secret_token: ${SECRET_TOKEN}|" config/application.yml && \
    sed -i -e "s|allow_account_registration:.*|allow_account_registration: true|" config/application.yml 

#Configure SSO database
RUN cd sso-devise-omniauth-provider && \
    cp config/database.yml.example config/database.yml
ADD sso.ddl /
ADD create-arvados-server-client.rb /
ADD create-test-user.rb /
RUN sudo -u postgres /usr/lib/postgresql/9.3/bin/pg_ctl start -w -D /etc/postgresql/9.3/main && \
    sudo -u postgres psql < sso.ddl && \
    cd sso-devise-omniauth-provider && \
    bundle exec rake db:setup && \
    bundle exec rake assets:precompile && \
    sudo -u postgres /usr/lib/postgresql/9.3/bin/pg_ctl stop -D /etc/postgresql/9.3/main -m smart

#Initialize SSO Server
RUN sudo -u postgres /usr/lib/postgresql/9.3/bin/pg_ctl start -w -D /etc/postgresql/9.3/main && \
    cd sso-devise-omniauth-provider && \
    bundle exec rails runner /create-arvados-server-client.rb && \
    bundle exec rails runner /create-test-user.rb && \
    bundle exec passenger start & \
    until /usr/bin/curl http://127.0.0.1:3000; do echo "Waiting for SSO Server to come online..."; sleep 3; done && \
    cd sso-devise-omniauth-provider && \
    bundle exec passenger stop && \
    sudo -u postgres /usr/lib/postgresql/9.3/bin/pg_ctl stop -D /etc/postgresql/9.3/main -m smart

#Add runit services
ADD sv /etc/service 


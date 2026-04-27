# Build deps for ruby + native gems, mysql client, image libs.
pkg_install \
  build-essential git curl ca-certificates gnupg dirmngr lsb-release pkg-config \
  autoconf bison \
  libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev libgdbm-dev \
  libncurses5-dev libxml2-dev libxslt1-dev \
  tzdata logrotate \
  imagemagick libvips \
  libmysqlclient-dev default-mysql-client

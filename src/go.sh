#!/bin/bash

   rst="$(tput sgr0)"
   bld="$(tput bold)"
   und="$(tput sgr 0 1)"

   red="$(tput setaf 1)"
 green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
 white="$(tput setaf 7)"

bgreen="${bld}${green}"
bwhite="${bld}${white}"

[ ! -z "$PIBOX_DEBUG" ] && set -x

RESULT=0
function show_result {
    if [ $? -eq 0 ]
    then
        echo "${green}[SUCCESS]${rst}"
    else
        echo "${red}[FAILURE]${rst}"
        RESULT=$(( RESULT + 1))
    fi
}

echo "
                        ${bgreen} __     __   __      ${rst}
                        ${bgreen}|__) | |__) /  \ \_/ ${rst}
                        ${bgreen}|    | |__) \__/ / \ ${rst}
"

#RTORRENT_DEFAULT is defined in the Dockerfile to "/opt/rtorrent"
echo $p
user="${PIBOX_USER:-"hadopi"}"
pass="${PIBOX_PASS:-"fuckyou"}"
p="${RTORRENT_VOLUME:-$RTORRENT_DEFAULT}"
sed -i "s,$RTORRENT_DEFAULT,$p,g" /etc/nginx/sites-enabled/rutorrent.conf
if [ ! -f "/opt/rtorrent/.rtorrent.rc" ]
then
  cp /rtorrent/.rtorrent.rc /opt/rtorrent/.rtorrent.rc
fi
sed -i "s,$RTORRENT_DEFAULT,$p,g" /opt/rtorrent/.rtorrent.rc

echo "$bwhite ==> DEFAULT PATH $p $rst"
echo
echo "$bwhite ==> RUTORRENT setup$rst"

mkdir -p $p/{session,share,watch}
rm -f $p/session/rtorrent.lock # force unlock

echo
echo "$bwhite ==> CREDENTIALS$rst"

pwdfile="$p/.htpasswd"
if [ ! -f "$pwdfile" ]
then
    echo -n "   > Setting up username / password for WEB access... "
    printf "${user}:$(openssl passwd -crypt "${pass}")\n" >> "${pwdfile}"
    show_result $?
    echo "   >    username: $user"
    echo "   >    password: $pass"
else
    echo "   > A password file already exists... [SKIPPING]"
fi

if [ ! -z "${PIBOX_FTP}" ] && [ "${PIBOX_FTP}" = "yes" ]
then
    echo -n "   > Setting up username/password for FTP access... "
    echo -e "${pass}\n${pass}" > /tmp/passin
    pure-pw useradd "$user" -d "$p/share" -u ftpuser -m < /tmp/passin 2>&1 >/dev/null && pure-pw mkdb
    show_result $?

    rm /tmp/passin
    sed -i "s,PIBOX_PUBLICIP,${PIBOX_PUBLICIP}," /etc/supervisor/conf.d/ftp.conf
else
    echo -n "   > Desactivating FTP access... "
    mv /etc/supervisor/conf.d/ftp.{conf,inactive}
    show_result $?
fi

echo
echo "$bwhite ==> SSL$rst"

if [[ ! -e $p/ssl.key ]] || [[ ! -e $p/ssl.crt ]]
then
    echo -n "   > Creating SSL certificate and key files... "
    # the generated certificate is also a self-signed CA and can be added to you Trusted CA
    # in order to get a "green address bar" in your browser and avoid the ssl warning
    openssl req \
        -days 3650 \
        -x509 \
        -sha256 \
        -nodes \
        -newkey rsa:4096 \
        -keyout "$p/ssl.key" \
        -subj "/C=FR/L=Paris/O=Seedboxes/OU=Pibox/CN=${URL:-"localhost"}" \
        -out "$p/ssl.crt" \

    show_result $?

    #chmod 600 $p/ssl.key
else
    echo "   > A certificate file already exists... [SKIPPING]"
fi

echo
echo "$bwhite ==> SERVICES$rst"

echo -n "   > stopping root rtorrent "
pkill rtorrent
show_result $?
echo -n "   > Starting rtorrent... "
service rtorrent start
show_result $?

echo -n "   > Starting php... "
/etc/init.d/php7.2-fpm start
show_result $?

echo -n "   > Starting http server... "
nginx -t
/etc/init.d/nginx start
show_result $?

echo
if [ $RESULT -eq 0 ]
then
  echo "$bgreen ==> PIBOX STARTED SUCCESSFULLY$rst"
  supervisord -n -e error -c /etc/supervisor/supervisord.conf
else
  echo "$bred ==> PIBOX FAILED TO START :("
  echo "$red   > check above failure and ask for help if needed: https://github.com/seedboxes/pibox/issues"

fi

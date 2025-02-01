#!/usr/bin/bash
DefaultDomain="";
DefaultDomainWWW="";
IsNeedWWW="";#値===wwwなら、www設定する。
IpAddress=`hostname -i`
UserName="";
UserPassword="";
if [[ `id -u` -ne 0 ]]; then
  # rootユーザーにしか実行させない
  printf '\033[31m%s\033[m\n' '------------------';
  echo "ルート権限が必要です。"
  echo "sudo su -"
  printf '\033[31m%s\033[m\n' '------------------';
  exit 1
fi
#####引数取得
function view_help(){
    printf '\033[31m%s\033[m\n' '------------------';
    cat <<EOM
    
Usage: 
[必須]...
EOM
    printf '\033[31m%s\033[m\n' ' -d     domain    デフォルトドメイン(例: ryo1999.com)';
    printf '\033[31m%s\033[m\n' ' -n     dirname   ユーザ名';
    printf '\033[31m%s\033[m\n' ' -p     password  ユーザパスワード';
    cat <<EOM
    
[任意]...
 -h          help表示
 -w          www設定
EOM
    printf '\033[31m%s\033[m\n' '------------------';
  exit 2
}
if [[ $1 = "" ]]; then # 引数がない場合
    view_help
    exit 2
fi
function set_domain() {
    DefaultDomain=${OPTARG};
    DefaultDomainWWW=www.${DefaultDomain};
}
function set_username() {
  UserName=${OPTARG};
}
function set_password() {
  UserPassword=${OPTARG};
}
function set_www() {
    IsNeedWWW=www
}
while getopts ":d:n:p:wh" optKey; do
  case "$optKey" in
    d)
      # -aの場合の実行内容
      set_domain
      ;;
    n)
      set_username
      ;;
    p)
      set_password
      ;;
    w)
      # -bの場合の実行内容
      set_www
      ;;
    '-h'|'--help'|* )
      # -h、--helpの場合、もしくは-a、-b以外の場合の実行内容
      view_help
      ;;
    *)
      #エラー
      
      ;;
  esac
done
#####引数取得終了
if [ "$UserName" = "" ] || [ "$UserPassword" = "" ] || [ "$DefaultDomain" = "" ]; then # 引数がない場合
    view_help
    exit 2
fi
IFACE="eth0"
MyIp=$(/sbin/ip -f inet -o addr show "${IFACE}" | cut -d\  -f 7 | cut -d/ -f 1)
getIP=$(nslookup $DefaultDomain | grep -Eo '[0-9]{1,3}.[0-9]{1,3}.[1-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}' | tail -n 1 )
if [ "${MyIp}" != "${getIP}" ]; then # 引数がない場合
    echo "ドメインが向いていません";
    exit 2
fi
#ユーザー設定
setup_users(){
    #カテルユーザー追加
    useradd ${UserName}
    echo ${UserPassword} | passwd --stdin "${UserName}"
    chmod o+x /home/${UserName}
}
setup_users
#VirtualHost登録
setup_virtual(){
  if [ -n $IsNeedWWW ] && [ "$IsNeedWWW" = "www" ]; then
    cat > /etc/httpd/virtual.d/${DefaultDomain}.conf << EOF
<VirtualHost *:80>
  ServerName ${DefaultDomain}
  ServerAlias ${DefaultDomainWWW}
#WWWあり
RewriteEngine On
RewriteCond %{HTTP_HOST} !^www\. [NC]
RewriteRule ^(.*)$ http://www.%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
#SSL強制
#RewriteEngine On
#RewriteCond %{HTTPS} off
#RewriteCond %{REQUEST_URI} !^/\.well-known/*
#RewriteRule ^.*$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L,NE]
  DocumentRoot /home/${UserName}/public_html
  ServerAdmin server@ryo1999.com
  DirectoryIndex index.php index.html
  <IfModule mod_userdir.c>
    UserDir disable
  </IfModule>
  
  #9072でphpバージョン変更可能
  <FilesMatch \\.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9074"
  </FilesMatch>
  <Directory "/home/${UserName}/public_html">
    Options ExecCGI Includes MultiViews FollowSymLinks
    AllowOverride ALL
    AddType application/x-httpd-cgi .cgi .pl
  </Directory>
</VirtualHost>
EOF
  else
    cat > /etc/httpd/virtual.d/${DefaultDomain}.conf << EOF
<VirtualHost *:80>
  ServerName ${DefaultDomain}
#WWWなし
RewriteEngine On
RewriteCond %{HTTP_HOST} ^www\.(.*) [NC]
RewriteRule ^(.*)$ http://%1%{REQUEST_URI} [R=301,L]
#SSL強制
#RewriteEngine On
#RewriteCond %{HTTPS} off
#RewriteCond %{REQUEST_URI} !^/\.well-known/*
#RewriteRule ^.*$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L,NE]
  DocumentRoot /home/${UserName}/public_html
  ServerAdmin server@ryo1999.com
  DirectoryIndex index.php index.html
  <IfModule mod_userdir.c>
    UserDir disable
  </IfModule>
  
  #9072でphpバージョン変更可能
  <FilesMatch \\.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9074"
  </FilesMatch>
  <Directory "/home/${UserName}/public_html">
    Options ExecCGI Includes MultiViews FollowSymLinks
    AllowOverride ALL
    AddType application/x-httpd-cgi .cgi .pl
  </Directory>
</VirtualHost>
EOF
  fi
}
setup_virtual;
service httpd restart
checkHttpd=`service httpd status`
if [[ "$checkHttpd" == *failed* ]]; then
  echo "HTTP ERROR; /etc/httpd/virtual.d/${DefaultDomain}.confを削除してください";
  exit;
fi
make_sslfile(){
    mkdir /root/ssl
    cd /root/ssl
    mkdir $DefaultDomain
    cd $DefaultDomain
    #生成
    if [ -n $IsNeedWWW ] && [ "$IsNeedWWW" = "www" ]; then
        cat > /root/ssl/$DefaultDomain/makecrt.sh << EOF
certbot certonly --non-interactive --agree-tos --webroot -w /home/$UserName/public_html/ -d $DefaultDomain -d $DefaultDomainWWW --email server@ryo1999.com
EOF
    else
        cat > /root/ssl/$DefaultDomain/makecrt.sh << EOF
certbot certonly --non-interactive --agree-tos --webroot -w /home/$UserName/public_html/ -d $DefaultDomain --email server@ryo1999.com
EOF
    fi
    
    chmod 775 /root/ssl/$DefaultDomain/makecrt.sh
    /root/ssl/$DefaultDomain/makecrt.sh
    #リンク
    ln -sf /etc/letsencrypt/live/$DefaultDomain/cert.pem /root/ssl/$DefaultDomain/crt.pem
    ln -sf /etc/letsencrypt/live/$DefaultDomain/fullchain.pem /root/ssl/$DefaultDomain/ca.pem
    ln -sf /etc/letsencrypt/live/$DefaultDomain/privkey.pem /root/ssl/$DefaultDomain/key.pem
}
make_sslfile
#VirtualHost登録
setup_virtual_ssl(){
  if [ -n $IsNeedWWW ] && [ "$IsNeedWWW" = "www" ]; then
    cat > /etc/httpd/virtual.d/${DefaultDomain}.conf << EOF
<VirtualHost *:80>
  ServerName ${DefaultDomain}
  ServerAlias ${DefaultDomainWWW}
#WWWあり
RewriteEngine On
RewriteCond %{HTTP_HOST} !^www\. [NC]
RewriteRule ^(.*)$ http://www.%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
#SSL強制
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteCond %{REQUEST_URI} !^/\.well-known/*
RewriteRule ^.*$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L,NE]
  DocumentRoot /home/${UserName}/public_html
  ServerAdmin server@ryo1999.com
  DirectoryIndex index.php index.html
  <IfModule mod_userdir.c>
    UserDir disable
  </IfModule>
  
  #9072でphpバージョン変更可能
  <FilesMatch \\.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9074"
  </FilesMatch>
  <Directory "/home/${UserName}/public_html">
    Options ExecCGI Includes MultiViews FollowSymLinks
    AllowOverride ALL
    AddType application/x-httpd-cgi .cgi .pl
  </Directory>
</VirtualHost>
<VirtualHost *:443>
  ServerName ${DefaultDomain}
  ServerAlias ${DefaultDomainWWW}
#WWWあり
RewriteEngine On
RewriteCond %{HTTP_HOST} !^www\. [NC]
RewriteRule ^(.*)$ http://www.%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
  SSLEngine on
  SSLCertificateKeyFile /root/ssl/${DefaultDomain}/key.pem
  SSLCertificateFile /root/ssl/${DefaultDomain}/crt.pem
  SSLCertificateChainFile /root/ssl/${DefaultDomain}/ca.pem
  SSLProtocol all -SSLv2 -SSLv3
  ErrorLog  /home/${UserName}/logs/ssl_error_log
  CustomLog /home/${UserName}/logs/ssl_access_log combined env=!no_log
  DocumentRoot /home/${UserName}/public_html
  ServerAdmin server@ryo1999.com
  DirectoryIndex index.htm index.html index.php index.cgi index.pl
  <IfModule mod_userdir.c>
    UserDir disable
  </IfModule>
  
  #9072でphpバージョン変更可能
  <FilesMatch \\.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9074"
  </FilesMatch>

  <Directory "/home/${UserName}/public_html">
    Options ExecCGI Includes MultiViews FollowSymLinks
    AllowOverride ALL
    AddType application/x-httpd-cgi .cgi .pl
  </Directory>
</VirtualHost>
EOF
  else
    cat > /etc/httpd/virtual.d/${DefaultDomain}.conf << EOF
<VirtualHost *:80>
  ServerName ${DefaultDomain}
#WWWなし
RewriteEngine On
RewriteCond %{HTTP_HOST} ^www\.(.*) [NC]
RewriteRule ^(.*)$ http://%1%{REQUEST_URI} [R=301,L]
#SSL強制
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteCond %{REQUEST_URI} !^/\.well-known/*
RewriteRule ^.*$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L,NE]
  DocumentRoot /home/${UserName}/public_html
  ServerAdmin server@ryo1999.com
  DirectoryIndex index.php index.html
  <IfModule mod_userdir.c>
    UserDir disable
  </IfModule>
  
  #9072でphpバージョン変更可能
  <FilesMatch \\.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9074"
  </FilesMatch>
  <Directory "/home/${UserName}/public_html">
    Options ExecCGI Includes MultiViews FollowSymLinks
    AllowOverride ALL
    AddType application/x-httpd-cgi .cgi .pl
  </Directory>
</VirtualHost>
<VirtualHost *:443>
  ServerName ${DefaultDomain}
  
#WWWなし
RewriteEngine On
RewriteCond %{HTTP_HOST} ^www\.(.*) [NC]
RewriteRule ^(.*)$ http://%1%{REQUEST_URI} [R=301,L]
  SSLEngine on
  SSLCertificateKeyFile /root/ssl/${DefaultDomain}/key.pem
  SSLCertificateFile /root/ssl/${DefaultDomain}/crt.pem
  SSLCertificateChainFile /root/ssl/${DefaultDomain}/ca.pem
  SSLProtocol all -SSLv2 -SSLv3
  ErrorLog  /home/${UserName}/logs/ssl_error_log
  CustomLog /home/${UserName}/logs/ssl_access_log combined env=!no_log
  DocumentRoot /home/${UserName}/public_html
  ServerAdmin server@ryo1999.com
  DirectoryIndex index.htm index.html index.php index.cgi index.pl
  <IfModule mod_userdir.c>
    UserDir disable
  </IfModule>

 <Directory "/home/${UserName}/public_html">
    Options ExecCGI Includes MultiViews FollowSymLinks
    AllowOverride ALL
    AddType application/x-httpd-cgi .cgi .pl
  </Directory>
 
  #9072でphpバージョン変更可能
  <FilesMatch \\.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9074"
  </FilesMatch>
</VirtualHost>
EOF
  fi
}
setup_virtual_ssl;
service httpd restart
checkHttpd=`service httpd status`
if [[ "$checkHttpd" == *failed* ]]; then
  # rm -rf /etc/httpd/virtual.d/${DefaultDomain}.conf;
  # userdel -r 〇〇
  # certbot-auto delete --cert-name 〇〇.co.jp
  echo "失敗しました。virtualhost, cerbot, userを削除して再起動してください。";
  exit;
fi
#最後に戻す
export LANG=ja_JP.utf8;
# todo-frontend のイメージ。nginx の公式イメージに画面のファイルと設定を足す
FROM nginx:1.30.6-alpine@sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951
# v1 と v2 は見出しの色だけが違う（docker build の --build-arg VERSION=v2 で切り替える）
ARG VERSION=v1
COPY default.conf /etc/nginx/conf.d/default.conf
COPY index.html app.js /usr/share/nginx/html/
COPY base.css /tmp/base.css
COPY style-${VERSION}.css /tmp/style.css
RUN cat /tmp/base.css /tmp/style.css > /usr/share/nginx/html/style.css \
 && sed -i "s|<span id=\"version\"></span>|<span id=\"version\">${VERSION}</span>|" /usr/share/nginx/html/index.html \
 && rm /tmp/base.css /tmp/style.css

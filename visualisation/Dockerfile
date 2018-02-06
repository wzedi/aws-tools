FROM alpine:latest

RUN apk --update add graphviz \
      python \
      py-pip \
      groff \
      less \
      mailcap \
      ttf-ubuntu-font-family \
      jq \
      && \
   pip install --upgrade awscli==1.14.5 s3cmd==2.0.1 python-magic && \
   apk -v --purge del py-pip && \
   rm /var/cache/apk/*

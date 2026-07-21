FROM curlimages/curl:8.5.0

USER root
RUN apk add --no-cache bind-tools openssl bash

COPY demo-tests.sh /demo-tests.sh
RUN chmod +x /demo-tests.sh

WORKDIR /lab
ENTRYPOINT ["/demo-tests.sh"]

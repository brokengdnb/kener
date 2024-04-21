FROM lsiobase/alpine:3.19 as base

# Define the environment variable
ENV TZ=Etc/CET
ENV PUBLIC_KENER_FOLDER=/config/static/kener
RUN mkdir -p /config/static/kener


RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache \
    nodejs \
    npm && \
  echo "**** cleanup ****" && \
  rm -rf \
    /root/.cache \
    /tmp/*

# set OS timezone specified by docker ENV
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apk add --update-cache \
    rsync \
    openssh-client \
    tzdata \
 && rm -rf /var/cache/apk/* \

COPY docker/cron/ /etc/crontabs/root/15min
# start crond with log level 8 in foreground, output to stderr
CMD ["crond", "-f", "-d", "8"]

ARG data_dir=/config
VOLUME $data_dir
ENV CONFIG_DIR=$data_dir

RUN mkdir -p "${CONFIG_DIR}"

COPY docker/root/ /
COPY docker/configCustom/ /config
# Dir ENVs need to be set before building or else build throws errors
ENV PUBLIC_KENER_FOLDER=/config/static/kener \
    MONITOR_YAML_PATH=/config/monitors.yaml \
    SITE_YAML_PATH=/config/site.yaml

# build requires devDependencies which are not used by production deploy
# so build in a stage so we can copy results to clean "deploy" stage later
FROM base as build

WORKDIR /app

COPY --chown=root:root . /app

# build requires PUBLIC_KENER_FOLDER dir exists so create temporarily
# -- it is non-existent in final stage to allow proper startup and chown'ing/example population
RUN mkdir -p "${CONFIG_DIR}/static" \
    && npm install \
    && chown -R root:root node_modules \
    && npm run kener:build

FROM base as app

# copy package, required libs (npm,nodejs) results of build, prod entrypoint, and examples to be used to populate config dir
# to clean, new stage
COPY --chown=root:root package*.json ./
COPY --from=base /usr/local/bin /usr/local/bin
COPY --from=base /usr/local/lib /usr/local/lib
COPY --chown=root:root scripts /app/scripts
COPY --chown=root:root static /app/static
COPY --chown=root:root config /app/config
COPY --chown=root:root src/lib/helpers.js /app/src/lib/helpers.js
COPY --from=build --chown=root:root /app/build /app/build
COPY --from=build --chown=root:root /app/prod.js /app/prod.js

# Copy the config/static folder from the build stage to the app stage
COPY --from=build --chown=root:root $CONFIG_DIR/static $CONFIG_DIR/static

ENV NODE_ENV=production

# install prod depdendencies and clean cache
RUN npm install --omit=dev \
    && npm cache clean --force \
    && chown -R root:root node_modules
RUN npm install pm2 -g



ARG webPort=3000
ENV PORT=$webPort
EXPOSE $PORT

ENTRYPOINT ["sh", "-c", "if [ $$ -eq 1 ]; then exec /init \"$@\"; else exec unshare --fork --pid --mount-proc /init \"$@\"; fi", "sh"]

# leave entrypoint blank!
# uses LSIO s6-init entrypoint with scripts
# that populate CONFIG_DIR with static dir, monitor/site.yaml when dir is empty
# and chown's all files so they are owned by proper user based on PUID/GUID env

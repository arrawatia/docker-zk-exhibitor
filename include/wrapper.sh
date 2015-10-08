#/bin/bash -e

# Generates the default exhibitor config and launches exhibitor

IP=$(hostname -i)
DEFAULT_AWS_REGION="us-west-2"
DEFAULT_DATA_DIR="/opt/zookeeper/snapshots"
DEFAULT_LOG_DIR="/opt/zookeeper/transactions"
S3_SECURITY=""
HTTP_PROXY=""
DEFAULT_CONFIG_TYPE="FILE"
DEFAULT_CONFIG_CHECK_MS="30000"
: ${CONFIG_TYPE:=$DEFAULT_CONFIG_TYPE}
: ${HOSTNAME:?$MISSING_VAR_MESSAGE}
: ${AWS_REGION:=$DEFAULT_AWS_REGION}
: ${ZK_DATA_DIR:=$DEFAULT_DATA_DIR}
: ${ZK_LOG_DIR:=$DEFAULT_LOG_DIR}
: ${HTTP_PROXY_HOST:=""}
: ${HTTP_PROXY_PORT:=""}
: ${HTTP_PROXY_USERNAME:=""}
: ${HTTP_PROXY_PASSWORD:=""}
: ${CONFIG_CHECK_MS:=$DEFAULT_CONFIG_CHECK_MS}

cat <<- EOF > /opt/exhibitor/defaults.conf
	zookeeper-data-directory=$ZK_DATA_DIR
	zookeeper-install-directory=/opt/zookeeper
	zookeeper-log-directory=$ZK_LOG_DIR
	log-index-directory=$ZK_LOG_DIR
	cleanup-period-ms=300000
	check-ms=$CONFIG_CHECK_MS
	backup-period-ms=600000
	client-port=2181
	cleanup-max-files=20
	backup-max-store-ms=21600000
	connect-port=2888
	observer-threshold=0
	election-port=3888
	zoo-cfg-extra=tickTime\=2000&initLimit\=10&syncLimit\=5&quorumListenOnAllIPs\=true
	auto-manage-instances-settling-period-ms=0
	auto-manage-instances=1
EOF

echo "Environnment : "
echo `env`

echo "Config type: $CONFIG_TYPE"

if [ "$CONFIG_TYPE" == "ZK" ]
then
    : ${ZKCFG_CONNECT?"Need to set ZK_CONNECT"}
    : ${ZKCFG_POLLING_MS:="10000"}
    : ${KUBERNETES_NAMESPACE:=""}
    : ${ZKCFG_ZPATH:="/exhibitor"}
    : ${ZKCFG_RETRY_SLEEP_MS:="1000"}
    : ${ZKCFG_RETRY_TIMES:="3"}
    if [ -n "${KUBERNETES_NAMESPACE}"]
    then
        ZKCFG_ZPATH_ROOT=""
    else
        ZKCFG_ZPATH_ROOT="/${KUBERNETES_NAMESPACE}"
    fi
    ZK_CONFIG_ZPATH="${ZKCFG_ZPATH_ROOT}${ZKCFG_ZPATH}"
    BACKUP_CONFIG="--configtype zookeeper --zkconfigconnect ${ZKCFG_CONNECT} --zkconfigpollms ${ZKCFG_POLLING_MS} --zkconfigzpath ${ZK_CONFIG_ZPATH}"
    BACKUP_CONFIG=${BACKUP_CONFIG}" --zkconfigretry ${ZKCFG_RETRY_SLEEP_MS}:${ZKCFG_RETRY_TIMES} --filesystembackup true"

elif [ "${CONFIG_TYPE}" == "S3" ]
then
  cat <<- EOF > /opt/exhibitor/credentials.properties
    com.netflix.exhibitor.s3.access-key-id=${AWS_ACCESS_KEY_ID}
    com.netflix.exhibitor.s3.access-secret-key=${AWS_SECRET_ACCESS_KEY}
EOF

  echo "backup-extra=throttle\=&bucket-name\=${S3_BUCKET}&key-prefix\=${S3_PREFIX}&max-retries\=4&retry-sleep-ms\=30000" >> /opt/exhibitor/defaults.conf

  S3_SECURITY="--s3credentials /opt/exhibitor/credentials.properties"
  BACKUP_CONFIG="--configtype s3 --s3config ${S3_BUCKET}:${S3_PREFIX} ${S3_SECURITY} --s3region ${AWS_REGION} --s3backup true"

else
  BACKUP_CONFIG="--configtype file --fsconfigdir /opt/zookeeper/local_configs --filesystembackup true"
fi

if [[ -n ${ZK_PASSWORD} ]]; then
	SECURITY="--security web.xml --realm Zookeeper:realm --remoteauth basic:zk"
	echo "zk: ${ZK_PASSWORD},zk" > realm
fi


if [[ -n $HTTP_PROXY_HOST ]]; then
    cat <<- EOF > /opt/exhibitor/proxy.properties
      com.netflix.exhibitor.s3.proxy-host=${HTTP_PROXY_HOST}
      com.netflix.exhibitor.s3.proxy-port=${HTTP_PROXY_PORT}
      com.netflix.exhibitor.s3.proxy-username=${HTTP_PROXY_USERNAME}
      com.netflix.exhibitor.s3.proxy-password=${HTTP_PROXY_PASSWORD}
EOF

    HTTP_PROXY="--s3proxy=/opt/exhibitor/proxy.properties"
fi

exec 2>&1

# If we use exec and this is the docker entrypoint, Exhibitor fails to kill the ZK process on restart.
# If we use /bin/bash as the entrypoint and run wrapper.sh by hand, we do not see this behavior. I suspect
# some init or PID-related shenanigans, but I'm punting on further troubleshooting for now since dropping
# the "exec" fixes it.
#
# exec java -jar /opt/exhibitor/exhibitor.jar \
# 	--port 8181 --defaultconfig /opt/exhibitor/defaults.conf \
# 	--configtype s3 --s3config thefactory-exhibitor:${CLUSTER_ID} \
# 	--s3credentials /opt/exhibitor/credentials.properties \
# 	--s3region us-west-2 --s3backup true

echo "CONFIG:"
echo ${BACKUP_CONFIG}

java -jar /opt/exhibitor/exhibitor.jar \
  --port 8181 --defaultconfig /opt/exhibitor/defaults.conf \
  ${BACKUP_CONFIG} \
  ${HTTP_PROXY} \
  --hostname ${IP} \
  ${SECURITY}

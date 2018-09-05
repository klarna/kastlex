#!/bin/bash -e

KAFKA_VERSION="${1:-1.1}"
IMAGE="zmstone/kafka:${KAFKA_VERSION}"
sudo docker pull $IMAGE

ZK='zookeeper'
KAFKA_1='kafka-1'
CONTAINERS="$ZK $KAFKA_1"

# kill running containers
for i in $CONTAINERS; do sudo docker rm -f $i > /dev/null 2>&1 || true; done

sudo docker run -d \
                -p 2181:2181 \
                --name $ZK \
                $IMAGE run zookeeper

n=0
while [ "$(</dev/tcp/localhost/2181 2>/dev/null && echo OK || echo NOK)" = "NOK" ]; do
  if [ $n -gt 4 ]; then
    echo "timeout waiting for $ZK"
    exit 1
  fi
  n=$(( n + 1 ))
  sleep 1
done

sudo docker run -d \
                -e BROKER_ID=0 \
                -e PLAINTEXT_PORT=9092 \
                -e SSL_PORT=9093 \
                -e SASL_SSL_PORT=9094 \
                -e SASL_PLAINTEXT_PORT=9095 \
                -p 9092-9095:9092-9095 \
                --link $ZK \
                --name $KAFKA_1 \
                $IMAGE run kafka

n=0
while [ "$(sudo docker exec $KAFKA_1 bash -c '/opt/kafka/bin/kafka-topics.sh --zookeeper zookeeper --describe')" != '' ]; do
  if [ $n -gt 4 ]; then
    echo "timeout waiting for $KAFKA_1"
    exit 1
  fi
  n=$(( n + 1 ))
  sleep 1
done

create_topic() {
  TOPIC_NAME="$1"
  shift
  if [ ! -z "$1" ]; then
    PARTITIONS="$1"
    shift
  else
    PARTITIONS=1
  fi
  CMD="/opt/kafka/bin/kafka-topics.sh --zookeeper zookeeper --create --partitions $PARTITIONS --replication-factor 1 --topic $TOPIC_NAME $@"
  sudo docker exec $KAFKA_1 bash -c "$CMD"
}

create_topic _try_to_create_ignore_failure || true
create_topic test-topic
create_topic kastlex
create_topic _kastlex_tokens 2 1 --config cleanup.policy=compact

# this is to warm-up kafka group coordinator
sudo docker exec $KAFKA_1 /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --new-consumer --group test-group --describe > /dev/null 2>&1

# add scram SASL user/pass
sudo docker exec $KAFKA_1 /opt/kafka/bin/kafka-configs.sh --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[iterations=8192,password=ecila],SCRAM-SHA-512=[password=ecila]' --entity-type users --entity-name alice


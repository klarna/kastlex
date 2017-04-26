# KastleX - Kafka REST Proxy in Elixir
Kastle is a REST interface to Kafka cluster, powered by [Brod](https://github.com/klarna/brod) and [Phoenix framework](http://www.phoenixframework.org/).

See also [Kastle](https://github.com/klarna/kastle).

# Get started

    mix deps.get
    mix phoenix.server

To start with an interactive shell:

    iex --sname kastlex -S mix phoenix.server

By default KastleX will try to connect to kafka at localhost:9092 and to zookeeper on localhost:2181.

Default app port is 8092.

# API

## Produce messages

    POST /api/v1/messages/:topic
    POST /api/v1/messages/:topic/:partition

With the first version KastleX will pick a random partition to produce message to.  
Use `Content-type: application/binary`.  
Key is supplied as query parameter `key`.  
Value is request body.  
Successful response: HTTP Status 204 and empty body.  

cURL example (-d implies POST):

    curl -s -i -H "Content-Type: application/binary" localhost:8092/api/v1/messages/foo -d bar

## Fetch messages

    GET /api/v1/messages/:topic/:partition/:offset
    {
      "size": 29,
      "messages": [
        {
          "value": "foo",
          "size": 17,
          "offset": 20,
          "key": null,
          "crc": -91546804
        }
      ],
      "highWmOffset": 21,
      "errorCode": "no_error"
    }

Optional parameters:
  * `max_wait_time`: maximum time in ms to wait for the response, default 1000
  * `min_bytes`: minimum bytes to accumulate in the response, default 1
  * `max_bytes`: maximum bytes to fetch, default 100 kB

## Query available offsets for partition.

    GET /api/v1/offsets/:topic/:partition
    [20]

Optional parameters:
  * `at`: point of interest, `latest`, `earliest`, or a number, default `latest`
  * `max_offsets`: how many offsets to return, integer, default 1

## Consumer groups

    GET /api/v1/consumers
    ["console-consumer-25992"]

    GET /api/v1/consumers/:group_id
    {
        "protocol": "range",
        "partitions": [
            {
                "topic": "kastlex",
                "partition": 0,
                "offset": 20,
                "metadata_encoding": "text",
                "metadata": "",
                "high_wm_offset": 20,
                "expire_time": 1473714215481,
                "commit_time": 1473627815481
            }
        ],
        "members": [
            {
                "subscription": {
                    "version": 0,
                    "user_data_encoding": "text",
                    "user_data": "",
                    "topics": [
                        "kastlex"
                    ]
                },
                "session_timeout": 30000,
                "member_id": "consumer-1-ea5aa1bc-6b14-488f-88f1-26edb2261786",
                "client_id": "consumer-1",
                "client_host": "/127.0.0.1",
                "assignment": {
                    "version": 0,
                    "user_data_encoding": "text",
                    "user_data": "",
                    "topic_partitions": {
                        "kastlex": [
                            0
                        ]
                    }
                }
            }
        ],
        "leader": "consumer-1-ea5aa1bc-6b14-488f-88f1-26edb2261786",
        "group_id": "console-consumer-66960",
        "generation_id": 1
    }


## Topics metadata

    GET /api/v1/topics
    ["kastlex"]

    GET /api/v1/topics/:topic
    {"topic":"kastlex","partitions":[{"replicas":[0],"partition":0,"leader":0,"isr":[0]}],"config":{}}

## Brokers metadata

    GET /api/v1/brokers
    [{"port":9092,"id":0,"host":"localhost","endpoints":["PLAINTEXT://127.0.0.1:9092"]}]

    GET /api/v1/brokers/:broker_id
    {"port":9092,"id":0,"host":"localhost","endpoints":["PLAINTEXT://127.0.0.1:9092"]}

(Yes, this one looks a bit silly)

## List under-replicated partitions

    GET /api/v1/urp
    GET /api/v1/urp/:topic

# Authentication
Authentication is a courtesy of [Guardian](https://github.com/ueberauth/guardian).

There are 2 files, permissions.yml and passwd.yml to configure permissions for different actions.

Example permissions.yml:

    anonymous:
      list_topics: true
      show_topic: all
      list_brokers: true
      show_broker: all
      show_offsets: all
      fetch: all
      list_urps: true
      show_urps: all
      list_groups: true
      show_group: all
    user1:
      produce:
        - kastlex
    admin:
      reload: true
      revoke: true

Anonymous user can do pretty much everything except writing data to kafka.

`user` can write to topic `kastlex`.

`admin` can reload permissions.

`all` means access to all topics, replace it with a list of specific topics when applicable (see for example user.produce).

Example passwd.yml:

    user1:
      password_hash: "$2b$12$3iR64t7Sm.cAHtZs5jkxZehdWQ7knmN/NxmK.X7NBUHfiIAxT4T9y"
    admin:
      password_hash: "$2b$12$gp5pJc/AGclJradJC9DuHe6xJoIe5HOwtAUGe2z7QFeAjvw1eZUKW"

Here we specify password hashes for each user.

`user` has password `user`, `admin` has password `admin`. Simple.

Generate password:

    mix hashpw difficult2guess

To obtain a token users need to login (submit a form with 2 fields, username and password):

    curl localhost:8092/login --data "username=user1&password=user1"
    {"token":"bcrypt hash"}

Get token directly into a shell variable (requires `jq`):

    JWT=$(curl -s localhost:8092/login --data "username=user1&password=user1" | jq -r .token)

Then you can submit authenticated requests via curl as:

    curl -H "Authorization: Bearer $JWT" localhost:8092/admin/reload
    curl -H "Authorization: Bearer $JWT" localhost:8092/api/v1/messages/kastlex/0 -H "Content-type: application/binary" -d 1

# Token storage
It is possible to run KastleX in 2 modes: when tokens are issued with relatively short timespan and administrator does not have any control over them, and when tokens are long-lived, but persisted and can be revoked on demand.

KastleX is using a compacted topic (cleanup_policy=compact) with a single partition in Kafka as a token storage. In order to enable token storage, add the following hook config for Guardian application:

    hooks: Kastlex.TokenStorage

And configuration for TokenStorage:

    config :kastlex, Kastlex.TokenStorage,
      topic: "_kastlex_tokens"

Alternatively set the following environment variable:

    KASTLEX_ENABLE_TOKEN_STORAGE=1

These 2 can be used to alter default storage topic name and default ttl:

    KASTLEX_TOKEN_STORAGE_TOPIC=_kastlex_tokens
    KASTLEX_TOKEN_TTL_SECONDS=315360000

Administrator can use the following API endpoint to revoke a token:

    DELETE  /admin/tokens/:username

Correspinding permission item in permissions.yml file is 'revoke'.

# Deployment to production

## Generate a JWK

    openssl ecparam -name secp521r1 -genkey -noout -out jwk.pem

## Generate a secret key base

    printf "%s" $(openssl rand -base64 32 | tr -d =) > secret_base.key

## Set the following varibles for Kastlex environment

    KASTLEX_SECRET_KEY_BASE=/path/to/secret_base.key
    KASTLEX_JWK_FILE=/path/to/jwk.pem
    KASTLEX_PERMISSIONS_FILE_PATH=/path/to/permissions.yml
    KASTLEX_PASSWD_FILE_PATH=/path/to/passwd.yml
    KASTLEX_KAFKA_CLUSTER=kafka-host1:9092,kafka-host2:9092
    KASTLEX_ZOOKEEPER_CLUSTER=zk-host1:2181,zk-host2:2181

## (Optional) Set custom HTTP port

    KASTLEX_HTTP_PORT=8092

## (Optional) Enable HTTPS
Variables are given with their default values except for KASTLEX_USE_HTTPS which is disabled by default.

So if you just set `KASTLEX_USE_HTTPS=true`, Kastlex will be accepting TLS connection on 8093 and use certificates in /etc/kastlex/ssl.

    KASTLEX_USE_HTTPS=true
    KASTLEX_HTTPS_PORT=8093
    KASTLEX_CERTFILE=/etc/kastlex/ssl/server.crt
    KASTLEX_KEYFILE=/etc/kastlex/ssl/server.key
    KASTLEX_CACERTFILE=/etc/kastlex/ssl/ca-cert.crt

## Building release for production

    MIX_ENV=prod mix compile
    MIX_ENV=prod mix release

## Running release

    rel/kastlex/bin/kastlex console

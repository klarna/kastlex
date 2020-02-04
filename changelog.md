
* 1.5.3 Improve Prometheus metrics report performance

* 1.5.4 Upgrade to brod 3.3.4.
  Prior to 3.3.4, brod consumer group coordinator commits consumed offsets to kafka, instead of next-to-fetch offset.
  Which is different from the convention in kafka spec and other library implementations.
  For the same reason, KastleX calculated lagging as `high-watermark-offset - committed-offset - 1`,
  1.5.4 changed it to `high-watermark-offset - committed-offset`.

* 1.5.5 Fix return result of Kastlex.Users.get_user

* 1.5.6 Change consumer cg cache from dets to ets (detached from master, proted to 1.7.1)

* 1.6.0
  - Upgrade to elixir 1.7
  - Upgrade to brod 3.7
  - Add scram-sasl auth towards kafka
  - Error codes changed (per change in kafka spec and convention) from CamelCase to snake_case, e.g:
      * UnknownTopicOrPartition -> unknown_topic_or_partition
      * LeaderNotAvailable -> leader_not_available
  - Message fileds `crc`, `attributes` and `magic_byte` are removed from JSON fetch response
  - Per kafka message `headers` field is added to JSON fetch response.
  - New http headers `x-message-headers`, `x-message-offset`, `x-message-ts` and `x-message-ts-type` are
    added to both v1 and v2 binary fetch response.
    The header value is the kafka message header formated in JSON.
  - Add `x-kafka-partition` and `x-message-offset` http headers to produce response
  - Stopped using 'latest as last' in fetch APIs, instead, introduced new logical offset 'last'.
    NOTE: in case the partition is empty, fetching 'last' will result in error.

1.7.0
  - Deleted zookeeper client, fetch topic metadata from KAFKA APIs
  - Added version 2 'consumers' API, fetch consumer states from KAFKA APIs

1.7.1
  - Change dets to ets for consumer state cache (port from 1.5.6).
1.7.2
  - Fix prod config, change allowed algos for guardian app from HS512 to ES512
    also upgrade to brod 3.7.10 to fix a bug which may skip through unstable messages
    in case messages are published in a transaction
1.7.3
  - Upgrade to brod 3.7.11 to fix a bug when receiving empty batch from compacted transactions
1.7.4
  - Remove expire_time from GUI since kafka 2.0 does not support it any more
1.x.y
  - Delete unused config `cg_cache_dir` since cg state is no longer cached in dets


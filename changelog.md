
* 1.5.3 Improve Prometheus metrics report performance

* 1.5.4 Upgrade to brod 3.3.4.
  Prior to 3.3.4, brod consumer group coordinator commits consumed offsets to kafka, instead of next-to-fetch offset.
  Which is different from the convention in kafka spec and other library implementations.
  For the same reason, KastleX calculated lagging as `high-watermark-offset - committed-offset - 1`,
  1.5.4 changed it to `high-watermark-offset - committed-offset`.
* 1.6.0
  - Upgrade to elixir 1.7
  - Upgrade to brod 3.7
  - Add scram-sasl auth towards kafka
  - Error codes changed (per change in kafka spec and convention) from CamelCase to snake_case, e.g:
      * UnknownTopicOrPartition -> unknown_topic_or_partition
      * LeaderNotAvailable -> leader_not_available
  - Message files `crc`, `attributes` and `magic_byte` are removed from JSON fetch response
  - Per kafka message `headers` field is added to JSON fetch response.
  - A new http header `x-message-headers` is added to both v1 and v2 binary fetch response.
    The header value is the kafka message header formated in JSON.
  - Stopped using 'latest as last' in fetch APIs, instead, introduced new logical offset 'last'.
    NOTE: in case the partition is empty, fetching 'last' will result in error.



* 1.5.3 Improve Prometheus metrics report performance

* 1.5.4 Upgrade to brod 3.3.4.
  Prior to 3.3.4, brod consumer group coordinator commits consumed offsets to kafka, instead of next-to-fetch offset.
  Which is different from the convention in kafka spec and other library implementations.
  For the same reason, KastleX calculated lagging as `high-watermark-offset - committed-offset - 1`,
  1.5.4 changed it to `high-watermark-offset - committed-offset`.
* 1.6.0
  - Upgrad to elixir 1.7
  - Upgrad to brod 3.7
  - Error codes changed (per change in kafka spec and convention), e.g:
      * UnknownTopicOrPartition -> unknown_topic_or_partition
      * LeaderNotAvailable -> leader_not_available
  - Message files `crc`, `attributes` and `magic_byte` are deleted from JSON fetch response
  - `headers` field is added to JSON fetch response
  - `x-message-headers` http header is added to v1 binary fetch response
  - Missing http headers are added for v2 fetch response
  - Deleted 'latest' as 'last' logic from fetch APIs
    introduced logical offset 'last' instead.
    NOTE: in case the partition is empty, fetching 'last' will result in error


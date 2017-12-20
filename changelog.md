
* 1.5.3 Improve Prometheus metrics report performance

* 1.5.4 Upgrade to brod 3.3.4.
  Prior to 3.3.4, brod consumer group coordinator commits consumed offsets to kafka, instead of next-to-fetch offset.
  Which is different from the convention in kafka spec and other library implementations.
  For the same reason, KastleX calculated lagging as `high-watermark-offset - committed-offset - 1`,
  1.5.4 changed it to `high-watermark-offset - committed-offset`.


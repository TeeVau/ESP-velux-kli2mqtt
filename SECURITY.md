# Security policy

Please do not disclose security issues in public issue trackers. Report them
privately to the repository owner with a minimal reproduction and affected
firmware version.

HTTP OTA has no separate password. It is available only for a short time after
an MQTT command from the configured broker. Treat the broker and local network
as the trust boundary: use credentials, restrict who may publish to the device
topics, and never expose the broker or ESP to the internet.

Never publish `secrets.h`, broker details, unredacted serial logs, private
network addresses or photos with location metadata.

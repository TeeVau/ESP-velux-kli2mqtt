# Security Policy

Please do not disclose security issues in public issue trackers. Report them
privately to the repository owner with a minimal reproduction and affected
firmware version.

This project intentionally exposes unauthenticated HTTP OTA only while a
trusted MQTT broker has opened a short-lived local-network window. Deploy it
only on a trusted network with protected MQTT credentials. Never publish
`secrets.h`, broker details, unredacted serial logs, private network addresses
or photos with location metadata.

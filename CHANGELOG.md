# Changelog

## 0.1.8 - 2026-07-24

### Fixes

- Fix a launch crash caused by concurrent anonymous telemetry and MetricKit queue uploads.
- Keep telemetry queue mutations safe when diagnostics are uploaded, consent is disabled, or new events arrive during an upload.

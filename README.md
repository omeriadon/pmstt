 <img width="400" height="400" alt="Timetable-watchOS-Default-1088@1x" src="https://github.com/user-attachments/assets/3d008ff8-89d2-4003-a8d5-b576fcd3cc60" />

# pmstt

💧 A project built with the Swift Vapor web framework.

Timetable for PMS is powered by this server.

See [omeriadon/timetable](https://github.com/omeriadon/timetable) for more details and to see what this server powers.

## Build and Run

To build the project using the Swift Package Manager, run the following command in the terminal from the root of the project:
```bash
swift build
```

To run the project and start the server, use the following command:
```bash
swift run
```
Tests:

```bash
swift test
```

## Production log timestamps

pmstt uses SwiftLog's standard stream handler. Each application log line begins
with a timestamp containing the local UTC offset, followed by its log level and
logger label:

```text
2026-07-29T21:50:13+0800 info codes.vapor.application:
```

PM2 must leave timestamp prefixing disabled and must not be started with a
separate timestamp option because that would add a second, conflicting prefix.

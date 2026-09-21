# Port Management

Port Management is an offline, read-only inventory of TCP listening and established connections.

![Port Management](/MyMacCleaner/screenshots/port_management/port_managment.png)

## What it shows

Each row can include the process name and PID, local address and port, remote endpoint when present, TCP state, and protocol. The inventory is collected locally with a fixed system query and is not sent anywhere.

The page groups connections as:

| Filter | Meaning |
|---|---|
| All | Every connection found in the current inventory |
| Listening | A local service waiting for a connection |
| Established | A current TCP connection |

## How to use it

1. Select **Port Management** and choose **Refresh** to collect a current inventory.
2. Search by process name, local port, or remote address.
3. Use the listening and established filters to narrow the list.
4. Record the process name and PID if you need to investigate a conflict in the owning tool, app, or service manager.

For example, search for `3000` to identify the local process currently associated with that port before deciding what to do outside MyMacCleaner.

## Phase-0 limitation

Port Management is observational. It has no controls for processes, network connections, services, or system configuration.

# denis-tcp-proxy

This script is listening on a tcp port and waits for connection.
If a connection occurs it will forward to a remote port.
If the remote side is not availabe a script is triggered to take action.

There are infinite posibbilities: 

* start a docker container in AWS or Google cloud
* restart a webserver on demand
* delete your harddisk ... 

# Usage

Usage: $0 <local port> <remote_host:remote_port> <refresh in seconds>



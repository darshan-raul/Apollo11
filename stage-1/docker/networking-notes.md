
Reference:
https://github.com/KamranAzeem/learn-docker/blob/master/docs/docker-networking-deep-dive.md

The following networks are available to you by default, when you install docker on your computer.

Bridge - NAT - docker0
Host - Uses host network
None - Isolated / no networking

Other Docker networks available to you are the following, but are not covered in this document.

Overlay - Swarm mode
Macvlan - Legacy applications needing direct connection to physical network
3rd party network plugins

-- Default bridge network:

- basically is a NAT interface.. gatwat
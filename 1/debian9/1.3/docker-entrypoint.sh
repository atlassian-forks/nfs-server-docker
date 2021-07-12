#!/usr/bin/env bash
# Copyright 2015 The Kubernetes Authors.
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

: "${MOUNTD_PORT:=20048}"
: "${NFS_PORT:=2049}"
: "${NFS_THREADS:=4}"
: "${STATD_PORT:=32765}"
: "${STATD_PORT_OUT:=32766}"
: "${LOCKD_PORT:=32767}"

function hex()
{
  local width="${2:-8}"
  printf "%0${width}x" "$1" | fold -w4 | paste -sd' ' -
}

function set_portmap_entry()
{
    local service
    local port
    local proto
    local service_version
    service="$(hex "$1")" # Service ID
    port="$(hex "$2")"
    if [ "$3"  = 'tcp' ]; then
        proto="$(hex 6)" # 0x6 == tcp
    else
        proto="$(hex 17)" # 0x12 == udp
    fi
    service_version="$(hex "$4")"

    # Google "rpcbind protocol" to find ONC+ RPC protocol specs
    local xid="7073 343b" # Can be anything - will be used for response
    local portmap_service
    local prog_version
    local rpc_version
    local proc
    local message_type
    message_type="$(hex 0)" # 0 == Call
    portmap_service="$(hex 100000)" # == Portmap service
    prog_version="$(hex 2)" # Program prog_version 2
    rpc_version="$(hex 2)" # RPC prog_version 2
    proc="$(hex 1)" # portmap proc 2 (SET)

    set="$(cat <<HEX
00000000: 8000 0038 $xid $message_type $rpc_version
00000010: $portmap_service $prog_version $proc 0000 0000
00000020: 0000 0000 0000 0000 0000 0000 $service
00000030: $service_version $proto $port
HEX
)"

    # Generate bytes from hex dump, pipe to rpcbind's UNIX socket and encode binary response into hex
    response="$(xxd -r <<<"$set" | socat - UNIX-CONNECT:/var/run/rpcbind.sock | xxd -p | tr -d '\n')"
    if [[ "$response" != "8000001c${xid// /}"*"00000001" ]]; then
      echo "Failed to set port mapping $1 $2/$3 $4" >&2
    fi
}

function delete_portmap_entry()
{
    local service="$1"
    local port="$2"
    local proto="$3"
    local service_version="$4"

    if ! rpcinfo -d -T "$proto" "$service" "$service_version"; then
      echo "Failed to delete port mapping $1 $2/$3 $4" >&2
    fi
}

function update_portmap_entries()
{
    local service="$1"
    local port="$2"
    local proto="$3"

    # Sample output:
    #   program vers proto   port  service
    #    100003    3   tcp   2049  nfs
    #    100003    4   tcp   2049  nfs
    #    100003    3   udp   2049  nfs

    rpcinfo -p | awk '{ if ($5 == "'"$service"'" && $3 == "'"$proto"'") { print } }' | while read -r line; do
        read -r -a fields <<<"$line"

        echo "portmap: ${fields[4]} (${fields[0]}) ${fields[3]}/${fields[2]} -> ${port}/${fields[2]} service_version:${fields[1]}"
        delete_portmap_entry "${fields[4]}" "${fields[3]}" "${fields[2]}" "${fields[1]}"
        set_portmap_entry "${fields[0]}" "$port" "${fields[2]}" "${fields[1]}"
    done
}

function start()
{

    if ! /usr/sbin/rpcinfo 127.0.0.1 > /dev/null 2>&1; then
       echo "Starting rpcbind..."
       /usr/sbin/rpcbind -s -d
    fi


    mount -v -t nfsd nfsd /proc/fs/nfsd

    echo "Starting rpc.mountd..."
    /usr/sbin/rpc.mountd --no-nfs-prog_version 2 --nfs-prog_version 3 --port "${MOUNTD_PORT}" --debug all

    echo "Exporting file systems..."
    /usr/sbin/exportfs -ar

    /usr/sbin/rpc.statd --no-notify --port "${STATD_PORT}" --outgoing-port "${STATD_PORT_OUT}" --no-syslog --foreground &
    /usr/sbin/rpc.nfsd --no-nfs-prog_version 2 --nfs-prog_version 3 --tcp --udp --port "${NFS_PORT}" --debug "${NFS_THREADS}"

    echo "Forwarding lockd ports..."
    port="$(rpcinfo -p 127.0.0.1 | awk '{ if ($5 == "nlockmgr" && $3 == "udp") { print $4 } }' | head -n1)"
    echo "$LOCKD_PORT/udp -> $port/udp"
    socat "UDP4-RECVFROM:$LOCKD_PORT,fork" "UDP4-SENDTO:127.0.0.1:$port" &
    update_portmap_entries "nlockmgr" "$LOCKD_PORT" "udp"

    port="$(rpcinfo -p 127.0.0.1 | awk '{ if ($5 == "nlockmgr" && $3 == "tcp") { print $4 } }' | head -n1)"
    echo "$LOCKD_PORT/tcp -> $port/tcp"
    socat "TCP-LISTEN:$LOCKD_PORT,fork,reuseaddr" "TCP:127.0.0.1:$port" &
    update_portmap_entries "nlockmgr" "$LOCKD_PORT" "tcp"

    echo "rpc ports:"
    /usr/sbin/rpcinfo -p

    ps ax
    echo "NFS server started."
}

function stop()
{
    echo "Stopping NFS"

    /usr/sbin/rpc.nfsd 0
    /usr/sbin/exportfs -au
    /usr/sbin/exportfs -f

    kill $( pidof rpc.mountd ) 2>/dev/null || true
    kill $( pidof rpc.statd ) 2>/dev/null || true
    kill $( pidof rpcbind ) 2>/dev/null || true
    kill $( pidof socat ) 2>/dev/null || true
}

trap stop EXIT TERM INT
start "$@"

tail -f /dev/null

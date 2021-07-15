#!/usr/bin/env bash

set -euo pipefail

: "${MOUNTD_PORT:=20048}"
: "${NFS_PORT:=2049}"
: "${NFS_THREADS:=4}"
: "${STATD_PORT:=32765}"
: "${STATD_PORT_OUT:=32766}"
: "${LOCKD_PORT:=32767}"
: "${EXPORT_PATH:=/srv/nfs}"

function start()
{
    if ! rpcinfo 127.0.0.1 > /dev/null 2>&1; then
       echo "Starting rpcbind..."
       rpcbind -s -d
    fi

    rpc.statd --no-notify --port "${STATD_PORT}" --outgoing-port "${STATD_PORT_OUT}" --no-syslog --foreground &

    local ganesha_config
    ganesha_config="$(cat <<EOF
###################################################
#
# EXPORT
#
# To function, all that is required is an EXPORT
#
# Define the absolute minimal export
#
###################################################
EXPORT
{
	# Export Id (mandatory, each EXPORT must have a unique Export_Id)
	Export_Id = 1;
	# Exported path (mandatory)
	Path = $EXPORT_PATH;
	# Pseudo Path (required for NFS v4)
	Pseudo = $EXPORT_PATH;
  # Whether to squash various users.
	Squash = no_root_squash;
	# Required for access (default is None)
	# Could use CLIENT blocks instead
	Access_Type = RW;
	# Exporting FSAL
	FSAL {
		Name = VFS;
	}
}
NFS_Core_Param
{
	MNT_Port = $MOUNTD_PORT;
	NLM_Port = $LOCKD_PORT;
	fsid_device = true;
}
NFSV4
{
	Grace_Period = 90;
}
# LOG {
#  COMPONENTS {
#    ALL = Full_Debug;
#  }
#}
EOF
)"

    cat > /ganesha.conf <<<"$ganesha_config"
    mkdir -p "$EXPORT_PATH"

    ganesha.nfsd -F -f /ganesha.conf -L /dev/stdout &
}

function stop()
{
    echo "Stopping NFS"

    kill $( pidof ganesha.nfsd ) 2>/dev/null || true
    kill $( pidof rpc.statd ) 2>/dev/null || true
    kill $( pidof rpcbind ) 2>/dev/null || true
}

trap stop EXIT TERM INT
start "$@"

tail -f /dev/null

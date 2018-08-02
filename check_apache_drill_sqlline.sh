#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-08-02 19:21:55 +0100 (Thu, 02 Aug 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

exec 2>&1

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

export PATH="$PATH:/opt/apache-drill/bin:/apache-drill/bin"
for x in /opt/mapr/drill/drill-*/bin; do
    export PATH="$PATH:$x"
done

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

trap "echo UNKNOWN; exit $UNKNOWN" EXIT

# nice try but doesn't work
#export TMOUT=10
#exec

host="${APACHE_DRILL_HOST:-${DRILL_HOST:-${HOST:-localhost}}}"
zookeepers="${ZOOKEEPERS:-}"
cli="sqlline"
krb5_host=""
krb5_princ=""
krb5_realm=""

usage(){
    if [ -n "$*" ]; then
        echo "$@"
        echo
    fi
    cat <<EOF

Nagios Plugin to check Apache Drill via local sqlline shell SQL query

Specify --host to check a specific Drill node (defaults to localhost), or --zookeeper to test that any node is up

ZooKeeper ensemble takes priority over --host

Tested on Apache Drill 1.13

usage: ${0##*/}

-H --host           Apache Drill Host (default: localhost, \$APACHE_DRILL_HOST, \$DRILL_HOST, \$HOST)
-z --zookeeper      ZooKeeper ensemble (comma separated list of hosts, \$ZOOKEEPERS)
   --krb5-host      Kerberos host component of remote Drillbit if using Kerberos via local TGT cache
   --krb5-princ     Kerberos principal of remote Drillbit if using Kerberos via local TGT cache
   --krb5-realm     Kerberos realm if using Kerberos via local TGT cache

EOF
    trap '' EXIT
    exit $UNKNOWN
}

until [ $# -lt 1 ]; do
    case $1 in
         -H|--host)     host="${2:-}"
                        shift
                        ;;
   -z|--zookeepers)     zookeepers="${2:-}"
                        shift
                        ;;
       --krb5-host)     krb5_host="${2:-}"
                        shift
                        ;;
      --krb5-princ)     krb5_princ="${2:-}"
                        shift
                        ;;
      --krb5-realm)     krb5_realm="${2:-}"
                        shift
                        ;;
         -h|--help)     usage
                        ;;
                *)      usage "unknown argument: $1"
                        ;;
    esac
    shift || :
done

if [ -z "$zookeepers" -a -z "$host" ]; then
    usage "--host / --zookeeper not specified"
fi
if [ -n "$krb5_host" -o -n "$krb5_princ" -o -n "$krb5_realm" ]; then
   if [ -z "$krb5_host" -o -z "$krb5_princ" -o -z "$krb5_realm" ]; then
        usage "Kerberos requires --krb5-host, --krb5-princ and --krb5-realm to all be specified if any are used"
    fi
fi

check_bin(){
    local bin="$1"
    if ! which $bin &>/dev/null; then
        echo "'$bin' command not found in \$PATH ($PATH)"
        exit $UNKNOWN
    fi
}
check_bin "$cli"

check_apache_drill(){
    local query="select * from sys.version;"
    local krb5=""
    if [ "$krb5_host" -a "$krb5_princ" -a "$krb5_realm" ]; then
        krb5=";principal=$krb5_princ/$krb5_host@$krb5_realm"
    fi
    if [ -n "$zookeepers" ]; then
        output="$("$cli" -u "jdbc:drill:zk=${zookeepers}${krb5}" -f /dev/stdin <<< "$query" 2>&1)"
        retcode=$?
    else
        output="$("$cli" -u "jdbc:drill:drillbit=${host}${krb5}" -f /dev/stdin <<< "$query" 2>&1)"
        retcode=$?
    fi
    trap '' EXIT
    if [ $retcode = 0 ]; then
        if grep -q "1 row selected" <<< "$output"; then
            echo "OK: Apache Drill sqlline query succeeded, SQL engine running"
            exit $OK
        fi
    fi
    err=""
    if [ -n "$krb5" ]; then
        err=" or Kerberos credentials or options invalid"
    fi
    echo "CRITICAL: Apache Drill sqlline query failed, SQL engine not running$err"
    exit $CRITICAL
}

check_apache_drill

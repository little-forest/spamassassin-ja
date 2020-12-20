#!/bin/sh

TARGET_PROCESS_NAME="spamass-milter"

if [ -z "${MILTER_SOCKET}" ]; then
  echo "MILTER_SOCKET is not specified." >&2
  exit 1
fi

_get_value() {
  local CONTENT="$1"
  local KEY="$2"
  echo "$CONTENT" | sed -re "s/(^|.+ )${KEY}:([^ ]+)( .+|$)/\2/;t;d"
}

_is_target() {
  local CONTENT="$1"
  local PROCESS_NAME=`_get_value "$CONTENT" processname`
  [ "${PROCESS_NAME}" == "${TARGET_PROCESS_NAME}" ] && return 0 || return 1
}

_on_start() {
  _is_target "$CONTENT" || return
  local RESULT=
  for I in 1 1 1 1 1; do
    sleep $I
    if [ -S "$MILTER_SOCKET" ]; then
      chown spamd.spamd ${MILTER_SOCKET} \
        && chmod 660 ${MILTER_SOCKET} \
        && RESULT=OK
      break
    fi
  done
  [ $RESULT != "OK" ] && echo "Failed to change owner : $MILTER_SOCKET" >&2
}

_on_stop() {
  _is_target "$CONTENT" || return
  [ -S "$MILTER_SOCKET" ] && rm ${MILTER_SOCKET}
}

while :; do
  echo -en "READY\n"

  read HEADER
  EVENT_NAME=`_get_value "$HEADER" eventname`
  LEN=`_get_value "$HEADER" len`
  read -n ${LEN} CONTENT

  case "${EVENT_NAME}" in
    PROCESS_STATE_RUNNING)
      _on_start "$CONTENT"
      ;;

    PROCESS_STATE_EXITED|PROCESS_STATE_STOPPED|PROCESS_STATE_FATAL)
      _on_stop "$CONTENT"
      ;;

    *) : ;;
  esac

  echo -en "RESULT 2\nOK"

done

# vim: ts=2 sw=2 sts=2 et nu foldmethod=marker

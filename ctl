#!/bin/sh

#- global variables ------------------------------------------------------------
_SCRIPT_BASE=`echo $(cd $(dirname $0); pwd)`
_SCRIPT_NAME=`basename $0`

_SPAMD_USER=spamd
_SPAMD_GROUP=spamd
_RULE_DIR=/var/lib/spamassassin
_BAYES_BASE_DIR=/var/spool/spamassassin
_CONF_DIR=/etc/mail/spamassassin
_SITE_CONF_DIR=${_CONF_DIR}/site
_SITE_CONF=${_CONF_DIR}/site.cf
_SHARE_DIR=/usr/share/spamassassin

_SOCKET_DIR=/var/run/spamd

_TIME_ZONE=Asia/Tokyo

_SPAMASS_HOSTNAME=skuld.littleforest.jp

_setup_color() { #{{{
  C_RED="\e[31m"
  C_GREEN="\e[32m"
  C_YELLOW="\e[33m"
  C_CYAN="\e[36m"
  C_WHITE="\e[37;1m"
  C_OFF="\e[m"
  M_OK="[${C_GREEN} OK ${C_OFF}]"

  M_FATAL="[${C_RED} FATAL ${C_OFF}]"
  M_FAILED="[${C_RED} FAILED ${C_OFF}]"
  M_WARN="[${C_YELLOW} WARNING ${C_OFF}]"
}
##}}}

_set_timezone() { #{{{
  local TIMEZONE="$1"
  local ZONE_FILE=/usr/share/zoneinfo/${TIMEZONE}

  if [ ! -f "${ZONE_FILE}" ]; then
    echo "Invalid time zone : ${ZONE_FILE}" >&2
    exit 1
  fi

  cp -L ${ZONE_FILE} /etc/localtime
  echo "${TIMEZONE}" >  /etc/timezone

  export TZ=${TIMEZONE}
}
#}}}

_fatal() { #{{{
  echo -e "${C_RED}[FATAL] $1${C_OFF}" >&2
  # prevent for restart by docker/systemd, exit status must be 0
  exit 0
}
#}}}

_usage() { #{{{
  cat <<!!!
usege: $_SCRIPT_NAME COMMAND
  COMMAND:
    boot : boot Spamassassin.

    shell : boot /bin/sh.
      usage)
        docker exec -it /ctl shell

    learn-spam :
      usage)
        docker cp /XXX/cur/ spamassassin:/spam/
        docker exec -it spamassassin /ctl learn-spam

    learn-ham :
      usage)
        docker cp /XXX/cur/ spamassassin:/ham/
        docker exec -it spamassassin /ctl learn-ham

    check-spam :
      usage)
        docker exec -i /ctl check-spam < MAIL_FILE
          or
        docker exec -i /ctl check-spam --header < MAIL_FILE

    help : display this usage.
!!!
  exit 0
}
#}}}

_boot() { #{{{
  _set_timezone ${_TIME_ZONE}

  # Check environment values
  [ -z "${HOST_SPAMD_UID}" ] && _fatal "HOST_SPAMD_UID is not defined."
  echo -e "${C_CYAN}HOST_SPAMD_UID : ${C_OFF}${HOST_SPAMD_UID}"
  [ -z "${HOST_SPAMD_GID}" ] && _fatal "HOST_SPAMD_GID is not defined."
  echo -e "${C_CYAN}HOST_SPAMD_GID : ${C_OFF}${HOST_SPAMD_GID}"

  # Adjust uid/gid
  groupmod -g ${HOST_SPAMD_GID} ${_SPAMD_GROUP}
  usermod -g ${HOST_SPAMD_GID} -u ${HOST_SPAMD_UID} ${_SPAMD_USER}

  # execute sa-update
  echo -e "${C_CYAN}Executing sa-update...${C_OFF}"
  /usr/local/bin/sa-update -v
  echo -e "${M_OK}"

  # copy default local.cf
  mkdir -p ${_SITE_CONF_DIR} && chown ${_SPAMD_USER}:${_SPAMD_GROUP} ${_SITE_CONF_DIR}
  if [[ ! -f ${_SITE_CONF}/local.cf ]]; then
    cp ${_SHARE_DIR}/local.cf.default ${_SITE_CONF_DIR}/local.cf
    chown ${_SPAMD_USER}:${_SPAMD_GROUP} ${_SITE_CONF_DIR}/local.cf
  fi

  # prepare bayes dir
  mkdir -p ${_BAYES_BASE_DIR}
  chown ${_SPAMD_USER}:${_SPAMD_GROUP} ${_BAYES_BASE_DIR} 

  # change report_hostname
  if [ -n "${_SPAMASS_HOSTNAME}" ]; then
    echo "report_hostname ${_SPAMASS_HOSTNAME}" > ${_SITE_CONF_DIR}/hostmame.cf
  fi

  # prepare configurations
  cat /dev/null > ${_SITE_CONF}
  chown ${_SPAMD_USER}:${_SPAMD_GROUP} ${_SITE_CONF}

  find ${_SITE_CONF_DIR} -type f -name '*.cf' | while read FILE; do
    echo "include ${FILE}" >> ${_SITE_CONF}
  done

  # prepare socket dir
  if [ ! -d ${_SOCKET_DIR} ]; then
    mkdir ${_SOCKET_DIR}
  fi
  echo -e "${C_CYAN}Socket directory${C_OFF} : ${_SOCKET_DIR}"

  # environment variables for Supervisord
  export SPAMD_SOCKET=${_SOCKET_DIR}/spamd.sock
  export MILTER_SOCKET=${_SOCKET_DIR}/spamass-milter.sock
  export SPAMD_USER=${_SPAMD_USER}
  export SPAMD_GROUP=${_SPAMD_GROUP}

  # check configuration
  echo -e "${C_CYAN}Checking spamassassin configurations...${C_OFF}"
  if spamassassin --lint; then
    echo -e "${M_OK}"
  else
    echo -e "${M_FAILED}" >&2
    exit 1
  fi

  # boot
  exec /usr/bin/supervisord -c /etc/supervisord.conf
}
#}}}

_check_spam() { #{{{
  if [ "$1" == '--header' ]; then
    /usr/local/bin/spamassassin --nocreate-prefs --exit-code | sed -nre '1,/^$/p'
    exit $?
  else
    /usr/local/bin/spamassassin --nocreate-prefs --exit-code
    exit $?
  fi
}
#}}}

_learn_spam() { #{{{
  local BASE='/spam'
  find ${BASE} -type d | tac | while read DIR; do
    echo -e "${C_CYAN}Learning SPAMs from ${DIR}${C_OFF}" 
    if sa-learn --spam --progress ${DIR}; then
      echo -e "${M_OK}"
      if [ "${DIR}" != "${BASE}" ]; then
        rm -rf "${DIR}"
      else
        rm -f "${DIR}/*"
      fi
    else
      echo -e "${M_FAILED}"
    fi
  done
  exit 0
}
#}}}

_learn_ham() { #{{{
  local BASE='/ham'
  find ${BASE} -type d | tac | while read DIR; do
    echo -e "${C_CYAN}Learning HAMs from ${DIR}${C_OFF}" 
    if sa-learn --ham --progress ${DIR}; then
      echo -e "${M_OK}"
      if [ "${DIR}" != "${BASE}" ]; then
        rm -rf "${DIR}"
      else
        rm -f "${DIR}/*"
      fi
    else
      echo -e "${M_FAILED}"
    fi
  done
  exit 0
}
#}}}

# setup
# _setup_color

case "$1" in
  boot)
    _boot
    ;;
  shell)
    exec /bin/sh
    ;;
  check-spam)
    shift 1
    _check_spam "$@"
    ;;
  learn-spam)
    shift 1
    _learn_spam "$@"
    ;;
  learn-ham)
    shift 1
    _learn_ham "$@"
    ;;
  help|-h|*)
    _usage
    ;;
esac

# vim: ts=2 sw=2 sts=2 et nu foldmethod=marker

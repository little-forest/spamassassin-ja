# SpamAssassin with Japanese tokenizer patch

## Overview

A [SpamAssassin](https://spamassassin.apache.org/) docker image which has following futures. 

* SpamAssassin patched by [Japanese tokenizer](https://github.com/heartbeatsjp/spamassassin_ja)
* [spamass-milter](http://savannah.nongnu.org/projects/spamass-milt/)
* [MeCab](https://taku910.github.io/mecab/) (Part-of-Speech and Morphological Analyzer)
* Auto configured sa-update
* Provides systemd unit file


## Setup

This image can be run as a standalone application, but it is more convenient to run it under systemd.

In this instruction, we will run spamassassin under systemd control, and link it with postfix.

### Setup as a systemd service


**1. Create the `spamd` group and user.**

```
# groupadd spamd
# useradd -g spamd -s /sbin/nologin -M spamd
```

**2. Create a directory for the spamass-milter's socket.**

```
# mkdir /var/run/spamd
```

**3. Install systemd related files.**

```
# cp systemd/spamassassin-ja.service /etc/systemd/system/
# cp systemd/spamassassin /etc/sysconfig/
```

**4. Start the `spamassassin-ja` service.**

```
# systemctl daemon-reload
# systemctl start spamassassin-ja.service
# systemctl enable spamassassin-ja.service
```

### Postfix setup

The spamassassin-ja provides the spamass-milter.

Spamass-milter opens a unix domain scoket as `/var/run/spamd/spamass-milter.sock`.

Postfix will access spamass-milter through this socket.

To allow postfix to use this socket, let postfix user belong to the `spamd` group.

```
# usermod -aG spamd postfix
```

Add following configuration to `/etc/postfix/main.cf`

```
#
# Milter settings
#
milter_default_action = accept
milter_mail_macros = {auth_authen} {auth_author} {auth_type}
smtpd_milters = unix:/var/run/spamd/spamass-milter.sock

non_smtpd_milters = $smtpd_milters

milter_protocol = 2
```

Restart postfix.

```
# systemctl restart postfix 
```

## How to run as a standalone

Assume that the `spamd` user's uid and gid are 910

```
# id spamd
uid=910(spamd) gid=910(spamd) groups=910(spamd)
```

```
docker run --rm \
  -e HOST_SPAMD_UID=910 \
  -e HOST_SPAMD_GID=910 \
  -v /var/run/spamd:/var/run/spamd \
  -v spamassassin:/mnt/spamassassin:Z \
  --name spamassassin littlef/spamassassin-ja
```

Both `HOST_SPAMD_UID` and `HOST_SPAMD_UID` are used as a spamass-milter socket's owner.

## Supplemental information on operations

### Log

* When run as a systemd service, all logs are stored in `/var/log/maillog` throw syslog udp socket.
  * Logs will not be output to journald
  * rsyslog must be configured to receive logs via udp/514.

* When run as a standalone container, all logs will be output to `stdout`.

### Directory structure

All files that should be persisent are stored in Docker volume named `spamassassin`.

Typically, this volume will be located in `/var/lib/docker/volumes/spamassassin`.


## Control script

This image has a control scrpt which placed as `/ctl`.

Additional operations can be performed by using control scripts.

### SPAM check

You can manually check if a mail is spam or not.

```
docker exec -i spamassassin /ctl check-spamm < MAIL_FILE
```

When `--header` option is given, only header will be outputted. 

```
docker exec -i spamassassin /ctl check-spamm --header < spamtest01.txt
```

### Learn SPAM or HAM

If you want to learn mails as SPAM, copy them to the `/spam` directory 
in the container and then run the learn-spam subcommand.

In the following example, the emails in the `spam-learn` directory of the alice user will be learned as SPAM.

```
docker cp /home/alice/Maildir/.spam-learn/cur spamassassin:/spam/
docker exec -it spamassassin /ctl learn-spam
```

After learning, `/spam` directory contents will be deleted.

In the same way, you can also learn the mails as a HAM by copying it to the `/ham` directory in the container.

```
docker cp /home/alice/Maildir/.ham-learn/cur spamassassin:/ham/
docker exec -it spamassassin /ctl learn-ham
```

### Update rule automatically

Spamassassin rule is automatically updated every Sunday at 1:00 am.

### Execute shell

```
docker exec -it /ctl shell
```


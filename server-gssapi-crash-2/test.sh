#!/bin/bash

set -e

export PATH=/opt/mongodb/bin:$PATH

  cp krb5.conf /etc/
  mkdir -p /etc/krb5kdc
  cp kdc.conf /etc/krb5kdc/kdc.conf
  cp kadm5.acl /etc/krb5kdc/

  (echo masterp; echo masterp) |kdb5_util create -s
  (echo testp; echo testp) |kadmin.local addprinc test/test@LOCALKRB
  
  krb5kdc
  kadmind
  
  echo 127.0.0.1 krb.local |tee -a /etc/hosts
  echo testp |kinit test/test@LOCALKRB

mongod --auth --setParameter authenticationMechanisms=GSSAPI

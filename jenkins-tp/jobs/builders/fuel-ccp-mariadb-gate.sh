#!/bin/bash -xe

virtualenv mariadbenv

source mariadbenv/bin/activate

pip install fuel-ccp/

ccp --images-maintainer mirantis@mirantis.com \
    --images-namespace mariadbbuild --images-tag latest \
    --repositories-names {repos} \
    --repositories-path containers/nextgen \
    build -c mariadb

deactivate

pushd containers/nextgen/ms-mariadb
tox -e py27
popd

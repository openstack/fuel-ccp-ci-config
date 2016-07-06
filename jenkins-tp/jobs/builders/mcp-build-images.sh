#!/bin/bash -ex

ls -al

virtualenv mcp
source mcp/bin/activate
pip install .

mcp-microservices \
--images-maintainer mos-microservices@mirantis.com \
--builder-push \
--auth-registry \
--builder-registry registry01-bud.ng.mirantis.net \
--auth-registry-username $REG_USER \
--auth-registry-password $REG_PASS \
--images-namespace nextgen \
--images-tag latest \
--repositories-path microservices-repos \
build

deactivate

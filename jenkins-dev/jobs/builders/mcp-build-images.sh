#!/bin/bash -ex

ls -al

virtualenv mcp
source mcp/bin/activate
pip install .

ccp \
--images-base-distro debian \
--images-base-tag 8.4 \
--images-maintainer mos-microservices@mirantis.com \
--auth-gerrit-username nextgen-ci \
--builder-push \
--auth-registry \
--builder-registry registry01-bud.ng.mirantis.net \
--auth-registry-username nextgen \
--auth-registry-password ti5Eeng3 \
--images-namespace nextgen \
--images-tag latest \
--repositories-path microservices-repos \
build

deactivate

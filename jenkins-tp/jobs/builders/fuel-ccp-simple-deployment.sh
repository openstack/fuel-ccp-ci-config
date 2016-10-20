#!/bin/bash -ex

# Deploys CCP and runs simple, built-in OpenStack tests.
# Kubernetes cluster is expected to be pre-deployed and snapshoted - if not
# this script will ensure this.
# The script expects fuel-ccp cloned into fuel-ccp/ and fuel-ccp-installer
# cloned into fuel-ccp-installer/ directory (e.g. by Jenkins SCM plugin).


# CONFIGURATION:
######################################################
FUEL_DEVOPS_ENV_NAME="ccp-simple-deployment-env"
FUEL_DEVOPS_SNAPSHOT_NAME="fresh"
FUEL_DEVOPS_INSTALLATION_DIR="/home/jenkins/venv-fuel-devops-3.0"
HYPERKUBE_REPO="quay.io/coreos/hyperkube"
HYPERKUBE_TAG="v1.4.0_coreos.1"
HYPERKUBE_VERSION="v1.4.0"


# Prepare K8s env:
source "${FUEL_DEVOPS_INSTALLATION_DIR}"/bin/activate
NEED_TO_SETUP_ENV=false
dos.py revert "${FUEL_DEVOPS_ENV_NAME}" "${FUEL_DEVOPS_SNAPSHOT_NAME}" || NEED_TO_SETUP_ENV=true
dos.py resume "${FUEL_DEVOPS_ENV_NAME}" || NEED_TO_SETUP_ENV=true
if [ "${NEED_TO_SETUP_ENV}" = "true" ]; then
    echo "Couldn't revert fuel-devops snapshot, recreating environment."

    # Try to delete old envs to ensure clean host:
    dos.py destroy "${FUEL_DEVOPS_ENV_NAME}" || true
    dos.py erase "${FUEL_DEVOPS_ENV_NAME}" || true

    # Create kargo deployment script:
    cat > k8s_deploy.sh << EOF
#!/bin/bash -ex

export ENV_NAME=${FUEL_DEVOPS_ENV_NAME}
export IMAGE_PATH="/home/jenkins/workspace/cloud-images/default-image.qcow2"
export DONT_DESTROY_ON_SUCCESS=1
export DEPLOY_METHOD="kargo"
export SLAVES_COUNT="3"
export WORKSPACE="/home/jenkins/workspace"
export FUEL_DEVOPS_INSTALLATION_DIR=${FUEL_DEVOPS_INSTALLATION_DIR}
export CUSTOM_YAML='hyperkube_image_repo: "${HYPERKUBE_REPO}"
hyperkube_image_tag: "${HYPERKUBE_TAG}"
kube_version: "${HYPERKUBE_VERSION}"'

echo "Running on \${NODE_NAME}: \${ENV_NAME}"
source \${FUEL_DEVOPS_INSTALLATION_DIR}/bin/activate
echo "Use image:"
ls -la \${IMAGE_PATH}
env

pushd fuel-ccp-installer
bash -ex "./utils/jenkins/run_k8s_deploy_test.sh"
popd
EOF
    chmod +x k8s_deploy.sh

    # Now deploy the cluster:
    ./k8s_deploy.sh

    # Create fresh snapshot:
    dos.py suspend "${FUEL_DEVOPS_ENV_NAME}"
    dos.py snapshot "${FUEL_DEVOPS_ENV_NAME}" "${FUEL_DEVOPS_SNAPSHOT_NAME}"

    # Resume from snapshot to deploy CCP later on in the script:
    dos.py resume "${FUEL_DEVOPS_ENV_NAME}"
fi


# Get IP address of first node in the cluster:
ADMIN_IP=$(ENV_NAME=${FUEL_DEVOPS_ENV_NAME} python fuel-ccp-installer/utils/jenkins/env.py get_slaves_ips | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)
SSH_COMMAND="sshpass -p vagrant ssh -o StrictHostKeyChecking=no vagrant@${ADMIN_IP}"
SCP_COMMAND="sshpass -p vagrant scp -o StrictHostKeyChecking=no"

ssh-keygen -R "${ADMIN_IP}"

# FIXME(mzawadzki): adjust time brutally before proper solution with ntp is
# merged to packer scripts in fuel-ccp-installer:
${SSH_COMMAND} "sudo /sbin/hwclock --hctosys"

if [ ${VERSION} == "newton" ]; then
    GIT_BRANCH="stable/newton"
else
    GIT_BRANCH="master"
fi


# Prepare env on "admin" VM:
if [ ${COMPONENT} == "full" ];then
    pushd fuel-ccp
    git fetch "${ZUUL_URL}"/"${ZUUL_PROJECT}" "${ZUUL_REF}"
    git checkout FETCH_HEAD
    popd
    ${SCP_COMMAND} -r fuel-ccp/ vagrant@"${ADMIN_IP}":~/
else
    ${SSH_COMMAND} "git clone https://git.openstack.org/openstack/fuel-ccp"
    cat > ccp-fetch.yaml << EOF
debug: True
repositories:
  path: /tmp/ccp-repos
  skip_empty: True
sources:
  openstack/keystone:
    git_url: https://github.com/openstack/keystone.git
    git_ref: ${GIT_BRANCH}
  openstack/horizon:
    git_url: https://github.com/openstack/horizon.git
    git_ref: ${GIT_BRANCH}
  openstack/nova:
    git_url: https://github.com/openstack/nova.git
    git_ref: ${GIT_BRANCH}
  openstack/neutron:
    git_url: https://github.com/openstack/neutron.git
    git_ref: ${GIT_BRANCH}
  openstack/heat:
    git_url: https://github.com/openstack/heat.git
    git_ref: ${GIT_BRANCH}
  openstack/keystone:
    git_url: https://github.com/openstack/keystone.git
    git_ref: ${GIT_BRANCH}
  openstack/glance:
    git_url: https://github.com/openstack/glance.git
    git_ref: ${GIT_BRANCH}
  openstack/horizon:
    git_url: https://github.com/openstack/horizon.git
    git_ref: ${GIT_BRANCH}
EOF
    REPO=`echo ${ZUUL_PROJECT} | cut -d '/' -f 2`
    ${SCP_COMMAND} ccp-fetch.yaml vagrant@"${ADMIN_IP}":~/
    ${SSH_COMMAND} "pushd fuel-ccp && tox -e venv -- ccp --config-file ~/ccp-fetch.yaml fetch"
    ${SSH_COMMAND} "cd /tmp/ccp-repos/${REPO} && git fetch ${ZUUL_URL}/${ZUUL_PROJECT} ${ZUUL_REF} && git checkout FETCH_HEAD"
fi
# Run CCP deployment and OpenStack tests:
${SSH_COMMAND} "pushd fuel-ccp && tox -e multi-deploy -- --number-of-envs 1"

# Clean-up (snapshot should remain for next jobs):
dos.py destroy "${FUEL_DEVOPS_ENV_NAME}"

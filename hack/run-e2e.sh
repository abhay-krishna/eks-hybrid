#!/usr/bin/env bash
# Copyright Amazon.com Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

source $REPO_ROOT/hack/common.sh

CLUSTER_NAME="${1?Please specifiy the Cluster Name}"
REGION="${2?Please specify the AWS region}"
KUBERNETES_VERSION="${3?Please specify the Kubernetes version}"
CNI="${4?Please specify the cni}"
NODEADM_AMD_URL="${5?Please specify the nodeadm amd url}"
NODEADM_ARM_URL="${6?Please specify the nodeadm arm url}"
LOGS_BUCKET="${7-}"

CONFIG_DIR="$REPO_ROOT/e2e-config"
BIN_DIR="$REPO_ROOT/_bin"

mkdir -p $CONFIG_DIR

cat <<EOF > $CONFIG_DIR/e2e-setup-spec.yaml
spec:
  clusterName: $CLUSTER_NAME
  clusterRegion: $REGION
  kubernetesVersion: $KUBERNETES_VERSION
  cni: $CNI
  clusterNetwork:
    vpcCidr: 10.0.0.0/16
    publicSubnetCidr: 10.0.10.0/24
    privateSubnetCidr: 10.0.20.0/24
  hybridNetwork:
    vpcCidr: 10.1.0.0/16
    publicSubnetCidr: 10.1.1.0/24
    privateSubnetCidr: 10.1.2.0/24
    podCidr: 10.2.0.0/16
EOF

function cleanup(){
  if [ -f $RESOURCES_YAML ]; then
    $BIN_DIR/e2e-test cleanup -f $RESOURCES_YAML || true
  fi
  $REPO_ROOT/hack/e2e-cleanup.sh $CLUSTER_NAME
}

trap "cleanup" EXIT

RESOURCES_YAML=$CONFIG_DIR/$CLUSTER_NAME-resources.yaml
$BIN_DIR/e2e-test setup -s $CONFIG_DIR/e2e-setup-spec.yaml

mv /tmp/setup-resources-output.yaml $RESOURCES_YAML

VPC_ID="$(yq -r '.status.hybridVpcID' $RESOURCES_YAML)"

cat <<EOF > $CONFIG_DIR/e2e-param.yaml
clusterName: "$CLUSTER_NAME"
clusterRegion: "$REGION"
hybridVpcID: "$VPC_ID"
nodeadmUrlAMD: "$NODEADM_AMD_URL"
nodeadmUrlARM: "$NODEADM_ARM_URL"
logsBucket: "$LOGS_BUCKET"
EOF


SKIP_FILE=$REPO_ROOT/hack/SKIPPED_TESTS.yaml
# Extract skipped_tests field from SKIP_FILE file and join entries with ' || '
skip=$(yq '.skipped_tests | join("|")' ${SKIP_FILE})

# We expliclty specify procs instead of letting ginkgo decide (with -p) because in if not
# ginkgo will use all available CPUs, which could be a small number depending
# on how the CI runner has been configured. However, even if only one CPU is avaialble,
# there is still value in running the tests in multiple processes, since most of the work is
# "waiting" for infra to be created and nodes to join the cluster.
$BIN_DIR/ginkgo --procs 64 -v -tags=e2e --skip="${skip}" $BIN_DIR/e2e.test -- -filepath=$CONFIG_DIR/e2e-param.yaml

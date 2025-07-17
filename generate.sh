#! /bin/bash
#
# Copyright (c) 2025, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

log() {
	echo "$@" 1>&2
}

CATALOG=$(ocne catalog search --name embedded | sed 1d | tr '\t' ' ' | tr -s ' ' | awk '{$1=$1};1' | tr ' ' ':')
COMPONENTS=$(echo "$CATALOG" | cut -d':' -f1 | sort | uniq)

KUBE_VERSION="1.32 1.31 1.30"
echo "os:"
echo "  ock:"
for kubeVer in $KUBE_VERSION; do
	PACKAGES=$(podman run --pull newer --rm --entrypoint /usr/bin/rpm container-registry.oracle.com/olcne/ock-ostree:$kubeVer -qa --queryformat "%{NAME}|%{VERSION}-%{RELEASE}|%{SHA1HEADER}\n" | sort)
	echo "  - version: $kubeVer"
	echo "    images:"
	echo "    - image: container-registry.oracle.com/olcne/ock:$kubeVer"
	echo "      sha: $(skopeo inspect docker://container-registry.oracle.com/olcne/ock:$kubeVer | jq '.Digest')"
	echo "    - image: container-registry.oracle.com/olcne/ock-ostree:$kubeVer"
	echo "      sha: $(skopeo inspect docker://container-registry.oracle.com/olcne/ock-ostree:$kubeVer | jq '.Digest')"
	echo "    rpms:"

	for package in $PACKAGES; do
		NAME=$(echo "$package" | cut '-d|' -f1)
		VERSION=$(echo "$package" | cut '-d|' -f2)
		HASH=$(echo "$package" | cut '-d|' -f3)
		echo "    - name: $NAME"
		echo "      version: $VERSION"
		echo "      hash: $HASH"
	done
done

APISERVER_TAGS=$(skopeo list-tags docker://container-registry.oracle.com/olcne/kube-apiserver)
echo "base:"
echo "  kubernetes:"
for kubeVer in $KUBE_VERSION; do
	TAGS=$(echo "$APISERVER_TAGS" | grep --only-matching "v${kubeVer}\.[0-9]*" | sort -V -r | uniq)
	for tag in $TAGS; do
		echo "  - version: $(echo $tag | tr -d v)"
		echo "    images:"
		echo "    - image: container-registry.oracle.com/olcne/kube-apiserver:$tag"
		echo "      sha: $(skopeo inspect docker://container-registry.oracle.com/olcne/kube-apiserver:$tag | jq '.Digest')"
		echo "    - image: container-registry.oracle.com/olcne/kube-controller-manager:$tag"
		echo "      sha: $(skopeo inspect docker://container-registry.oracle.com/olcne/kube-controller-manager:$tag | jq '.Digest')"
		echo "    - image: container-registry.oracle.com/olcne/kube-proxy:$tag"
		echo "      sha: $(skopeo inspect docker://container-registry.oracle.com/olcne/kube-proxy:$tag | jq '.Digest')"
		echo "    - image: container-registry.oracle.com/olcne/kube-scheduler:$tag"
		echo "      sha: $(skopeo inspect docker://container-registry.oracle.com/olcne/kube-scheduler:$tag | jq '.Digest')"
	done
done

# Expand the Kubernetes versions for a more complete catalog
KUBE_VERSION="$KUBE_VERSION 1.29 1.28 1.27 1.26"

echo "catalog:"
for component in $COMPONENTS; do
	echo "  ${component}:"
	VERSIONS=$(echo "$CATALOG" | grep "^${component}:" | cut -d: -f2 | sort -V -r | uniq)
	for version in $VERSIONS; do
		echo "  - version: ${version}"

		echo "    kubernetes:"
		IMAGES=
		for kubeVer in $KUBE_VERSION; do
			log "Looking at $component at $version for Kubernetes $kubeVer"
			THESE_IMAGES=$(ocne catalog mirror --config <(cat << EOF
kubernetesVersion: $kubeVer
applications:
- name: $component
  version: $version
  catalog: embedded
EOF
))
			if [ "$?" = "0" ]; then
				echo "      - $kubeVer"
			fi
			log "  found $THESE_IMAGES"
			IMAGES=$(echo "${IMAGES}${THESE_IMAGES} ")
		done
		echo "    images:"
		IMAGES=$(echo "$IMAGES" | tr ' ' '\n' | sort | uniq)
		for image in $IMAGES; do
			IMG=$(skopeo inspect docker://$image)

			echo "    - image: \"$image\""
			echo "      sha: $(echo "$IMG" | jq '.Digest')"
		done
	done
done

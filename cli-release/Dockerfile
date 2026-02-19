FROM container-registry.oracle.com/os/oraclelinux:9
ARG BASE_VERSION
ARG HEAD_VERSION
RUN dnf install oracle-ocne-release-el9 cpio
RUN dnf config-manager --enable ol9_ocne
RUN mkdir -p /${BASE_VERSION} && mkdir -p /${HEAD_VERSION}
RUN yumdownloader --destdir /${BASE_VERSION} ocne-${BASE_VERSION}.el9
RUN yumdownloader --destdir /${HEAD_VERSION} ocne-${HEAD_VERSION}.el9
RUN cd /${BASE_VERSION} && rpm2cpio *.rpm | cpio -idv
RUN cd /${HEAD_VERSION} && rpm2cpio *.rpm | cpio -idv

# Copyright 2016 The Kubernetes Authors.
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM centos:latest
RUN cd /etc/yum.repos.d/
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
RUN sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

RUN yum install centos-stream-repos --allowerasing -y && \
    yum upgrade -y && \
    yum -y install \
    centos-release-nfs-ganesha4 \
    && yum -y install \
    nfs-ganesha \
    nfs-ganesha-vfs \
    /usr/bin/ps \
    nfs-utils \
    && yum clean all

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +rx /usr/local/bin/docker-entrypoint.sh

EXPOSE 2049/tcp
EXPOSE 2049/udp
EXPOSE 20048/tcp
EXPOSE 20048/udp
EXPOSE 111/tcp
EXPOSE 111/udp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["start"]

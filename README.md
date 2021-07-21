# Disclaimer
⚠️ For **testing** and **experimental** purposes only.
This image should not be used for production purposes. ⚠️

# Upstream
This source repo was originally based on:
https://github.com/GoogleCloudPlatform/nfs-server-docker

# How to build

    make build

To tag the image differently, you can specify either the `image` or `tag` variable:

    make build image=myown/nfs tag=3.0

# How to publish

    make

image ?= atlassian/nfs-server-test
tag ?= 2.0

full_image := "$(image):$(tag)"

# Find files that are not ignored by git
SRC_FILES := $(shell find . -path './.git' -prune -o -type f -not -exec git check-ignore -q --no-index {} \; -print)

all: build push

# Capture vars and rebuild if any of them changed
FORCE:
.vars: FORCE
	@if [[ `cat $@ 2>&1` != $(full_image) ]]; then \
		printf '%s' "$(full_image)" > $@ ; \
	fi

.build: $(SRC_FILES) .vars
	docker build -t $(full_image) .
	@touch .build

.push: .build
	docker push $(full_image)
	@touch .push

.PHONY: clean
clean:
	rm -f .build .push .vars

.PHONY: build
build: .build

.PHONY: push
push: build .push
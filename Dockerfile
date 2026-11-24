# HarnessRouter Community Edition on Railway.
#
# Upstream's official all-in-one image, pinned by release tag AND multi-arch index digest, plus one
# small start wrapper. No upstream file is changed: the wrapper runs /app/entrypoint.sh as the image
# would. To update: change the tag and digest together (Docker Hub harnessrouter/harnessrouter) and
# add a CHANGELOG.md entry.
FROM harnessrouter/harnessrouter:0.41.26@sha256:d7710cf7e6b7621fae51d18b973111075a0faab726419f021bb2e314117cdee6

# Railway's own init is PID 1, so tini runs as a child; as a subreaper it still reaps the
# orphaned processes agent CLIs leave behind.
ENV TINI_SUBREAPER=1

COPY railway-start.sh /usr/local/bin/hr-railway-start
RUN chmod 0755 /usr/local/bin/hr-railway-start \
    && bash -n /usr/local/bin/hr-railway-start \
    && test -x /app/entrypoint.sh && test -x /usr/bin/tini

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hr-railway-start"]

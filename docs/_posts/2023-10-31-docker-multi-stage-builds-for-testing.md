---
layout: default
title: "2023/10/31: Docker multi-stage builds for testing"
---

# Docker multi-stage builds for testing

**2023/10/31**

## Why?

Docker's [multi-stage builds](https://docs.docker.com/build/guide/multi-stage/) are a powerful tool for producing smaller images, faster. We can also use multi-stage Docker builds to test our images.

Sometimes, we aren't building an application, but an image to be the basis of downstream applications - for example, a development environment. In this case, we can't simply copy a single application executable and test it, our system under test is the image itself.


```Dockerfile
# The image we build
FROM debian AS foundation
# Our downstream users will read /config_files
COPY . /config_files
```

```Dockerfile
# Downstream app using our image
FROM foundation AS app
COPY . /app
RUN /app/downstream_app /config_files
```

## How?

How do we test that our `foundation` image maintains its contract to downstream users? 

We could write a test that inspects our image and validates our contracts. That could be awkward, since our existing testing framework, if we have one, is probably geared toward testing application or library code, not Docker images.

We can multi-stage builds to run our tests during the *build* phase, failing the build if our tests fail.

```Dockerfile
# The image we want to release after testing
FROM debian AS foundation_candidate
COPY . /config_files

# Our test
FROM foundation_candidate AS test
COPY test.sh /test.sh
# Write /tmp/results.txt only if test passes
RUN /bin/sh test.sh && echo "pass" > /tmp/result.txt

# The stage we will actually release
FROM foundation_candidate AS foundation
# This will cause the `test` stage to build. If that stage fails to write /tmp/result.txt,
# this `COPY` will fail, and our Docker build will fail.
COPY --from=test /tmp/result.txt /dev/null
```

We can build this image by targeting the final build stage.

A failing build:

```bash
% echo "exit 1" > test.sh
% docker build -t foundation --target foundation .
 => ERROR [test 2/2] RUN /bin/sh test.sh && echo "pass"                                                                                                                                                         0.1s
------
 > [test 2/2] RUN /bin/sh test.sh && echo "pass":
------
Dockerfile:9
--------------------
   7 |     COPY test.sh /test.sh
   8 |     # Write /tmp/results.txt only if test passes
   9 | >>> RUN /bin/sh test.sh && echo "pass"
  10 |
  11 |     # The stage we will actually release
--------------------
ERROR: failed to solve: process "/bin/sh -c /bin/sh test.sh && echo \"pass\"" did not complete successfully: exit code: 1
```

A passing build!

```bash
% echo "exit 0" > test.sh
% docker build -t foundation --target foundation .
```

The final image doesn't contain the tests, but it does contain a `5 byte` layer from copying the test results to `/dev/null`.

```bash
% docker history foundation
IMAGE          CREATED              CREATED BY                                      SIZE      COMMENT
2ca32e95dd61   About a minute ago   COPY /tmp/result.txt /dev/null # buildkit       5B        buildkit.dockerfile.v0
<missing>      About a minute ago   COPY . /config_files # buildkit                 512B      buildkit.dockerfile.v0
<missing>      2 weeks ago          /bin/sh -c #(nop)  CMD ["bash"]                 0B
<missing>      2 weeks ago          /bin/sh -c #(nop) ADD file:bf4264671bd91eb30…   139MB
```

## Can we improve it?

Slightly! Let's print out an error message when tests fail.

```Dockerfile
# Write /tmp/results.txt only if test passes
RUN (/bin/sh test.sh && echo "pass" > /tmp/result.txt) || (echo "Tests Failed" ; exit 42)
```

Now fail a test.

```bash
% echo "exit 1" > test.sh
% docker build -t foundation --target foundation .
=> ERROR [test 2/2] RUN (/bin/sh test.sh && echo "pass" > /tmp/result.txt) || (echo "Tests Failed" ; exit 42)                                                                                                  0.1s
------
 > [test 2/2] RUN (/bin/sh test.sh && echo "pass" > /tmp/result.txt) || (echo "Tests Failed" ; exit 42):
0.089 Tests Failed
------
Dockerfile:9
--------------------
   7 |     COPY test.sh /test.sh
   8 |     # Write /tmp/results.txt only if test passes
   9 | >>> RUN (/bin/sh test.sh && echo "pass" > /tmp/result.txt) || (echo "Tests Failed" ; exit 42)
  10 |
  11 |     # The stage we will actually release
--------------------
ERROR: failed to solve: process "/bin/sh -c (/bin/sh test.sh && echo \"pass\" > /tmp/result.txt) || (echo \"Tests Failed\" ; exit 42)" did not complete successfully: exit code: 42
```

Is that better? Well, it does say `Tests Failed`.

## Parallel tests

Docker runs the non-dependent stages of a multi-stage build [in parallel](https://docs.docker.com/build/guide/multi-stage/). Once the stages our tests depend on have built, the tests can run in parallel.

```Dockerfile
# The image we want to release after testing
FROM debian AS foundation_candidate
COPY . /config_files

# Our tests
FROM foundation_candidate AS test1
COPY test1.sh /test1.sh
# Write /tmp/results1.txt only if test passes
RUN /bin/sh test1.sh && echo "pass" > /tmp/result1.txt

FROM foundation_candidate AS test2
COPY test2.sh /test2.sh
# Write /tmp/results2.txt only if test passes
RUN /bin/sh test2.sh && echo "pass" > /tmp/result2.txt

# The stage we will actually release
FROM foundation_candidate AS foundation
# This will cause the `test1` and `test2` stages to build. 
# If either of those stages fail to write /tmp/resultN.txt,
# the relevant `COPY` will fail, and our Docker build will fail.
COPY --from=test1 /tmp/result1.txt /dev/null
COPY --from=test2 /tmp/result2.txt /dev/null
```

Run it as before, notice that test2 doesn't wait for test1 to finish.

```bash
% echo "sleep 2 && exit 0" > test1.sh
% echo "exit 0" > test2.sh
% docker build -t foundation --target foundation .
```

## Alternatives

We could stick with a dedicated CI `testing` phase using its own Dockerfile to import and test the one we're building. 

We can use features of our CI system to pass our artifact between phases.

More people can read Dockerfiles than can understand our CI system, and those people probably know how to `docker build` our `Dockerfile` on their dev machine, but they probably don't know how to execute our CI pipeline there.

## Advantages

- Easy to write and read, possibly much easier than alternate methods of testing.
- Tests [run in parallel](https://docs.docker.com/build/guide/multi-stage/).
- State doesn't leak between tests.
- Much better than not testing at all.

## Disadvantages

- Extra 5 bytes per test in our final image.
- Our tests run in our build phase, which can be confusing, especially in a CI pipeline.
- Totally custom. Any test output is unlikely to be easily parsed by standard tools.

## The Bottom Line

CI pipelines typically have a `testing` phase. If our build artifact doesn't fit well into our testing paradigm, we may end up writing a complex test just to "fit in" with a testing framework not designed for our artifact type. Or we may end up with no tests at all.

In those cases, we can leverage Docker's powerful built-in features to deliver tested artifacts to our customers.

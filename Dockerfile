FROM ruby:3.3
RUN apt update && apt install -yq less vim
RUN gem install bundler

COPY docs/Gemfile* /tmp
RUN cd /tmp && bundle

WORKDIR /docs
